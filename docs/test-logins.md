# Test logins (private repo, demo data only)

Password for all demo users: `Demo@12345`

This is the value of `Seed__DemoUserPassword` used in `docs/how-to-run.md`. The API seeder only applies it when users are first created. If your local database was seeded with a different value, that value is the password.

| Username | Password | Role | Tenant |
|----------|----------|------|--------|
| `superadmin` | `Demo@12345` | SaaSSuperAdmin | platform |
| `riverdale.admin` | `Demo@12345` | SchoolAdmin | Riverdale (1) |
| `riverdale.teacher` | `Demo@12345` | Teacher | Riverdale (1) |
| `hillside.admin` | `Demo@12345` | SchoolAdmin | Hillside (2) |

Do not reuse these credentials outside local testing.
