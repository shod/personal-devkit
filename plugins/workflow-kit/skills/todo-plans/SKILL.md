---
name: todo-plans
description: Read and write project plans and open questions to C:\Work\Dubz\todo-plans.md. Use this skill whenever the user wants to: add a task, note, or open question to the plan file; view or list existing items; mark something as done; or manage the todo-plans list. Trigger on phrases like "add to plans", "add to todo", "what's in our plans", "mark as done", "write down a question", "check plans".
---

# Todo Plans Skill

Manages the project plan file at `C:\Work\Dubz\todo-plans.md`.

All responses to the user must be in English.

## Operations

### Read / List
When the user wants to see current plans or questions:
1. Read `C:\Work\Dubz\todo-plans.md`
2. Display contents in a readable format, highlighting open items (`- [ ]`) and done items (`- [x]`)

### Add item
When the user wants to add a task, note, or open question:
1. Read the file first
2. Append the new item under the appropriate section:
   - Tasks/notes → under `## Tasks` (create section if absent)
   - Open questions → under `## Open Questions` (create section if absent)
3. Format: `- [ ] {item text}`
4. If the user provides context (e.g. "because of X", "related to Y"), add it as an indented note: `  - Context: {context}`
5. Confirm to the user what was added

### Mark as done
When the user wants to mark an item as complete:
1. Read the file
2. Find the matching item (fuzzy match on text)
3. Replace `- [ ]` with `- [x]`
4. Confirm to the user

### Edit / Remove
When the user wants to change or delete an item:
1. Read the file
2. Apply the change
3. Confirm

## Rules
- Always Read the file before writing to avoid overwriting content
- Preserve all existing sections and formatting
- Use the Edit tool for targeted changes; use Write only for full rewrites
- If the file doesn't exist, create it with a `# TODO Plans` header before adding content
