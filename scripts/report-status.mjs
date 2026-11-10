#!/usr/bin/env node
/**
 * report-status.mjs — parse PROJECT_STATUS.md and POST it to the Projects Dashboard.
 *
 * Usage:  node scripts/report-status.mjs [--file PROJECT_STATUS.md] [--target work] [--force] [--quiet] [--dry-run]
 *
 * Config file ~/.config/project-status/config.json:
 *   { "targets": { "default": { "url": "...", "token": "..." }, "work": { "url": "...", "token": "..." } } }
 * Target is chosen by --target, then `target:` in the front matter, then PROJECT_STATUS_TARGET, then "default".
 * Env vars PROJECT_STATUS_URL / PROJECT_STATUS_TOKEN override whatever the target says.
 *
 * Idempotent: the hash of the last sent payload is stored in .project-status.sent
 * next to the status file; unchanged content is not re-sent (use --force to override).
 * Requires Node 18+ (global fetch). No dependencies.
 */
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { homedir } from 'node:os';
import { join, dirname, resolve } from 'node:path';

const args = process.argv.slice(2);
const flag = (n) => args.includes(n);
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : d; };

const file = resolve(opt('--file', 'PROJECT_STATUS.md'));
const quiet = flag('--quiet');
const log = (...m) => { if (!quiet) console.log(...m); };

if (!existsSync(file)) {
  log(`[status] no ${file}, skipping`);
  process.exit(0);
}

// ---------- config ----------
let cfg = {};
const cfgPath = join(homedir(), '.config', 'project-status', 'config.json');
if (existsSync(cfgPath)) {
  try { cfg = JSON.parse(readFileSync(cfgPath, 'utf8')); } catch { /* ignore */ }
}
// ---------- parse ----------
const text = readFileSync(file, 'utf8').replace(/\r\n/g, '\n');
const fm = text.match(/^---\n([\s\S]*?)\n---\n?([\s\S]*)$/);
if (!fm) {
  console.error('[status] PROJECT_STATUS.md must start with a --- front matter block');
  process.exit(1);
}
const meta = {};
for (const line of fm[1].split('\n')) {
  const m = line.match(/^([A-Za-z_]+):\s*(.*?)\s*(?:#.*)?$/);
  if (m) meta[m[1]] = m[2].replace(/^["']|["']$/g, '');
}

const sections = {};
let current = null;
for (const line of fm[2].split('\n')) {
  const h = line.match(/^##\s+(.+?)\s*$/);
  if (h) { current = h[1].toLowerCase().replace(/[^a-z0-9]+/g, '_'); sections[current] = []; continue; }
  if (current) sections[current].push(line);
}
const sec = (k) => {
  const v = (sections[k] || []).map((l) => l.trim()).filter(Boolean).join(' ');
  return v === '—' || v === '-' ? '' : v;
};

// ---------- target (which dashboard) ----------
// Priority: --target flag > `target:` in front matter > PROJECT_STATUS_TARGET env > "default".
// Config file shape (either form works):
//   { "url": "...", "token": "..." }                                  — single target
//   { "targets": { "default": {url, token}, "work": {url, token} } } — several targets
const targetName = opt('--target', meta.target || process.env.PROJECT_STATUS_TARGET || 'default');
const targets = cfg.targets || (cfg.url ? { default: { url: cfg.url, token: cfg.token } } : {});
const target = targets[targetName] || {};
const url = process.env.PROJECT_STATUS_URL || target.url;
const token = process.env.PROJECT_STATUS_TOKEN || target.token || '';
if (!url && !flag('--dry-run')) {
  console.error(`[status] no URL for target "${targetName}" (set PROJECT_STATUS_URL or targets.${targetName}.url in ${cfgPath})`);
  process.exit(1);
}

const payload = {
  token,
  id: meta.id,
  project: meta.project,
  type: meta.type,
  status: meta.status,
  stage: meta.stage,
  repo: meta.repo,
  last_step: sec('last_step'),
  next_step: sec('next_step'),
  blocker: sec('blocker'),
  by: process.env.PROJECT_STATUS_BY || 'claude-code',
};
if (!payload.id) { console.error('[status] front matter needs an `id`'); process.exit(1); }

// ---------- change detection ----------
const { token: _t, ...forHash } = payload;
const hash = createHash('sha1').update(JSON.stringify(forHash)).digest('hex');
const sentPath = join(dirname(file), '.project-status.sent');
if (!flag('--force') && existsSync(sentPath) && readFileSync(sentPath, 'utf8').trim() === hash) {
  log('[status] unchanged, not sent');
  process.exit(0);
}

if (flag('--dry-run')) {
  console.log(JSON.stringify(forHash, null, 2));
  process.exit(0);
}

// ---------- send ----------
try {
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'text/plain;charset=utf-8' }, // avoids CORS preflight on Apps Script
    body: JSON.stringify(payload),
    redirect: 'follow',
  });
  const body = await res.text();
  let data;
  try { data = JSON.parse(body); } catch { data = { ok: false, error: body.slice(0, 200) }; }
  if (!data.ok) {
    console.error('[status] server error:', data.error);
    process.exit(1);
  }
  writeFileSync(sentPath, hash);
  log(`[status] ${payload.id} -> ${targetName}, row ${data.row}${data.created ? ' (new)' : ''}`);
} catch (err) {
  console.error('[status] send failed:', err.message);
  process.exit(1);
}
