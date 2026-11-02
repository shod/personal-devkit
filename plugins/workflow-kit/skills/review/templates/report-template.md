# Review Report Template

The `review` skill fills in this template. Replace each `{placeholder}` with a real value.

---

## Template

```markdown
# Code Review: {Phase N | Task T0XX | Uncommitted changes}

**Date**: {YYYY-MM-DD}
**Feature**: {feature folder}
**Scope**: {git diff <base>...HEAD | task T0XX | working tree}
**Files reviewed**: {count}
**Rules loaded**: {list of review.rules skills | none}
**Rules not loaded**: {list | none}

## Summary

| Category | CRITICAL | WARNING | INFO |
|----------|----------|---------|------|
| Spec compliance | 0 | 0 | 0 |
| Correctness | 0 | 0 | 0 |
| Security | 0 | 0 | 0 |
| Performance | 0 | 0 | 0 |
| Test quality | 0 | 0 | 0 |
| Maintainability | 0 | 0 | 0 |
| Stack rules | 0 | 0 | 0 |
| **Total** | **0** | **0** | **0** |

## Must fix (CRITICAL)

1. {short title} — `path/to/file:line`

> If none: "No critical findings."

## Findings

### [CRITICAL] {short title}
- **Category**: {category}
- **File**: `path/to/file:line`
- **Problem**: {what is wrong and why it matters}
- **Recommendation**: {what to change}

{one block per finding, CRITICAL first, then WARNING, then INFO}

> If none: "No findings."

## Positives

- {what the change does well}

REVIEW_RESULT: critical={N} warning={N} info={N} report={path}
```

## Completion rules

1. Keep every category row in the summary table, also with zeros.
2. Sort findings by severity: CRITICAL, WARNING, INFO.
3. Each finding has a file and a line.
4. The `REVIEW_RESULT:` line is the last line of the report.
