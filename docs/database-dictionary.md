# EduNestIO — Database Dictionary

Schemas: **core** (platform, identity, audit), **academics** (academic setup + students).
All timestamps are `timestamptz` (UTC). Money would use `NUMERIC` (no float). Scripts
in `/database`.

## Tables

### core.tenant
School tenant. `tenant_id` (PK), `name`, `code` (unique), `status`
(Active|Suspended|Trial), `subscription_plan`, `trial_ends_at`, `locale`,
`time_zone`, `currency_code`, `created_at`, `updated_at`.

### core.campus
Branch per tenant. `campus_id` (PK), `tenant_id` (FK), `name`, `code` (unique per
tenant), `address`, `is_primary`.

### core.app_user
Authenticatable user. `user_id` (PK), `tenant_id` (FK, NULL = platform super admin),
`username` (unique per tenant), `email`, `full_name`, `password_hash`,
`password_salt`, `is_active`, `failed_attempts`, `locked_until`, `last_login_at`.

### core.role / core.permission / core.role_permission / core.user_role
RBAC. `role` (`role_id`, `name` unique), `permission` (`permission_id`, `code`
unique, `module`), join tables `role_permission` and `user_role`.

### core.user_session
Opaque bearer tokens. `session_id` (PK), `user_id` (FK), `tenant_id`, `token`
(unique), `expires_at`, `revoked_at`.

### core.audit_log
Append-only. `audit_id` (PK), `tenant_id`, `actor_user_id`, `action`, `entity`,
`entity_id`, `correlation_id`, `changes` (jsonb), `created_at`.

### core.number_sequence
Per-tenant counters. PK `(tenant_id, seq_key)`, `prefix`, `next_value`, `padding`.

### academics.school_class / academics.class_section
Academic structure. `school_class` (`class_id`, `tenant_id`, `name` unique per
tenant, `ordinal`); `class_section` (`section_id`, `tenant_id`, `class_id`, `name`
unique per tenant+class).

### academics.student
Student master. `student_id` (PK), `tenant_id` (FK), `admission_number`
(**unique per tenant**), name fields, `gender`, `date_of_birth`, contact/address,
`class_id`/`section_id` (FK), `status` (Active|Inactive|Withdrawn|Graduated), audit
columns.

## Indexes (02_indexes.sql)
Tenant-leading indexes on users, campus, audit, classes, sections and students
(`(tenant_id, created_at)`, `(tenant_id, class_id)`, `(tenant_id, status)`,
name/admission search), plus session lookup indexes.

## Functions (03_functions.sql)
Signature: `fn(p_tenant_id integer, p_payload jsonb) RETURNS jsonb`; envelope
`{result_code, message, data}` (0 = success).

| Function | Purpose | Key payload | Edge cases |
|----------|---------|-------------|-----------|
| `core.fn_next_document_number` | Race-safe per-tenant sequence | `{seq_key}` | creates row on first use; atomic increment |
| `core.fn_authenticate` | Fetch user + hash/salt + roles/perms for login | `{username}` | returns to trusted server only; not found → code 4 |
| `core.fn_create_session` | Mint bearer token | `{user_id, token, minutes}` | updates last_login |
| `core.fn_validate_session` | Resolve token → context | `{token}` | expired/revoked → code 5 |
| `core.fn_upsert_user` | Idempotent user seed/admin | `{username,email,full_name,password_hash,password_salt,roles[]}` | existing user unchanged |
| `academics.fn_student_save` | Create/update student | StudentVO + `ActorUserId` | auto admission no; tenant-ownership check → code 8; duplicate → code 7 |
| `academics.fn_student_get` | Fetch one | `{student_id}` | cross-tenant guess → code 4 |
| `academics.fn_student_list` | Paged/filtered list | `{search,class_id,status,page,page_size}` | page_size capped 100 |
| `academics.fn_student_delete` | Soft delete (Inactive) | `{student_id}` | missing/other tenant → code 4 |
| `core.fn_write_audit` | Append audit record | `{actor_user_id,action,entity,entity_id,correlation_id,changes}` | — |

## Views (05_views.sql)
- `academics.vw_student_counts` — per-tenant totals by status (dashboard KPI).
- `academics.vw_class_strength` — active student count per class.

## Procedures (04_procedures.sql)
- `core.sp_purge_expired_sessions()` — maintenance; delete old sessions.

## Seed data
- `06_seed_reference_data.sql`: roles, permissions, mappings (idempotent, no users).
- `07_test_data.sql`: fictitious tenants (Riverdale/Hillside), classes, sections,
  demo students, numbering. Demo **users** are created by the API dev-seeder with
  hashed passwords (no plaintext in SQL).
