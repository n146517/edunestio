# EduNestIO — Modules & Permissions

## Roles (seeded)

SaaSSuperAdmin, SchoolAdmin, Principal, Accountant, AdmissionOfficer, Teacher,
ClassTeacher, Librarian, TransportManager, HRPayrollManager, Student, Guardian,
Receptionist.

`SaaSSuperAdmin` is a platform role (no single tenant) and bypasses tenant
permission checks for platform operations only; cross-tenant data access remains
explicit and audited.

## Permissions (current)

| Code | Module | Granted to (seed) |
|------|--------|-------------------|
| `platform.tenant.manage` | Platform | SaaSSuperAdmin |
| `student.view` | Student | SchoolAdmin, Principal, AdmissionOfficer, Receptionist, Teacher, ClassTeacher |
| `student.create` | Student | SchoolAdmin, Principal, AdmissionOfficer, Receptionist |
| `student.update` | Student | SchoolAdmin, Principal, AdmissionOfficer, Receptionist |
| `student.delete` | Student | SchoolAdmin, Principal |

Permissions are the real authorization boundary (checked via `[RequirePermission]`
on the server). Role→permission mapping lives in `06_seed_reference_data.sql`.
Adding a module means adding its permission rows + mappings there and the matching
constants in `Common/Security/Roles.cs`.

## Role matrix (Student module example)

| Action | SchoolAdmin | Principal | AdmissionOfficer | Receptionist | Teacher | Guardian |
|--------|:----:|:----:|:----:|:----:|:----:|:----:|
| View students | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| Create student | ✅ | ✅ | ✅ | ✅ | — | — |
| Update student | ✅ | ✅ | ✅ | ✅ | — | — |
| Deactivate student | ✅ | ✅ | — | — | — | — |

Future modules extend this matrix. See `implementation-status.md` for module status.

## Module list

All 27 brief modules are enumerated with current status in
[`implementation-status.md`](implementation-status.md). Implemented end-to-end:
**Student Records**. Partially scaffolded: Dashboard, Academic Setup, Settings,
SaaS Platform Admin, Audit. The rest are navigation placeholders pending their
vertical slice.
