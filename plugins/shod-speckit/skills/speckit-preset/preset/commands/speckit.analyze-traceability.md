## Additional Detection Pass G: Traceability *(shod-speckit preset)*

Run this pass together with passes A–F in step 4, before producing the report.
It is read-only, like the rest of the analysis.

1. **Locate the product docs.** Read the "Product context" block in `CLAUDE.md` (or `AGENTS.md`)
   for the intent and PRD paths. Defaults: `docs/intent.md`, `docs/prd.md`.
   If neither file exists, skip this pass and add one line to the report:
   "Traceability: skipped — no intent/PRD in this project."
2. **Read the `## Traceability` section of spec.md.**
   - Section missing → finding, severity **MEDIUM**, category `Traceability`, "spec has no Traceability section".
   - Placeholders still present (text in `[...]` brackets) → **MEDIUM**, "Traceability not filled".
   - A line `N/A — no <file>` is valid when that file does not exist. Skip steps 3–4 for that line.
     If the file exists → **MEDIUM**, "Traceability marked N/A but <file> exists".
3. **Resolve every referenced ID** (G-x, SC-x, US-x, FR-x, NFR-x, §n) against the intent/PRD files.
   An ID that does not exist there → **HIGH**, "dangling reference".
   Load only the sections you need (progressive disclosure), not whole documents.
4. **Coverage.** Every PRD requirement listed under **PRD** must map to at least one requirement in
   spec.md and at least one task in tasks.md. Gaps → **HIGH**, "PRD item claimed but not implemented".
5. **Deferred items** must name a target feature (`→ feature NNN`). Missing target → **LOW**.

Add these findings to the same findings table (ID prefix `T`) and count them in the Metrics
section as "Traceability issues". Do not create a separate report.
