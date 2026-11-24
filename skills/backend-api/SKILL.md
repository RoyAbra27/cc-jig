---
name: backend-api
description: Build-time checklist for backend and API work in any framework (NestJS, Express, Fastify, FastAPI, Django, Go) - designing or changing an endpoint, controller, worker, queue job, cron, webhook, migration or service config. Use whenever you are about to write or change server-side code that takes requests, runs jobs or touches the schema, even if the user only says "add an endpoint", "add a column" or "the worker should retry", and when debugging framework DI, middleware, validation or shutdown behavior. Not for reviewing a finished branch (branch-audit) or choosing a library (buy-vs-build).
---

# Backend and API work

The model already knows backend engineering. This skill exists for the decisions that get skipped when the task sounds small, and for framework facts that go stale.

## 1. Versions first, facts from docs

Read the project's real versions (`package.json`, `pyproject.toml`, `go.mod`, lockfile) before saying anything version-specific. Framework APIs change between majors (NestJS 11 to 12 removed `HealthIndicator`; Express 5 changed wildcard routes), so confirm framework facts with context7 (`resolve-library-id`, then `query-docs`) at that version instead of from memory. If a reference file below matches the framework, read it.

- NestJS: `references/nestjs.md`

## 2. Decide these before writing the handler

Each one is cheap at design time and expensive after clients depend on it. Say in one line which apply and what you chose; skip the ones that don't.

1. **Contract and errors:** request and response shape, status codes, and one error body shape used everywhere. Validate input at the boundary and reject unknown fields.
2. **Authorization per route:** who may call it and on whose data (tenant or owner check in the query, not only a role guard).
3. **Idempotency:** what happens if the client or a queue retries the same request. Writes that can repeat need an idempotency key or a natural unique constraint.
4. **Pagination and limits:** any list endpoint gets a cursor or limit with a max; request body size has a cap.
5. **Timeouts and retries on outbound calls:** every call to another service has a timeout; retries only on idempotent calls, with backoff and a cap.
6. **Migrations stay backward-compatible:** the old code must run against the new schema during deploy. Add a column nullable or with a default, backfill, then enforce; rename or drop in a later release (expand, then contract). Add an index for every new query path.
7. **Jobs and queues:** what a job does if it runs twice, crashes halfway, or runs concurrently with itself; where failed jobs go and who sees them.
8. **Shutdown and health:** in-flight requests and jobs drain on SIGTERM; health checks don't hit rate limits or slow dependencies.
9. **Logs and data:** no tokens, passwords or personal data in logs, URLs, object keys or error bodies.
10. **Rate limits behind a proxy:** limit per identity, and trust the proxy's client-IP header only when the app actually sits behind that proxy.

## 3. Prove it

Write the endpoint's test at the contract level (status, body, the auth failure, the retry case) per the testing-workflow skill. For a migration, show it applies on a copy of current data, not only an empty database.

## Review is a different job

For a finished branch, the audit-time version of these checks lives in the branch-audit skill's `references/lanes.md` (`api-surface`, `data-path`). Do not copy them here.
