-- ============================================================================
-- KELASAGARA BIOMATCH (v17) - ALL 31 KARNATAKA DISTRICTS ADJACENCY SEED
-- Includes official 2023-2026 nomenclature (Vijayanagara KA-31, Kalaburagi,
-- Belagavi, Vijayapura, Shivamogga, Chikkamagaluru, Tumakuru, Ballari)
-- ============================================================================

CREATE TABLE IF NOT EXISTS karnataka_districts (
    district_code VARCHAR(8) PRIMARY KEY,
    district_name_en VARCHAR(64) NOT NULL UNIQUE,
    district_name_kn VARCHAR(64) NOT NULL,
    revenue_division VARCHAR(32) NOT NULL,
    -- Self-inclusive adjacency list: [own_code, ...bordering_district_codes]
    adjacent_districts VARCHAR(8)[] NOT NULL
);

TRUNCATE TABLE karnataka_districts CASCADE;

INSERT INTO karnataka_districts (
    district_code,
    district_name_en,
    district_name_kn,
    revenue_division,
    adjacent_districts
) VALUES
-- ----------------------------------------------------------------------------
-- 1. BENGALURU REVENUE DIVISION (9 Districts)
-- ----------------------------------------------------------------------------
('KA-01', 'Bengaluru Urban', 'ಬೆಂಗಳೂರು ನಗರ', 'Bengaluru',
 ARRAY['KA-01', 'KA-02', 'KA-29']),

('KA-02', 'Bengaluru Rural', 'ಬೆಂಗಳೂರು ಗ್ರಾಮಾಂತರ', 'Bengaluru',
 ARRAY['KA-02', 'KA-01', 'KA-29', 'KA-06', 'KA-27', 'KA-19']),

('KA-29', 'Ramanagara', 'ರಾಮನಗರ', 'Bengaluru',
 ARRAY['KA-29', 'KA-01', 'KA-02', 'KA-06', 'KA-11']),

('KA-27', 'Chikkaballapura', 'ಚಿಕ್ಕಬಳ್ಳಾಪುರ', 'Bengaluru',
 ARRAY['KA-27', 'KA-02', 'KA-19', 'KA-06']),

('KA-19', 'Kolar', 'ಕೋಲಾರ', 'Bengaluru',
 ARRAY['KA-19', 'KA-02', 'KA-27']),

('KA-06', 'Tumakuru', 'ತುಮಕೂರು', 'Bengaluru',
 ARRAY['KA-06', 'KA-02', 'KA-29', 'KA-27', 'KA-11', 'KA-13', 'KA-16', 'KA-31']),

('KA-16', 'Chitradurga', 'ಚಿತ್ರದುರ್ಗ', 'Bengaluru',
 ARRAY['KA-16', 'KA-06', 'KA-13', 'KA-14', 'KA-17', 'KA-31', 'KA-18']),

('KA-17', 'Davanagere', 'ದಾವಣಗೆರೆ', 'Bengaluru',
 ARRAY['KA-17', 'KA-16', 'KA-14', 'KA-15', 'KA-26', 'KA-31']),

('KA-14', 'Shivamogga', 'ಶಿವಮೊಗ್ಗ', 'Bengaluru',
 ARRAY['KA-14', 'KA-17', 'KA-16', 'KA-13', 'KA-20', 'KA-21', 'KA-15']),

-- ----------------------------------------------------------------------------
-- 2. MYSURU REVENUE DIVISION (8 Districts)
-- ----------------------------------------------------------------------------
('KA-09', 'Mysuru', 'ಮೈಸೂರು', 'Mysuru',
 ARRAY['KA-09', 'KA-11', 'KA-10', 'KA-12', 'KA-13']),

('KA-11', 'Mandya', 'ಮಂಡ್ಯ', 'Mysuru',
 ARRAY['KA-11', 'KA-09', 'KA-29', 'KA-06', 'KA-13']),

('KA-10', 'Chamarajanagara', 'ಚಾಮರಾಜನಗರ', 'Mysuru',
 ARRAY['KA-10', 'KA-09', 'KA-11', 'KA-29']),

('KA-12', 'Kodagu', 'ಕೊಡಗು', 'Mysuru',
 ARRAY['KA-12', 'KA-09', 'KA-13', 'KA-21']),

('KA-13', 'Hassan', 'ಹಾಸನ', 'Mysuru',
 ARRAY['KA-13', 'KA-09', 'KA-11', 'KA-06', 'KA-16', 'KA-14', 'KA-21', 'KA-12']),

('KA-15', 'Chikkamagaluru', 'ಚಿಕ್ಕಮಗಳೂರು', 'Mysuru',
 ARRAY['KA-15', 'KA-14', 'KA-17', 'KA-16', 'KA-13', 'KA-21', 'KA-20']),

('KA-21', 'Dakshina Kannada', 'ದಕ್ಷಿಣ ಕನ್ನಡ', 'Mysuru',
 ARRAY['KA-21', 'KA-20', 'KA-15', 'KA-13', 'KA-12']),

('KA-20', 'Udupi', 'ಉಡುಪಿ', 'Mysuru',
 ARRAY['KA-20', 'KA-21', 'KA-15', 'KA-14', 'KA-24']),

-- ----------------------------------------------------------------------------
-- 3. BELAGAVI REVENUE DIVISION (7 Districts)
-- ----------------------------------------------------------------------------
('KA-22', 'Belagavi', 'ಬೆಳಗಾವಿ', 'Belagavi',
 ARRAY['KA-22', 'KA-24', 'KA-25', 'KA-26', 'KA-23', 'KA-28']),

('KA-23', 'Bagalkote', 'ಬಾಗಲಕೋಟೆ', 'Belagavi',
 ARRAY['KA-23', 'KA-22', 'KA-28', 'KA-04', 'KA-07', 'KA-26']),

('KA-28', 'Vijayapura', 'ವಿಜಯಪುರ', 'Belagavi',
 ARRAY['KA-28', 'KA-22', 'KA-23', 'KA-04', 'KA-30', 'KA-08']),

('KA-25', 'Dharwad', 'ಧಾರವಾಡ', 'Belagavi',
 ARRAY['KA-25', 'KA-22', 'KA-24', 'KA-15', 'KA-26']),

('KA-26', 'Gadag', 'ಗದಗ', 'Belagavi',
 ARRAY['KA-26', 'KA-25', 'KA-22', 'KA-23', 'KA-07', 'KA-31', 'KA-15']),

('KA-15-HV', 'Haveri', 'ಹಾವೇರಿ', 'Belagavi',
 ARRAY['KA-15-HV', 'KA-25', 'KA-24', 'KA-14', 'KA-17', 'KA-31', 'KA-26']),

('KA-24', 'Uttara Kannada', 'ಉತ್ತರ ಕನ್ನಡ', 'Belagavi',
 ARRAY['KA-24', 'KA-22', 'KA-25', 'KA-15-HV', 'KA-14', 'KA-20']),

-- ----------------------------------------------------------------------------
-- 4. KALABURAGI (KALYANA KARNATAKA) REVENUE DIVISION (7 Districts)
-- ----------------------------------------------------------------------------
('KA-08', 'Kalaburagi', 'ಕಲಬುರಗಿ', 'Kalaburagi',
 ARRAY['KA-08', 'KA-05', 'KA-30', 'KA-28']),

('KA-05', 'Bidar', 'ಬೀದರ್', 'Kalaburagi',
 ARRAY['KA-05', 'KA-08']),

('KA-30', 'Yadgir', 'ಯಾದಗಿರಿ', 'Kalaburagi',
 ARRAY['KA-30', 'KA-08', 'KA-28', 'KA-04']),

('KA-04', 'Raichur', 'ರಾಯಚೂರು', 'Kalaburagi',
 ARRAY['KA-04', 'KA-30', 'KA-28', 'KA-23', 'KA-07', 'KA-18']),

('KA-07', 'Koppal', 'ಕೊಪ್ಪಳ', 'Kalaburagi',
 ARRAY['KA-07', 'KA-04', 'KA-23', 'KA-26', 'KA-31', 'KA-18']),

('KA-18', 'Ballari', 'ಬಳ್ಳಾರಿ', 'Kalaburagi',
 ARRAY['KA-18', 'KA-04', 'KA-07', 'KA-31', 'KA-16']),

('KA-31', 'Vijayanagara', 'ವಿಜಯನಗರ', 'Kalaburagi',
 ARRAY['KA-31', 'KA-18', 'KA-07', 'KA-26', 'KA-15-HV', 'KA-17', 'KA-16', 'KA-06']);

-- Correct standard code normalization inside arrays (Haveri = KA-15-HV vs Chikkamagaluru = KA-15)
UPDATE karnataka_districts
SET adjacent_districts = array_replace(adjacent_districts, 'KA-15', 'KA-15-HV')
WHERE district_code IN ('KA-25', 'KA-26', 'KA-17') AND NOT (district_code = 'KA-14');

-- Create GIN index on adjacent_districts for sub-millisecond containment lookups
CREATE INDEX IF NOT EXISTS idx_karnataka_districts_adj_gin
ON karnataka_districts USING GIN (adjacent_districts);
