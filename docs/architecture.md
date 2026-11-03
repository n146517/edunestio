# EduNestIO — Architecture

## Pattern: Controller → BL → DA → stored functions

EduNestIO's backend mirrors the reference project's layering. Business logic stays
out of controllers; data access is isolated in DA classes that call PostgreSQL
stored functions.

```
HTTP request
  → Controller (RestAPI)         thin: reads UserContext from token, calls BL, shapes ApiResponse
  → BL (Business)                 new BL(); DBManagerDA.GetDBObject(DAType.X); try { call DA } finally { Release }
  → DA (DataAccess)               DAHelper.ExecuteTenantJson(DbMaster, "schema.fn", tenantId, payload)
  → PostgreSQL function            schema.fn(p_tenant_id int, p_payload jsonb) RETURNS jsonb
  ← jsonb envelope { result_code, message, data }
```

### Projects and dependency direction

```
RestAPI ─► Business ─► DataAccess ─► Common
   └──────────┴───────────┴──────────┘  (all reference Common)
```

- **EduNestIO.Common** — infrastructure substitutes and shared types: `DbMaster`
  (Npgsql connection wrapper), `DBBase` (DA base), `DBUtil`, `LogWriter` (structured
  logger), `AppConfig`, `ResultCodes`, DTOs/VOs, `PasswordHasher`, `Roles`/`Permissions`,
  `UserContext`. These are original replacements for the reference project's
  proprietary binary DLLs (connection pool, logger), preserving the same call shape.
- **EduNestIO.WebServices.DataAccess** — one `*DA` per area (`AuthDA`, `StudentDA`,
  `UserDA`, `CommonDA`) + `DAHelper`. DA methods are one-liners that invoke a stored
  function and return the deserialized envelope.
- **EduNestIO.WebServices.Business** — one `*BL` per area + `DBManagerDA` (the DA
  factory with the `DAType` enum). BL orchestrates DAs and applies app-side rules
  (e.g. PBKDF2 password verification in `AuthBL`).
- **EduNestIO.WebServices.RestAPI** — controllers, `Startup`/`Program`, auth handler,
  filters, middleware, `config/appsettings.json`.

## Data access contract

Every tenant-scoped function has the signature `fn(p_tenant_id integer, p_payload jsonb) RETURNS jsonb`
and returns `{ "result_code": int, "message": text, "data": json }` where
`result_code = 0` means success (maps to `Common.ResultCodes`). The DA layer passes
the tenant id as a parameter and the request as a jsonb payload — values never get
concatenated into SQL, so the design is injection-safe by construction.

## Request lifecycle (authenticated)

1. `CorrelationIdMiddleware` assigns `X-Correlation-ID`.
2. `TokenAuthenticationHandler` validates the bearer token against
   `core.fn_validate_session` and builds a `ClaimsPrincipal` (user id, tenant id,
   roles, permission claims).
3. `[RequirePermission(...)]` enforces the permission server-side (403 if missing).
4. The controller reads `UserContext` (tenant id **from the token**) and calls the BL.
5. The BL obtains a DA via `DBManagerDA`, calls the stored function with the tenant id,
   releases the DA in `finally`.
6. The stored function enforces tenant scoping again in SQL (defense in depth).
7. The controller maps the envelope's `result_code` to an HTTP status + `ApiResponse`.

## Multi-tenancy

Shared database, shared schema, `tenant_id` on every tenant-owned table. The tenant
is resolved from the authenticated session only. Functions re-verify ownership on
read and write; a guessed id from another tenant yields `NOT_FOUND` (404), never a
leak. See `security-and-privacy.md`.

## Frontend

Angular 21 (standalone, signals, zoneless). `core/` holds the auth store, typed API
client, and HTTP interceptors (bearer token + centralized error handling against the
`ApiResponse` envelope). `layout/` is the app shell (sidebar, top bar, user menu,
toasts). `features/` holds pages; planned modules show honest "coming soon"
placeholders. Route guards are UX only — the API is the authority.

## Cross-cutting

- **Errors**: `ServiceExceptionFilter` → consistent `ApiResponse` + correlation id; 5xx bodies never leak stack traces.
- **Logging**: `LogWriter` structured lines (console + daily file), correlation id, no secrets/PII.
- **Config/secrets**: `config/appsettings.json` (non-secrets) + environment variables; no secrets in source or bundle.
- **Numbering**: `core.fn_next_document_number` gives race-safe per-tenant sequences (admission numbers, future receipts/certificates).
