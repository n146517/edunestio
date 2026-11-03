-- =============================================================================
-- EduNestIO :: 04_procedures.sql
-- Stored PROCEDURES are used only where they add genuine value over functions
-- (e.g. multi-statement maintenance with transaction control). The application's
-- read/write business logic uses jsonb FUNCTIONS (03_functions.sql) which compose
-- better with the DA layer. No business procedures are required for the current
-- scope; this file is a placeholder kept for execution-order consistency.
-- =============================================================================

-- Example maintenance procedure: purge expired sessions (callable by a scheduler).
CREATE OR REPLACE PROCEDURE core.sp_purge_expired_sessions()
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM core.user_session WHERE expires_at < now() - interval '1 day';
END;
$$;
