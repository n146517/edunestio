# EduNestIO — API Reference

Base URL (dev): `https://localhost:7265/api`. Interactive docs: `/swagger` (Development).

All responses use the envelope:

```json
{ "isSuccess": true, "resultCode": 0, "resultCodeDescription": "Success",
  "correlationId": "…", "data": { } }
```

Auth: send `Authorization: Bearer <token>` (token from `/auth/login`). The server
derives tenant and permissions from the token.

## Auth

### POST /api/auth/login  (anonymous)
Body: `{ "username": "riverdale.admin", "password": "…" }`
- `200` → `data` = LoginResult `{ token, expiresAtUtc, userId, tenantId, username, email, fullName, tenantName, roles[], permissions[] }`
- `400` missing fields · `401` invalid credentials (generic, no enumeration)

### GET /api/auth/me  (authenticated)
- `200` → `data` = `{ user_id, tenant_id, username, email, roles[], permissions[] }`
- `401` if no/invalid token

## Status

### GET /api/status  (anonymous)
- `200` → `data` = `{ status, service, server_time_utc }`

## Students

All require a bearer token; each action requires a permission. Tenant is implicit
(from token). Pagination: `page` (default 1), `pageSize` (default 20, max 100).

### GET /api/students  — perm `student.view`
Query: `search`, `classId`, `status`, `page`, `pageSize`.
- `200` → `data` = `{ items: Student[], page, page_size, total_count }`
- `401` / `403`

### GET /api/students/{id}  — perm `student.view`
- `200` → `data` = Student
- `404` if not found **or not in caller's tenant** (no existence leak)

### POST /api/students  — perm `student.create`
Body (StudentVO, PascalCase): `{ FirstName, LastName, Gender?, DateOfBirth?, Email?, Phone?, AddressLine1?, City?, State?, PostalCode?, ClassId?, SectionId?, AdmissionNumber?, Status? }`
(`AdmissionNumber` auto-generated if omitted.)
- `201` → `data` = `{ student_id, admission_number }`
- `400` validation · `409` duplicate admission number · `403`

### PUT /api/students/{id}  — perm `student.update`
Body: StudentVO (routed `id` wins).
- `200` → `data` = `{ student_id }`
- `404` if not found / other tenant · `403`

### DELETE /api/students/{id}  — perm `student.delete`
Soft delete (status → Inactive).
- `200` → `data` = `{ student_id }` · `404` · `403`

## Status codes & result codes

| HTTP | ResultCode | Meaning |
|------|-----------|---------|
| 200/201 | 0 SUCCESS | OK |
| 400 | 3 VALIDATION_ERROR | invalid input |
| 401 | 5 UNAUTHORIZED | missing/invalid token or bad credentials |
| 403 | 6 FORBIDDEN | authenticated but missing permission |
| 404 | 4 NOT_FOUND | missing or cross-tenant (no leak) |
| 409 | 7 DUPLICATE | tenant-unique conflict |
| 500 | 99 INTERNAL_SERVER_ERROR | unexpected (detail logged server-side only) |

Every response carries `correlationId` (also the `X-Correlation-ID` response header)
for support/tracing.
