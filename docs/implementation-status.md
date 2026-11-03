# EduNestIO — Implementation Status

Honest status of every module from the brief. The product is built as a runnable
foundation + vertical slice first, then module-by-module. This file is the source
of truth for what is Done / Partial / Planned.

Legend: ✅ Done · 🟡 Partial · ⬜ Planned (scaffolded placeholder only)

## Platform foundation

| Area | Status | Notes |
|------|--------|-------|
| Solution structure (Controller → BL → DA) | ✅ | 5 projects, reference-style layering |
| PostgreSQL schema + stored functions (jsonb in/out) | ✅ | `/database` scripts; applied-to-live-DB pending (see README blocker) |
| Multi-tenancy (tenant derived from server session) | ✅ | Tenant never trusted from client; enforced in functions + API |
| Authentication (opaque bearer token, PBKDF2 hashing) | ✅ | `TokenAuthenticationHandler`, `AuthBL`, session table |
| Authorization (role + granular permission, server-side) | ✅ | `RequirePermission`; `RolePermissionMap` in DB seed |
| Centralized errors / ApiResponse / correlation id | ✅ | `ServiceExceptionFilter`, `CorrelationIdMiddleware` |
| Structured logging | ✅ | `LogWriter` (console + daily file) |
| Swagger/OpenAPI (dev) | ✅ | Bearer scheme wired |
| Angular app shell (sidebar, top bar, user menu, toasts, guards, interceptors) | ✅ | Rebranded EduNestIO |
| Dev seed (demo tenants/users, idempotent, no hard-coded secrets) | ✅ | `DevSeedBL` + `fn_upsert_user` |
| Automated tests (unit + tenant-isolation integration) | ✅ | **60 pass on live PostgreSQL 18** (EDUNESTIO_TEST_DB set) |
| Original SVG branding (logo, mark, favicon, module icons) | ✅ | `frontend/school-web/public/` + dashboard module-card grid |
| **Live DB verified** | ✅ | `/database` scripts applied to `edunestio` + `edunestio_test`; stored functions + end-to-end flows exercised |

## Core modules (from the brief)

| # | Module | Status | Notes |
|---|--------|--------|-------|
| — | **Student Records (vertical slice)** | ✅ | Full stack: tables + 4 stored functions + DA + BL + controller + Angular screen (list/search/paginate/create/deactivate) + tenant-isolation tests. Admission-number auto-generation, soft delete. |
| 1 | Dashboard & Analytics | 🟡 | Status KPI wired end-to-end; `vw_student_counts`/`vw_class_strength` views exist. Rich charts/role KPIs planned. |
| 2 | Student Records | ✅ | **Enhanced full module** (`modules/16`): list with **summary cards** (total/active/inactive/graduated/withdrawn), search (name/admission/roll/guardian phone), filters (class, section, academic year, status) from live master data, responsive table with avatar/roll/guardian/joined, pagination with total + page size. Dedicated **profile page** (overview, personal, academic, guardian, address, record history). **Create/Edit** form (sectioned: personal/academic/guardian/contact+address) with frontend+backend validation; admission number auto-generated on create and **kept stable on edit**; roll-number uniqueness + section-belongs-to-class validation. Explicit **status management** (Active/Inactive/Graduated/Withdrawn) with reason + audit, plus reactivate; deactivate is soft (Inactive), never a hard delete. New fields: roll_number, academic_year, admission_date, nationality, blood_group, guardian_*, country, photo_url. **Academic progression / enrollment history** (`modules/17`): each student keeps one record (stable admission number + id) with a per-class **enrollment history**; **Promote** (individual or bulk) closes the current class as *Promoted* and opens a new *Active* enrollment in the next class while the student stays Active (e.g. Grade 1 Promoted + Grade 2 Active shown on the profile's Class history); **Graduate** and **Withdraw** are terminal; a trigger auto-creates the first enrollment on admission. 22 student tests (7 new enrollment) incl. edit-preserves-admission, status change + reactivate, promote/graduate/withdraw, bulk promote, teacher 403, cross-tenant isolation. **Document upload is a flagged follow-up** (needs a secure file-storage subsystem — not yet implemented). |
| 3 | Admissions & Enquiry CRM | ✅ | Enquiries (auto-numbered), stage funnel, follow-ups, and **convert-to-student** (reuses `fn_student_save`) — full stack (`modules/11` + 6 stored fns + AdmissionDA/BL/Controller + Angular screen + 5 tests incl. convert + double-convert-409 + tenant isolation). |
| 4 | Academic Setup | ✅ | Academic years, classes, sections, subjects — full stack (schema `modules/10` + 8 stored fns + AcademicDA/BL/Controller + Angular tabbed screen + 4 tests). Timetable/curriculum mapping still planned. |
| 5 | Attendance | ✅ | Class-wise daily marking (Present/Absent/Late/Leave), bulk mark-all, monthly register, per-student history, today summary — full stack (`modules/12` + 5 stored fns + AttendanceDA/BL/Controller + Angular marking screen + 4 tests incl. cross-tenant student ignored). Period-mode/parent alerts planned. |
| 6 | Fees & Finance | ✅ | Fee heads, structures, per-student demands (discount), payments with **race-safe receipt numbering** + auto/explicit allocation, partial payments, student ledger/balances, payment reversal, defaulter list, collection report by mode. NUMERIC money end-to-end (`finance` schema, `modules/13` + 11 stored fns + FeeDA/BL/Controller + Angular tabbed screen + 5 tests incl. reverse + cross-tenant assign rejected). Scholarships/late-fee automation still planned. |
| 7 | Exams & Report Cards | ✅ | **Full 10-screen workflow** (`modules/14` + `18`–`22`): **multi-class exams** with exam type, academic year, start/end dates and description; a 4-step **Create Exam wizard** (Details → per-class Subjects with Theory/Practical + max/pass marks → per-subject Schedule → done); **dropdown-driven Marks Entry** (Exam→Class→Section→Subject) with absent flag, **Excel template export + import preview/validate** (ClosedXML); exam list with **status tabs** (Upcoming/Ongoing/Completed/Published derived from dates); **Result Preview** (per-student totals/%/grade/result + Ready/Missing counts) with a **publish guard** that blocks on missing marks unless overridden; **class-wise Report Cards** list + a **printable individual report card** (school header, student info, subject table, totals, grade, pass/fail, signatures). ExamDA/BL/Controller + Angular (exams list, wizard, marks-entry, results, report-cards, printable card) + 10 tests. Server-side PDF + ZIP bulk download are a flagged follow-up (browser print works now). |
| 8 | Homework & Assignments | ⬜ | Nav placeholder. |
| 9 | Timetable & Substitution | ⬜ | Nav placeholder. |
| 10 | Communication & Notifications | ⬜ | Nav placeholder. Provider adapter planned behind interface. |
| 11 | Parent & Student Portal | ⬜ | Roles (Student/Guardian) seeded; screens planned. |
| 12 | Teacher Portal | ⬜ | Teacher role seeded; screens planned. |
| 13 | Certificates & Documents | ⬜ | `number_sequence` reusable for document numbering. |
| 14 | Library | ⬜ | Planned. |
| 15 | Transport | ⬜ | Planned. |
| 16 | Staff & HR | ⬜ | Planned. |
| 17 | Payroll | ⬜ | Planned. |
| 18 | Inventory & Procurement | ⬜ | Planned. |
| 19 | Hostel (feature-flagged) | ⬜ | Planned, disabled. |
| 20 | Canteen (feature-flagged) | ⬜ | Planned, disabled. |
| 21 | Leave & Approvals | ⬜ | Planned. |
| 22 | Grievances & Helpdesk | ⬜ | Planned. |
| 23 | Reports & Exports | ⬜ | Planned. |
| 24 | Settings & Configuration | 🟡 | Tenant profile fields (locale/time zone/currency/numbering) exist in schema; UI planned. |
| 25 | SaaS Platform Admin | 🟡 | Tenant table + statuses + SaaSSuperAdmin role + cross-tenant guard exist; onboarding UI planned. |
| 26 | Audit & Compliance | 🟡 | `audit_log` table + `fn_write_audit` exist; systematic wiring across modules planned. |
| 27 | Import/Export | ⬜ | Planned. |

## Known limitations / not yet verified

- **Live-DB verified**: `/database` scripts (base + module migrations) applied to a
  running PostgreSQL 18 (`edunestio` + `edunestio_test`); all 60 backend tests pass
  against the real database, including tenant-isolation over real HTTP.
- **Exam report cards: server-side PDF generation and bulk ZIP download are a flagged
  follow-up.** The printable report card works today via the browser's Print / Save-as-PDF.
- **Student document upload/download is not yet implemented.** It requires a secure
  file-storage subsystem (authz-gated storage + download, type/size validation). The
  rest of the Students module (profile, filters, summary, create/edit, status) is
  complete and verified. Documents are a deliberate, flagged follow-up.
- Payment gateway, WhatsApp/SMS/email providers are intentionally behind future
  adapter interfaces; no real provider wired.
- No live GPS, no production deployment, no billing enforcement.

## How modules are added (each as a vertical slice)

1. Tables + indexes in `01_schema.sql` / `02_indexes.sql`.
2. `schema.fn_*` stored functions (jsonb in/out, tenant-scoped) in `03_functions.sql`.
3. `*DA` (calls functions) → register in `DBManagerDA.DAType` → `*BL` → `*Controller`
   with `[RequirePermission]`.
4. Angular feature + route + nav entry (replace the placeholder).
5. Tenant-isolation + permission tests.
6. Update this file.
