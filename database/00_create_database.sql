-- =============================================================================
-- EduNestIO :: 00_create_database.sql
-- Creates the application database. Run as a PostgreSQL superuser / role that
-- can create databases. Connect to the 'postgres' maintenance DB first.
--
-- Usage (psql):
--   psql -U postgres -h localhost -p 5432 -f 00_create_database.sql
--
-- NOTE: CREATE DATABASE cannot run inside a transaction block or a DO block,
-- so creation is guarded by a \gexec trick that is a no-op if it already exists.
-- =============================================================================

SELECT 'CREATE DATABASE edunestio'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'edunestio')\gexec

-- After this, connect to the new database and run 01_schema.sql .. 07_test_data.sql:
--   \connect edunestio
