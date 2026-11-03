-- =============================================================================
-- EduNestIO :: 07_test_data.sql
-- Clearly fictitious LOCAL demo data only. Safe to run after reference seed.
-- Demo USERS (with hashed passwords) are created by the API dev-seeder, not here,
-- so no plaintext credential ever appears in SQL. This file seeds tenants,
-- academic setup, numbering and a few demo students.
-- =============================================================================

-- Tenants (fixed ids for deterministic demos) --------------------------------
INSERT INTO core.tenant (tenant_id, name, code, status, subscription_plan, currency_code)
VALUES (1, 'Riverdale Demo School', 'riverdale', 'Active', 'Standard', 'USD'),
       (2, 'Hillside Demo Academy', 'hillside',  'Active', 'Standard', 'USD')
ON CONFLICT (tenant_id) DO NOTHING;
-- keep the serial in sync
SELECT setval(pg_get_serial_sequence('core.tenant','tenant_id'), GREATEST((SELECT max(tenant_id) FROM core.tenant),1));

INSERT INTO core.campus (tenant_id, name, code, is_primary) VALUES
 (1, 'Riverdale Main Campus', 'main', true),
 (2, 'Hillside Main Campus',  'main', true)
ON CONFLICT (tenant_id, code) DO NOTHING;

-- Number sequences for admission numbers -------------------------------------
INSERT INTO core.number_sequence (tenant_id, seq_key, prefix, next_value, padding) VALUES
 (1, 'admission_number', 'RVD-', 1001, 4),
 (2, 'admission_number', 'HSA-', 2001, 4)
ON CONFLICT (tenant_id, seq_key) DO NOTHING;

-- Academic setup --------------------------------------------------------------
INSERT INTO academics.school_class (tenant_id, name, ordinal) VALUES
 (1, 'Grade 1', 1), (1, 'Grade 2', 2), (1, 'Grade 3', 3),
 (2, 'Grade 1', 1), (2, 'Grade 2', 2)
ON CONFLICT (tenant_id, name) DO NOTHING;

INSERT INTO academics.class_section (tenant_id, class_id, name)
SELECT c.tenant_id, c.class_id, 'A' FROM academics.school_class c
ON CONFLICT (tenant_id, class_id, name) DO NOTHING;

-- Demo students (fictitious) --------------------------------------------------
INSERT INTO academics.student (tenant_id, admission_number, first_name, last_name, gender, date_of_birth, class_id, status)
SELECT 1, 'RVD-0001', 'Ava',   'Stone',  'Female', DATE '2016-04-12',
       (SELECT class_id FROM academics.school_class WHERE tenant_id=1 AND name='Grade 1'), 'Active'
WHERE NOT EXISTS (SELECT 1 FROM academics.student WHERE tenant_id=1 AND admission_number='RVD-0001');

INSERT INTO academics.student (tenant_id, admission_number, first_name, last_name, gender, date_of_birth, class_id, status)
SELECT 1, 'RVD-0002', 'Liam',  'Porter', 'Male', DATE '2015-09-03',
       (SELECT class_id FROM academics.school_class WHERE tenant_id=1 AND name='Grade 2'), 'Active'
WHERE NOT EXISTS (SELECT 1 FROM academics.student WHERE tenant_id=1 AND admission_number='RVD-0002');

INSERT INTO academics.student (tenant_id, admission_number, first_name, last_name, gender, date_of_birth, class_id, status)
SELECT 2, 'HSA-0001', 'Noah',  'Reyes',  'Male', DATE '2016-01-22',
       (SELECT class_id FROM academics.school_class WHERE tenant_id=2 AND name='Grade 1'), 'Active'
WHERE NOT EXISTS (SELECT 1 FROM academics.student WHERE tenant_id=2 AND admission_number='HSA-0001');
