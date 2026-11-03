# EduNestIO — Security & Privacy

## Authentication
- ASP.NET Core custom bearer scheme (`EduNestToken`). Login verifies credentials with
  **PBKDF2 (Rfc2898, SHA-256, 100k iterations, per-user random salt)** — no custom
  crypto. On success an opaque random session token (48 bytes, URL-safe) is stored in
  `core.user_session` with an expiry and validated on every request.
- Login returns a single generic failure for unknown-user and wrong-password
  (no account enumeration). Account lockout fields (`failed_attempts`,
  `locked_until`) exist on `app_user` for future lockout enforcement.
- Tokens are bearer credentials; the SPA keeps them in `sessionStorage` (tab-scoped).
  Output encoding / CSP matter to limit XSS. A refresh-token flow is a documented
  future hardening.

## Authorization
- Server-side permission checks via `[RequirePermission("…")]` → 403 when missing.
  Frontend route guards are UX only.
- Roles map to permissions in the database (`role_permission`); configurable without
  code changes to the auth pipeline.

## Tenant isolation (defense in depth)
1. Tenant id comes only from the validated session token, never from client body/headers.
2. Controllers pass that tenant id to the BL/DA; stored functions take `p_tenant_id`.
3. Functions re-check tenant ownership on read and write. Cross-tenant access returns
   `NOT_FOUND` (404), so probing cannot confirm another tenant's records exist.
4. Writes stamp/validate `tenant_id` server-side; a tampered payload cannot target
   another tenant.
5. Automated tests assert a Tenant A user cannot read or update Tenant B's student
   (by guessed id or payload), and lists never cross tenants.

## Injection & input safety
- Data access passes values as a single **jsonb parameter** to stored functions;
  no SQL is built from user input → SQL injection is prevented by construction.
- Server-side validation on required fields; the API suppresses the default model
  binder error shape in favor of consistent `ApiResponse`.

## Secrets
- No secrets in source control or the frontend bundle. Connection strings, the demo
  seed password, and test DB connection are supplied via environment variables /
  `config/appsettings.json` (which ships empty for secret fields). `.env.example`
  documents the names with placeholders only.

## Logging & data handling
- Structured logs include a correlation id. Passwords, tokens, and hashes are never
  logged; payloads are logged at Detail level only and should exclude sensitive PII
  in production (raise `LogWriter.MinimumLevel`).
- `core.audit_log` is append-only for sensitive actions (actor, tenant, entity,
  before/after jsonb without secrets).

## Transport & deployment assumptions
- HTTPS/TLS is expected at the gateway/deployment layer. CORS is an allow-list
  (`Cors:AllowedOrigins`). Secure headers, rate limiting, and backup/restore are
  deployment concerns to configure per environment.

## Items requiring school/legal review
- Data retention, consent for guardian/student data, regional privacy obligations,
  and payment data handling (no card data is stored; gateways remain behind future
  adapter interfaces). EduNestIO does not claim legal compliance automatically.
