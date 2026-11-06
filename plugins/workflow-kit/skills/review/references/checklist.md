# Review Checklist

Framework-agnostic checks. Stack-specific checks come from the skills in
`.claude-project.json` → `review.rules`.

**Priority:** constitution > project standards files > stack rules > this checklist.
If two rules conflict, the higher-priority source wins.

---

## 1. Spec compliance

- Each requirement of the reviewed tasks has code that implements it.
- The code does what the spec says, not a similar thing.
  Compare names, fields, status codes, limits and error cases with `spec.md` and the contracts.
- The code does not add behavior that the spec does not ask for.
- Each acceptance scenario of the reviewed tasks has a test.

## 2. Correctness

- Edge cases work: empty input, null, zero, one item, very large input, duplicates.
- Error paths work: the code handles failures of the database, the network and external APIs.
- No off-by-one errors in loops, ranges and pagination.
- No race conditions: two parallel requests cannot corrupt data.
- Transactions wrap writes that must succeed or fail together.
- Time zones and dates are correct.
- Money uses an exact type, not a float.

## 3. Security

- Every endpoint and action checks authorization, not only authentication.
- A user cannot read or change data of another user by changing an ID (IDOR).
- User input never goes into SQL, shell commands, file paths, templates or `eval` without escaping or binding.
- Input validation exists at the boundary (request, message, file upload).
- No secrets, tokens or passwords in code, logs or error messages.
- Responses and logs do not expose personal data or internal structure.
- Public endpoints have rate limits where the spec or constitution asks for them.

## 4. Performance

- No database query inside a loop (N+1).
- Large data sets use pagination, chunks or streaming.
- Slow work (emails, external API calls, reports) runs in the background where the project supports it.
- New queries on large tables use indexes.
- No blocking calls (sleep, long synchronous waits) in the request path.

## 5. Test quality

- Tests check behavior, not implementation details.
- Assertions check real values. A test that only checks "no exception" or "status 200" is weak.
- No test was weakened, skipped or deleted to make it pass.
- Tests cover the error paths, not only the happy path.
- Tests do not depend on order, time or external services without a fake.

## 6. Maintainability

- New code follows the patterns of sibling files. It does not add a second way to do the same thing.
- No duplicated logic in the diff.
- No dead code, commented-out code or debug output.
- No abstractions or options that the spec does not need.
- Names say what the thing does or holds.
