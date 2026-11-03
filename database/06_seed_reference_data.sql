-- =============================================================================
-- EduNestIO :: 06_seed_reference_data.sql
-- Default roles, permissions, and role->permission mappings. Idempotent.
-- No users or secrets here (users with hashed passwords are seeded by the app
-- via 07_test_data workflow / the API seeding endpoint, so no plaintext ever
-- appears in SQL).
-- =============================================================================

-- Roles -----------------------------------------------------------------------
INSERT INTO core.role (name, description) VALUES
 ('SaaSSuperAdmin',   'Platform administrator across all tenants'),
 ('SchoolAdmin',      'School owner/administrator within a tenant'),
 ('Principal',        'Principal'),
 ('Accountant',       'Finance and fees'),
 ('AdmissionOfficer', 'Admissions and enquiries'),
 ('Teacher',          'Teaching staff'),
 ('ClassTeacher',     'Class teacher'),
 ('Librarian',        'Library'),
 ('TransportManager', 'Transport'),
 ('HRPayrollManager', 'HR and payroll'),
 ('Student',          'Student portal'),
 ('Guardian',         'Parent/guardian portal'),
 ('Receptionist',     'Front desk')
ON CONFLICT (name) DO NOTHING;

-- Permissions -----------------------------------------------------------------
INSERT INTO core.permission (code, module, description) VALUES
 ('platform.tenant.manage', 'Platform', 'Manage tenants/subscriptions'),
 ('student.view',   'Student', 'View students'),
 ('student.create', 'Student', 'Create students'),
 ('student.update', 'Student', 'Update students'),
 ('student.delete', 'Student', 'Deactivate students')
ON CONFLICT (code) DO NOTHING;

-- Role -> permission mappings -------------------------------------------------
-- SaaSSuperAdmin: platform management (student perms are tenant-scoped; super
-- admin acts via explicit tenant context when needed).
INSERT INTO core.role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id
  FROM core.role r CROSS JOIN core.permission p
 WHERE r.name = 'SaaSSuperAdmin' AND p.code IN ('platform.tenant.manage')
ON CONFLICT DO NOTHING;

-- SchoolAdmin / Principal: full student CRUD within the tenant.
INSERT INTO core.role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id
  FROM core.role r CROSS JOIN core.permission p
 WHERE r.name IN ('SchoolAdmin','Principal')
   AND p.code IN ('student.view','student.create','student.update','student.delete')
ON CONFLICT DO NOTHING;

-- AdmissionOfficer / Receptionist: create + view + update.
INSERT INTO core.role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id
  FROM core.role r CROSS JOIN core.permission p
 WHERE r.name IN ('AdmissionOfficer','Receptionist')
   AND p.code IN ('student.view','student.create','student.update')
ON CONFLICT DO NOTHING;

-- Teacher / ClassTeacher: view only.
INSERT INTO core.role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id
  FROM core.role r CROSS JOIN core.permission p
 WHERE r.name IN ('Teacher','ClassTeacher')
   AND p.code IN ('student.view')
ON CONFLICT DO NOTHING;
