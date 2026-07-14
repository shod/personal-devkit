---
name: "graphify-spec-context"
description: "Ground a feature spec in the codebase knowledge graph before /speckit-specify writes it. Queries the existing graphify graph (or builds one) for code, modules and entities related to the feature, and returns a concise grounding context."
argument-hint: "(optional) the feature description; defaults to the description already in the conversation"
user-invocable: true
disable-model-invocation: false
---

## Purpose

This is the `before_specify` hook for spec-kit (registered in
`.specify/extensions.yml`). It is invoked automatically by `/speckit-specify`
before the specification is drafted. Its job is to feed the spec author the
relevant slice of the existing codebase from the graphify knowledge graph, so
requirements are grounded in what actually exists rather than invented.

This skill lives outside `.specify/integrations/*.manifest.json`, so a spec-kit
update never touches it.

## Input

The feature description is whatever the user typed after `/speckit-specify` in
this conversation. Use that text. If `$ARGUMENTS` is non-empty, prefer it.

```text
$ARGUMENTS
```

## Steps

1. **Locate the graph.** Check whether a `graphify-out/` directory exists at the
   repo root (or under the current feature/working path).

2. **Ground the spec:**
   - **If `graphify-out/` exists** — invoke the **graphify** skill (Skill tool,
     `skill: "graphify"`) treating the feature description as a *query*, not a
     rebuild. Ask it for: existing modules/files the feature would touch,
     related entities and their relationships, and any already-implemented
     behavior that overlaps with the requested feature.
   - **If `graphify-out/` does NOT exist** — invoke the **graphify** skill to
     build the graph for the relevant code path first (e.g. `backend/` and/or
     `client/`), then query it as above. If building is too costly for this
     run, say so explicitly and continue with a best-effort plain search
     instead of silently skipping.

3. **Summarize.** Produce a short, structured grounding block — this is the
   value the spec author consumes:

   ```markdown
   ## Knowledge-Graph Grounding (graphify)

   **Related existing code:** <files / modules>
   **Related entities:** <domain entities + relationships>
   **Overlapping behavior:** <already-implemented things to reuse or avoid duplicating>
   **Gaps / net-new:** <what the feature genuinely adds>
   ```

   Keep it tight — bullet points, no narration. If the graph yields nothing
   relevant, say so plainly so the author knows the feature is greenfield.

## Done When

- [ ] The graphify graph was queried (or built+queried, or explicitly reported
      as unavailable with a fallback).
- [ ] A `## Knowledge-Graph Grounding (graphify)` block was emitted for
      `/speckit-specify` to use when drafting the spec.
