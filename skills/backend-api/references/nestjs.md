# NestJS gotchas

Version-sensitive: these held on NestJS 11-12 (checked 2026-10-27). Confirm anything version-specific with context7 at the project's version.

## Structure and lifecycle
- Request order: middleware -> guards -> interceptors (before) -> pipes -> handler -> interceptors (after) -> exception filters. Put each concern where it runs.
- DEFAULT scope unless REQUEST scope is genuinely needed: it bubbles up the injection chain and costs a per-request instance. Request-scoped global enhancers fail at startup (11.2.8+).
- Circular dependency: read the chain in the error and restructure (shared module or events) first; `forwardRef()` on both sides last.
- Throw the built-in `HttpException` subclasses; map domain errors in an exception filter.

## Easy to miss
- `app.enableShutdownHooks()` is off by default. SIGTERM never fires on Windows. `app.close()` does not exit the process.
- Throttler `ttl` is milliseconds. Behind a proxy set `trust proxy` (Express) or `trustProxy` (Fastify). Multiple instances need shared storage (Redis).
- `ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true })` only works on DTO classes, not interfaces or types.
- With SWC: no type check unless `--type-check`; an `import type` erases a DI token, so inject a real class or `@Inject(TOKEN)`.
- Queues: `@nestjs/bullmq`; `@nestjs/bull` is in maintenance mode.
- Standalone workers and CLIs: `NestFactory.createApplicationContext(AppModule)`, then `await app.close()`.
- E2E tests: `Test.createTestingModule({ imports: [AppModule] })`, `.overrideProvider(...)`, `createNestApplication()` + `init()`, and `await app.close()` in `afterAll`.

## Debugging
1. **Can't resolve dependencies:** the provider is in the right module's `providers`, or exported and its module imported; `@Injectable()` present; check the `import type` case above.
2. **Route or middleware stopped matching after Nest 11:** Express 5 / Fastify 5 wildcard syntax (`*splat`).
3. **Guard or interceptor not firing:** binding level (method, controller, global via `APP_GUARD`) and context type (HTTP vs WS vs RPC).
4. **Hooks run in a new order after Nest 12:** hierarchy-level ordering; don't rely on cross-module hook order.
