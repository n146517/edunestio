# EduNestIO — School Management SaaS

Multi-tenant School Management SaaS. ASP.NET Core Web API (Controller → Business → DataAccess layering, PostgreSQL stored functions) + Angular + PostgreSQL.

> **Status:** runnable foundation + **7 complete vertical slices** (Student Records, Admissions, Academic Setup, Attendance, Fees & Finance, Exams & Report Cards, plus dashboard) verified against a live PostgreSQL 18 with **34 passing tests**. Remaining modules are tracked honestly in [`docs/implementation-status.md`](docs/implementation-status.md).
>
> **New to the project? Start with [`docs/how-to-run.md`](docs/how-to-run.md)** — setup, run, test, and the end-to-end request flow.

## Architecture at a glance

The backend follows a classic layered pattern (modeled on the provided reference project):

```
Controller  ──►  BL (Business)  ──►  DA (DataAccess)  ──►  PostgreSQL stored functions
  (HTTP)          (new BL(),           (raw Npgsql:            (schema.fn(tenant_id int,
                   DBManagerDA           select fn(@p0,@p1),     payload jsonb)
                   factory + finally     jsonb in / jsonb out)   RETURNS jsonb envelope)
                   Release)
```

- Data access calls **PostgreSQL functions** with a JSON payload and reads a JSON envelope `{ result_code, message, data }`. No ORM.
- `DBManagerDA.GetDBObject(DAType.X)` hands out DA objects; `ReleaseDBObject` returns the connection. Npgsql pools connections.
- The proprietary infrastructure DLLs from the reference project (connection pool, logger) are replaced with original, documented substitutes in `EduNestIO.Common` (`DbMaster`, `DBBase`, `LogWriter`).

```
backend/
  EduNestIO.slnx
  EduNestIO.Common/               # DbMaster, DBBase, DBUtil, LogWriter, DTOs/VOs, enums, security
  EduNestIO.WebServices.DataAccess/   # *DA.cs (call stored functions), DAHelper
  EduNestIO.WebServices.Business/     # *BL.cs, DBManagerDA (factory + DAType), DevSeedBL
  EduNestIO.WebServices.RestAPI/      # Controllers, Startup.cs, Program.cs, Auth, Filters, Middleware, config/
  EduNestIO.Tests/                    # xUnit: PasswordHasher + tenant-isolation integration
database/                         # 00..08 SQL scripts + README + apply-all.ps1
frontend/school-web/          # Angular 21 app (shell, auth, 7 feature modules)
docs/                             # architecture, modules-and-permissions, db dictionary, api-reference, ...
```

## Prerequisites

- .NET SDK 10
- Node.js 20+ and npm
- PostgreSQL 18 (16+ works; psql path in `apply-all.ps1` defaults can be overridden via `-PsqlPath`)

## Setup

### 1. Database (clean init)

```powershell
# Applies 00..07 in order; creates the 'edunestio' database if missing.
./database/apply-all.ps1 -DbPassword "<your-postgres-password>"
```

See [`database/README.md`](database/README.md) for the manual psql command sequence and execution order.

### 2. Backend secrets + run

The API reads `backend/EduNestIO.WebServices.RestAPI/config/appsettings.json` plus environment variables. Provide the DB connection and (for demo users) the seed password via environment — never commit secrets. See [`.env.example`](.env.example).

```powershell
$env:ConnectionStrings__Default = "Host=localhost;Port=5432;Database=edunestio;Username=postgres;Password=<pw>"
$env:ASPNETCORE_ENVIRONMENT = "Development"
$env:Seed__Enabled = "true"
$env:Seed__DemoUserPassword = "<demo password>"

dotnet run --project backend/EduNestIO.WebServices.RestAPI
```

- API: `https://localhost:7265` (http `http://localhost:5022`)
- Swagger (Development): `https://localhost:7265/swagger`
- Health/status: `GET /api/status`

On first Development run with seeding enabled, demo users are created with securely hashed passwords.

### 3. Frontend

```powershell
cd frontend/school-web
npm install
npm start           # http://localhost:4200
```

### Demo accounts (development seed; password = your `Seed__DemoUserPassword`)

| Username | Role | Tenant |
|----------|------|--------|
| superadmin | SaaSSuperAdmin | platform |
| riverdale.admin | SchoolAdmin | Riverdale (1) |
| riverdale.teacher | Teacher (view only) | Riverdale (1) |
| hillside.admin | SchoolAdmin | Hillside (2) |

Sign in as `riverdale.admin` vs `hillside.admin` to see tenant isolation — each only sees its own students.

## Build & test

```powershell
dotnet build backend/EduNestIO.slnx
# 34 tests; set EDUNESTIO_TEST_DB to run the DB-backed tenant-isolation suite
$env:EDUNESTIO_TEST_DB = "Host=localhost;Port=5432;Database=edunestio_test;Username=postgres;Password=<pw>"
dotnet test  backend/EduNestIO.slnx

cd frontend/school-web
npm run build
npm test -- --watch=false
```

## Environment variables

See [`.env.example`](.env.example). Key names: `EDUNESTIO_DB_CONNECTION` / `ConnectionStrings__Default`, `Seed__Enabled`, `Seed__DemoUserPassword`, `EDUNESTIO_TEST_DB`, `Cors__AllowedOrigins__0`, `ASPNETCORE_ENVIRONMENT`.

## Security notes

- Tenant id is derived from the authenticated session, never from client input. Stored functions re-check tenant ownership; cross-tenant access returns 404 (no existence leak).
- Passwords hashed with PBKDF2 (SHA-256). Data access uses parameterized jsonb (no SQL string building → no injection).
- No secrets in source or the frontend bundle. See [`docs/security-and-privacy.md`](docs/security-and-privacy.md).

## Live-DB verified

The `/database` SQL (base + all module migrations) is applied to a running
PostgreSQL 18 (`edunestio` + `edunestio_test`). All C# builds are clean and **34
tests pass** against the real database, including tenant-isolation over real HTTP.
Reproduce with `apply-all.ps1`, set `EDUNESTIO_TEST_DB`, and run `dotnet test`.
Details in [`docs/implementation-status.md`](docs/implementation-status.md).

## Documentation

- [`docs/architecture.md`](docs/architecture.md)
- [`docs/modules-and-permissions.md`](docs/modules-and-permissions.md)
- [`docs/database-dictionary.md`](docs/database-dictionary.md)
- [`docs/api-reference.md`](docs/api-reference.md)
- [`docs/security-and-privacy.md`](docs/security-and-privacy.md)
- [`docs/test-plan.md`](docs/test-plan.md)
- [`docs/implementation-status.md`](docs/implementation-status.md)
