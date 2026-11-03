# EduNestIO — How to Run, Test, and Use

A practical guide to get EduNestIO running locally, verify it end-to-end, and
understand how a request flows through the stack. Written for the current build
(PostgreSQL 18, 7 modules live, 34 automated tests passing).

---

## 1. What you need

| Tool | Version | Notes |
|------|---------|-------|
| .NET SDK | 10 | `dotnet --version` |
| Node.js + npm | 20+ | for the Angular app |
| PostgreSQL | 18 (16+ works) | running on `localhost:5432` |
| psql | ships with PostgreSQL | used by the apply script |

This machine's PostgreSQL: `localhost:5432`, user `postgres`, psql at
`C:\Program Files\PostgreSQL\18\bin\psql.exe`.

---

## 2. One-time database setup

The database holds **two** databases:

- `edunestio` — the app/dev database the API talks to.
- `edunestio_test` — a separate database the integration tests run against.

Each is built from the base scripts (`00`–`07`) plus every module migration under
`database/modules/*.sql`, applied in order. The scripts are **idempotent** — safe
to re-run.

### Option A — apply script (recommended for a clean build)

```powershell
# From the repo root. Creates 'edunestio' if missing, then applies 00..07 + modules.
./database/apply-all.ps1 -DbPassword "Angular@12345" -PsqlPath "C:\Program Files\PostgreSQL\18\bin\psql.exe"
```

To build the **test** database the same way, pass `-DbName`:

```powershell
# Create the test DB first (one time), then apply everything to it.
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -p 5432 -c "CREATE DATABASE edunestio_test;"
./database/apply-all.ps1 -DbPassword "Angular@12345" -DbName "edunestio_test" -PsqlPath "C:\Program Files\PostgreSQL\18\bin\psql.exe"
```

### Option B — apply a single module (what we do per slice)

```powershell
$psql = "C:\Program Files\PostgreSQL\18\bin\psql.exe"; $env:PGPASSWORD = "Angular@12345"
& $psql -U postgres -h localhost -p 5432 -d edunestio      -v ON_ERROR_STOP=1 -f database/modules/14_exams.sql
& $psql -U postgres -h localhost -p 5432 -d edunestio_test -v ON_ERROR_STOP=1 -f database/modules/14_exams.sql
```

A clean exit (`EXIT=0`) and `CREATE FUNCTION` / `INSERT` lines mean success.

---

## 3. Run the backend API

The API reads `backend/EduNestIO.WebServices.RestAPI/config/appsettings.json` plus
environment variables (section separator is `__`). Never hard-code secrets.

```powershell
$env:ConnectionStrings__Default = "Host=localhost;Port=5432;Database=edunestio;Username=postgres;Password=Angular@12345"
$env:ASPNETCORE_ENVIRONMENT = "Development"
$env:Seed__Enabled = "true"
$env:Seed__DemoUserPassword = "Demo@12345"   # choose any strong value; this becomes the demo login password

dotnet run --project backend/EduNestIO.WebServices.RestAPI
```

- API base: `https://localhost:7265` (or `http://localhost:5022`)
- Swagger (Development): `https://localhost:7265/swagger`
- Status probe: `GET /api/status`

On the first Development run with `Seed__Enabled=true`, demo users are created with
PBKDF2-hashed passwords (the plaintext is only ever the value you put in
`Seed__DemoUserPassword`).

> Note: `dotnet run` is a long-running process — run it in its own terminal, not
> inside a script that expects it to exit.

---

## 4. Run the frontend

```powershell
cd frontend/school-web
npm install        # first time only
npm start          # dev server at http://localhost:4200
```

The dev server proxies API calls to the backend. Open `http://localhost:4200` and
sign in with a demo account.

---

## 5. Demo accounts

Password for all = whatever you set in `Seed__DemoUserPassword` (e.g. `Demo@12345`).

| Username | Role | Tenant | What it shows |
|----------|------|--------|----------------|
| `superadmin` | SaaSSuperAdmin | platform | cross-tenant/platform scope |
| `riverdale.admin` | SchoolAdmin | Riverdale (1) | full access within tenant 1 |
| `riverdale.teacher` | Teacher | Riverdale (1) | view-only + marks — used to prove 403s |
| `hillside.admin` | SchoolAdmin | Hillside (2) | tenant 2 — proves isolation |

**Try the isolation story:** sign in as `riverdale.admin`, note the students /
exams / fees you see. Sign in as `hillside.admin` — you see a completely separate
set. Cross-tenant id probing returns 404, never another tenant's data.

Seed data in tenant 1: classes Grade 1 / Grade 2; student `RVD-0001` Ava Stone
(Grade 1); demo subjects Mathematics / English / Science / Social Studies.

---

## 6. Verify it (automated tests)

The integration tests spin up the API in-process and talk to the **test** database
over real HTTP. Point them at `edunestio_test`:

```powershell
$env:EDUNESTIO_TEST_DB = "Host=localhost;Port=5432;Database=edunestio_test;Username=postgres;Password=Angular@12345"
dotnet test backend/EduNestIO.slnx
```

Expected: **34 passed, 0 failed**. These cover, per module, at least:

- a happy-path end-to-end flow,
- a permission check (e.g. a teacher gets **403** creating an exam or publishing),
- tenant isolation / cross-tenant access returning **404**,
- a validation failure returning **400** (e.g. marks above the subject max).

If `EDUNESTIO_TEST_DB` is unset, the DB-backed tests no-op (pass) so the suite
still runs without a database.

Frontend build/test:

```powershell
cd frontend/school-web
npx ng build --configuration development
npm test -- --watch=false
```

---

## 7. How a request flows (end to end)

Every feature is a vertical slice through the same layers:

```
Angular feature component
   │  calls a typed service (HttpClient) → /api/<module>/...
   ▼
HTTP  (Bearer token in Authorization header)
   │
   ▼
Controller  (ASP.NET Core)         e.g. ExamController : BaseApiController
   │  [Authorize] + [RequirePermission("exam.manage")]   ← server-side authz
   │  CurrentUser.TenantId comes from the validated token, NEVER the client
   ▼
BL  (Business)                     e.g. ExamBL
   │  GetDBObject(DAType.Exam) factory  →  call  →  ReleaseDBObject in finally
   ▼
DA  (DataAccess)                   e.g. ExamDA
   │  DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_exam_save", tenantId, payload)
   │  raw Npgsql, parameterized:  select academics.fn_exam_save(@p0, @p1)   (@p1 = jsonb)
   ▼
PostgreSQL stored function         academics.fn_exam_save(p_tenant_id int, p_payload jsonb)
   │  re-validates tenant ownership of every id it touches
   │  returns a JSON envelope:  { result_code, message, data }
   ▼
BL/Controller map the envelope back to HTTP:
   result_code 0 → 200/201 ; 3 → 400 ; 4 → 404 ; 6 → 403 ; 7 → 409 ; 8 → 404 (no leak)
   wrapped in ApiResponse { isSuccess, data, resultCode, correlationId }
```

Key guarantees:

- **Tenant is derived from the session token**, re-checked inside every stored
  function. Cross-tenant access returns 404 so existence never leaks.
- **No ORM, no SQL string building.** Data goes in/out as `jsonb` via parameters,
  so there is no SQL-injection surface.
- **Authorization is server-side** via `[RequirePermission(...)]`; the Angular
  permission guards are UX only, not the security boundary.

### Result codes (envelope → HTTP)

| result_code | Meaning | HTTP |
|-------------|---------|------|
| 0 | Success | 200 (or 201 on create) |
| 3 | Validation error | 400 |
| 4 | Not found | 404 |
| 6 | Forbidden / not permitted | 403 |
| 7 | Duplicate | 409 |
| 8 | Tenant mismatch | 404 (no existence leak) |

---

## 8. Module tour (what's live today)

See [`implementation-status.md`](implementation-status.md) for the authoritative
status. Live, end-to-end modules you can click through:

1. **Dashboard** — module-card grid + a live student-count KPI.
2. **Student Records** — summary cards, search + filters (class/section/year/status),
   paginated table, full profile page, sectioned create/edit (auto admission number,
   kept stable on edit), and status management (graduate/withdraw/reactivate; soft
   deactivate). Document upload is a flagged follow-up.
3. **Admissions & Enquiry CRM** — enquiries (auto-numbered), stage funnel,
   follow-ups, and **convert enquiry → student**.
4. **Academic Setup** — academic years, classes, sections, subjects.
5. **Attendance** — class-wise daily marking, monthly register, history.
6. **Fees & Finance** — fee heads/structures, per-student demands, payments with
   race-safe receipt numbers, ledger/balances, reversals, defaulters.
7. **Exams & Report Cards** — exams per class, subjects with max/pass marks, marks
   entry, publish, and a computed report card (percentage, grade, pass/fail).

Each lives under `frontend/school-web/src/app/features/<module>/` with a matching
`core/services/<module>.service.ts`, a backend `*Controller`/`*BL`/`*DA`, and a
`database/modules/NN_<module>.sql` migration.

---

## 9. Troubleshooting

| Symptom | Fix |
|---------|-----|
| `password authentication failed` | Check the password in the connection string matches your Postgres `postgres` user. |
| Tests all no-op / 0 DB tests run | `EDUNESTIO_TEST_DB` is unset or points at a DB without the migrations. |
| `relation ... does not exist` on test run | The test DB is missing a module migration — re-apply `database/modules/*.sql` to `edunestio_test`. |
| 403 on an action you expect to work | The signed-in demo user's role lacks that permission (by design — try `riverdale.admin`). |
| psql "extra command-line argument" on Windows | JSON got mangled by PowerShell quoting — put the SQL in a file and use `-f`, not `-c`. |
| Port already in use (7265/5022/4200) | Stop the previous `dotnet run` / `ng serve`, or change the port. |

---

## 10. Docker (optional)

`docker-compose.yml` mounts the base scripts and every `database/modules/NN_*.sql`
into a Postgres container's init directory, so a fresh container comes up with the
full schema + all module migrations applied.
