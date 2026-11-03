-- =============================================================================
-- EduNestIO :: Module — Student self-view read permissions
-- (26_student_self_view.sql)
-- Lets a signed-in student/guardian see their OWN exams, report cards and
-- attendance on their profile. These are read-only permissions; every endpoint
-- is already tenant-scoped and the student portal only ever requests the
-- student's own id, so no cross-student data is exposed.
-- Idempotent. Apply after module 24 (exam.reportcard) and 12 (attendance).
-- =============================================================================

INSERT INTO core.role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id
  FROM core.role r CROSS JOIN core.permission p
 WHERE r.name IN ('Student','Guardian')
   AND p.code IN ('exam.view','exam.reportcard','attendance.view')
ON CONFLICT DO NOTHING;
