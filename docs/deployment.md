# EduNestIO — Deployment

## Environments
- **Development**: local .NET + Node + PostgreSQL (or `docker-compose up db`).
  `ASPNETCORE_ENVIRONMENT=Development` enables Swagger and (optional) demo seeding.
- **Staging/Production**: Development-only features (Swagger, auto demo seeding) are
  off. Apply `/database` scripts as a release step; never auto-seed demo users.

## Local via Docker (database only)
```powershell
# Set POSTGRES_PASSWORD in your shell/.env first (see .env.example)
docker compose up -d db
# DB is created and initialized from /database/01..07 on first run.
```
Then run the API and frontend as in the root README.

## Backend
```powershell
dotnet publish backend/EduNestIO.WebServices.RestAPI -c Release -o ./publish
# Provide via environment (never in source):
#   ConnectionStrings__Default, ASPNETCORE_ENVIRONMENT=Production
#   (do NOT set Seed__Enabled in production)
```
Host behind a reverse proxy / gateway that terminates TLS. Configure
`Cors:AllowedOrigins` for the deployed SPA origin.

## Frontend
```powershell
cd frontend/school-web
npm ci
npm run build        # outputs dist/school-web (production config -> apiBaseUrl '/api')
```
Serve the static `dist` behind the same origin as the API (or configure CORS) so the
SPA's `/api` base resolves to the backend.

## Database releases
- All schema changes go through the numbered scripts in `/database` (version
  controlled). Apply in order; `apply-all.ps1` automates it for a clean DB.
- Back up before applying changes; `08_rollback_or_down.sql` drops schema objects
  (dev only).

## Operational
- Health/status: `GET /api/status`.
- Logs: structured lines to console + daily files under the configured `LogDirectory`.
- Expired sessions can be purged via `core.sp_purge_expired_sessions()` on a schedule.

## Not included (document before go-live)
Secrets manager wiring, HTTPS certificates, rate limiting, WAF, automated backups,
monitoring/alerting, and a production CI/CD pipeline are environment-specific and not
configured in this repository.
