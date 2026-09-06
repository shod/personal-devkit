---
name: flutter-best-practices
description: Flutter/Dart conventions for a thin-client mobile app talking to a Laravel API. Use when writing, reviewing, or refactoring Dart/Flutter code — screens, providers/state, API/DTO layer, SSE streaming, or Patrol E2E tests. Encodes the "smart backend, thin client" contract.
---

# Flutter best practices (thin client over a Laravel API)

Apply these when writing or reviewing Flutter/Dart in this monorepo's mobile app.
They encode the project constitution: business logic lives in Laravel; Flutter
renders state and collects input.

## Architecture
- **Thin client.** No business rules in Dart that the server doesn't re-check —
  question limits, entitlement/subscription state, prediction generation, prompt
  building all belong to the backend. The client displays results and gathers input.
- **Layering.** `presentation` (widgets/screens) → `application` (state:
  providers/notifiers) → `data` (repositories) → `api` (HTTP client + DTOs).
  Widgets never call the HTTP client directly.
- **One HTTP client** with the Sanctum bearer token + Firebase App Check header
  attached by an interceptor. Never read/store secrets (LLM/SMS/payment keys) in
  the client — it only ever holds the user's Sanctum token, in secure storage.

## Contracts & DTOs
- DTOs mirror the OpenAPI contract in `specs/NNN-*/contracts/`. Generate or
  hand-write them against the contract; when the contract changes, the DTO changes.
- Parse the single error shape `{ "error": { "code", "message" } }` in one place
  and map to typed failures — don't scatter `response.statusCode` checks in widgets.

## Streaming (mandatory UX for AI)
- LLM answers arrive as **SSE** and must render token-by-token. A 10s spinner
  instead of a stream is a defect. Use a streamed response reader; expose the
  partial text through the notifier so the widget rebuilds incrementally.
- Handle mid-stream cancel/disconnect and the idempotency key
  (`client_message_id`) on retry.

## State management
- Keep state objects immutable; expose read-only views to widgets. Prefer a
  single source of truth per screen. (Pick one of Riverpod / Bloc for the repo and
  stay consistent — do not mix paradigms across features.)

## Layout: survives long text and font scale
- **Size from the text, not from a character count.** Never `width = digits * 22.0`
  and never a magic constant sized on one device. Measure the real string
  (`TextPainter`) or let the framework lay it out.
- **Respect `MediaQuery.textScalerOf(context)`.** A box that fits at 1.0x breaks at
  the 1.8x-2.0x scale users actually enable in system settings.
- **Everything that can overflow either scrolls or truncates.** `maxLines` +
  `TextOverflow.ellipsis` for text; a scroll view for any column that can exceed the
  viewport - especially with the keyboard open. `RenderFlex overflow` in any state is
  a defect, not cosmetics.
- **Focus must not change geometry.** Signal focus with colour, not with border
  thickness: growing a border 1px -> 2px steals inner width and re-wraps the label.
- Fixed-width children inside a `Row` need `Flexible`/`Expanded`; bottom sheets wrap
  their body in `Flexible(SingleChildScrollView(...))`, never a fixed height.
- Prove it: pump the widget at `TextScaler.linear(1.0)`, `1.3` and `1.85`, assert
  `tester.takeException()` is null and that geometry is stable across focus.

## Screen states: loading, ready, empty, failed
- **Every request reaches a terminal state.** A `catch` that returns without settling
  leaves `loading` with no result forever - the classic infinite spinner. Settle in
  `finally`, or set an explicit failure state.
- **`empty` and `failed` are different states with different UI.** "Nothing yet" must
  never render the same as "the request died".
- **Failure with nothing to show:** message + retry action. **Failure with something
  already rendered** (cache): keep the old result, show a non-blocking banner.
- **Never show a third-party SDK's own error string to the user.** Map provider
  errors (Firebase, billing, network) to localized keys; the raw text goes to the log
  and crash reporter.
- Polling and streaming screens need a terminal condition and a retry cap. "Keep
  reconnecting" is not a state.

## Testing pyramid (per constitution V)
- **unit** — provider/notifier logic, DTO parsing, failure mapping.
- **widget** — key screens (chat, paywall) with fake repositories.
- **golden** — only for stabilized screens; do not gold unstable UI.
- **E2E — Patrol, not Playwright.** Playwright does not drive native Flutter.
  E2E runs against staging with fake external services (LLM/SMS/payments behind
  interfaces). Assert real flows, not implementation detail.

## Review checklist
- [ ] No business rule enforced only on the client
- [ ] No secret/API key in Dart or compiled artifact; only the Sanctum token, in secure storage
- [ ] DTOs match the current contract; errors mapped in one place
- [ ] AI responses stream token-by-token (no blocking spinner)
- [ ] No size derived from a character count or magic constant; long text scrolls or ellipsises
- [ ] Widget pumped at textScaler 1.0 / 1.3 / 1.85 - no overflow, geometry stable on focus
- [ ] Loading always settles; empty is not the same state as failed; failure shows message + retry
- [ ] No raw SDK/server error string shown to the user - localized key only
- [ ] E2E written with Patrol; external services faked
