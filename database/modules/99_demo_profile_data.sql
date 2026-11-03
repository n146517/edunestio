-- =============================================================================
-- EduNestIO :: Demo profile data (99_demo_profile_data.sql)
-- Fills a demo student's full profile (personal, guardian, address, academic)
-- so the Student Detail screen shows a realistic, fully-populated record instead
-- of empty "—" placeholders. LOCAL / DEMO ONLY. Idempotent and tenant-scoped (1).
-- Safe to re-run: it upserts a current academic year and updates the demo student
-- by admission number (no duplicate rows created).
-- =============================================================================

-- 1) Ensure a current academic year exists for tenant 1 ----------------------
INSERT INTO academics.academic_year (tenant_id, name, start_date, end_date, is_current)
SELECT 1, '2025 - 26', DATE '2025-04-01', DATE '2026-03-31', true
WHERE NOT EXISTS (
    SELECT 1 FROM academics.academic_year WHERE tenant_id = 1 AND name = '2025 - 26'
);

-- 2) Fill the demo student (Nishant, RVD-1002) with a complete profile --------
UPDATE academics.student s SET
    middle_name       = 'Kumar',
    gender            = 'Male',
    date_of_birth     = DATE '2012-03-12',
    email             = 'nishant.student@example.com',
    phone             = '+91 90000 11111',
    address_line1     = '123 Green Park',
    address_line2     = 'Gomti Nagar',
    city              = 'Lucknow',
    state             = 'Uttar Pradesh',
    postal_code       = '226010',
    country           = 'India',
    nationality       = 'Indian',
    blood_group       = 'B+',
    roll_number       = '1',
    admission_date    = DATE '2024-04-01',
    academic_year_id  = (SELECT academic_year_id FROM academics.academic_year
                          WHERE tenant_id = 1 AND name = '2025 - 26'),
    guardian_name     = 'Rajesh Nishant',
    guardian_relation = 'Father',
    guardian_phone    = '+91 98765 43210',
    guardian_alt_phone= '+91 91234 56789',
    guardian_email    = 'rajesh.nishant@example.com',
    updated_at        = now()
WHERE s.tenant_id = 1 AND s.admission_number = 'RVD-1002';

-- 3) Fill a second demo student (Maya Turner, RVD-1001) too -------------------
UPDATE academics.student s SET
    gender            = 'Female',
    date_of_birth     = DATE '2016-07-21',
    email             = 'maya.student@example.com',
    phone             = '+91 90000 22222',
    address_line1     = '45 Rose Avenue',
    address_line2     = 'Hazratganj',
    city              = 'Lucknow',
    state             = 'Uttar Pradesh',
    postal_code       = '226001',
    country           = 'India',
    nationality       = 'Indian',
    blood_group       = 'O+',
    roll_number       = '2',
    admission_date    = DATE '2023-04-01',
    class_id          = (SELECT class_id FROM academics.school_class WHERE tenant_id = 1 AND name = 'Grade 2'),
    section_id        = (SELECT section_id FROM academics.class_section WHERE tenant_id = 1 AND class_id = (SELECT class_id FROM academics.school_class WHERE tenant_id = 1 AND name = 'Grade 2') AND name = 'A'),
    academic_year_id  = (SELECT academic_year_id FROM academics.academic_year WHERE tenant_id = 1 AND name = '2025 - 26'),
    guardian_name     = 'Priya Turner',
    guardian_relation = 'Mother',
    guardian_phone    = '+91 99887 76655',
    guardian_alt_phone= '+91 98888 12345',
    guardian_email    = 'priya.turner@example.com',
    updated_at        = now()
WHERE s.tenant_id = 1 AND s.admission_number = 'RVD-1001';
