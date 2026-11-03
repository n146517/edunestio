# EduNestIO Database

Version-controlled PostgreSQL scripts. Run in order against a clean database.

## Execution order

| Order | File | Purpose |
|-------|------|---------|
| 0 | `00_create_database.sql` | Create the `edunestio` database (run on the `postgres` maintenance DB) |
| 1 | `01_schema.sql` | Schemas, tables, keys, constraints |
| 2 | `02_indexes.sql` | Indexes (FK, tenant filtering, search) |
| 3 | `03_functions.sql` | Business functions (jsonb in/out) |
| 4 | `04_procedures.sql` | Maintenance procedures |
| 5 | `05_views.sql` | Reporting/dashboard views |
| 6 | `06_seed_reference_data.sql` | Roles, permissions, mappings (idempotent) |
| 7 | `07_test_data.sql` | Fictitious local demo tenants/classes/students |
| — | `08_rollback_or_down.sql` | Drop everything (dev only) |

## Commands (psql)

```bash
# 1) create the database (enter the postgres password when prompted)
psql -U postgres -h localhost -p 5432 -f 00_create_database.sql

# 2) run the rest against the new database, in order
psql -U postgres -h localhost -p 5432 -d edunestio -f 01_schema.sql
psql -U postgres -h localhost -p 5432 -d edunestio -f 02_indexes.sql
psql -U postgres -h localhost -p 5432 -d edunestio -f 03_functions.sql
psql -U postgres -h localhost -p 5432 -d edunestio -f 04_procedures.sql
psql -U postgres -h localhost -p 5432 -d edunestio -f 05_views.sql
psql -U postgres -h localhost -p 5432 -d edunestio -f 06_seed_reference_data.sql
psql -U postgres -h localhost -p 5432 -d edunestio -f 07_test_data.sql
```

A helper script `apply-all.ps1` (Windows) runs all of the above in one go.

## Conventions

- `snake_case` identifiers; `timestamptz` stored in UTC.
- `NUMERIC`/`DECIMAL` for money (never floating point).
- Tenant-scoped uniqueness (e.g. admission number unique per tenant).
- Every tenant business function signature: `fn(p_tenant_id integer, p_payload jsonb) RETURNS jsonb`.
- Return envelope: `{ "result_code": int, "message": text, "data": json }` where `result_code = 0` is success.

## Demo users

Demo users (with securely hashed passwords) are created by the **API dev-seeder** on first run (Development only), so no plaintext credential appears in any SQL file. See the root `README.md` for demo logins.
