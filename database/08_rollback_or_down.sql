-- =============================================================================
-- EduNestIO :: 08_rollback_or_down.sql
-- Destructive. Drops all EduNestIO schema objects. Use only on local/dev.
-- Order: drop schemas with CASCADE removes tables, views, functions, procedures.
-- =============================================================================

DROP SCHEMA IF EXISTS academics CASCADE;
DROP SCHEMA IF EXISTS core CASCADE;

-- To drop the database entirely (run from the 'postgres' maintenance DB):
--   DROP DATABASE IF EXISTS edunestio;
