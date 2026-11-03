# EduNestIO — Test Plan & Results

## Automated tests (backend, xUnit)

Project: `backend/EduNestIO.Tests`. Run: `dotnet test backend/EduNestIO.slnx`.

### Unit (no database) — PasswordHasherTests
| Test | Asserts |
|------|---------|
| Hash then Verify succeeds | Correct password verifies |
| Verify fails for wrong password | Wrong password rejected |
| Each hash uses a unique salt | Salts (and derived keys) differ for same password |
| Session tokens unique & URL-safe | No `+ / =`, unique per call |

### Integration (require a test DB) — StudentTenantIsolationTests
Run fully when `EDUNESTIO_TEST_DB` points at a database that has `/database` scripts
applied; otherwise they no-op (pass) and this is called out below.

| Test | Asserts |
|------|---------|
| Status endpoint is public | 200 without auth |
| Anonymous cannot list students | 401 |
| Invalid login returns 401 (generic) | No enumeration |
| Admin lists only own tenant | Every row `tenant_id == 1` |
| Teacher cannot create student | 403 (view-only role) |
| **Tenant A creates, Tenant B cannot see/fetch** | B `GET /students/{id}` → 404; not in B's list |
| **Tenant B cannot update Tenant A student** | PUT → 404 (no leak) |

## Actual results (this environment)

```
dotnet test backend/EduNestIO.slnx
Passed! - Failed: 0, Passed: 11, Skipped: 0, Total: 11
```

- The 4 PasswordHasher tests executed for real and passed.
- The 7 integration tests passed as no-ops because `EDUNESTIO_TEST_DB` was not set
  (no reachable/credentialed PostgreSQL in this environment). They are written to
  exercise the full HTTP + DB + tenant-isolation path when a test DB is provided.

Frontend: `npm run build` (production) and `npm test -- --watch=false` succeed.

## Critical flows coverage

| Flow | Covered by |
|------|-----------|
| Login | Integration (valid admin login in LoginAsync; invalid → 401) |
| Tenant separation | Integration (A/B isolation on read, list, update) |
| Create student | Integration (admin create → 201) |
| Role restriction | Integration (teacher create → 403) |
| Password security | Unit (PBKDF2 hash/verify) |

Not yet automated (planned with their modules): convert enquiry → admission, mark
attendance, create fee demand + receipt, enter marks + publish report card, library
issue/return, report export.

## How to run the DB-backed suite

```powershell
# 1. Apply scripts to a test database
./database/apply-all.ps1 -DbPassword "<pw>" -DbName edunestio_test
# 2. Point tests at it and run
$env:EDUNESTIO_TEST_DB = "Host=localhost;Port=5432;Database=edunestio_test;Username=postgres;Password=<pw>"
dotnet test backend/EduNestIO.slnx
```
