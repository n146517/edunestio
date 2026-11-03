-- =============================================================================
-- EduNestIO :: Module — Report-card permission + Teacher scoping
-- (24_exam_reportcard_permission.sql)
-- Adds a dedicated 'exam.reportcard' permission so Report Cards can be granted
-- independently of the full Exams view. Re-scopes the Teacher / ClassTeacher
-- roles to ONLY Marks Entry (exam.marks) and Report Cards (exam.reportcard):
-- they no longer get exam.view, so the Examination list and Results pages are
-- hidden from them. Admin roles (SchoolAdmin / Principal) also get the new
-- permission. Idempotent. Apply after module 14 (exams) and 06 seed.
-- =============================================================================

-- 1) New permission ----------------------------------------------------------
INSERT INTO core.permission (code, module, description) VALUES
 ('exam.reportcard', 'Exam', 'View and generate student report cards')
ON CONFLICT (code) DO NOTHING;

-- 2) Admin roles get report-card access too ----------------------------------
INSERT INTO core.role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id
  FROM core.role r CROSS JOIN core.permission p
 WHERE r.name IN ('SchoolAdmin','Principal') AND p.code = 'exam.reportcard'
ON CONFLICT DO NOTHING;

-- 3) Teachers: grant marks + report card, plus read-only academic data so the
--    class/section dropdowns on those screens can load.
INSERT INTO core.role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id
  FROM core.role r CROSS JOIN core.permission p
 WHERE r.name IN ('Teacher','ClassTeacher') AND p.code IN ('exam.marks','exam.reportcard','academic.view')
ON CONFLICT DO NOTHING;

-- 4) Teachers: remove the broad exam.view so they can't open Examination /
--    Results (they keep marks + report card only). Safe + reversible.
DELETE FROM core.role_permission rp
 USING core.role r, core.permission p
 WHERE rp.role_id = r.role_id AND rp.permission_id = p.permission_id
   AND r.name IN ('Teacher','ClassTeacher')
   AND p.code = 'exam.view';
