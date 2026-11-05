-- ============================================================================
-- KELASAGARA BIOMATCH ENGINE: DPDPA SECTION 12 & RULE 8(3) SHREDDING
-- Migration: 004_dpdpa_shredding.sql
-- ============================================================================

-- 1. KMS Wrapped-DEK Revocation Denylist (Blocks backup replay attacks)
CREATE TABLE IF NOT EXISTS revoked_dek_digests (
    dek_sha256_hex CHAR(64) PRIMARY KEY,
    pseudonymized_subject_hash CHAR(64) NOT NULL,
    key_version_name TEXT NOT NULL,
    revoked_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Atomic Overwrite-Before-Delete Stored Procedure for pgvector
CREATE OR REPLACE FUNCTION shred_worker_biometric_template(
    p_uid VARCHAR(64),
    p_noise_vector vector(128),
    p_dek_sha256_hex CHAR(64),
    p_subject_hash CHAR(64),
    p_key_version TEXT
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_rows_deleted INT := 0;
BEGIN
    -- Step A: Register wrapped DEK in permanent revocation denylist
    INSERT INTO revoked_dek_digests (
        dek_sha256_hex,
        pseudonymized_subject_hash,
        key_version_name
    ) VALUES (
        p_dek_sha256_hex,
        p_subject_hash,
        p_key_version
    ) ON CONFLICT (dek_sha256_hex) DO NOTHING;

    -- Step B: Overwrite the 128-D embedding in-place with CSPRNG unit noise
    -- so the HNSW / heap tuple no longer holds true facial geometry
    UPDATE biometric_templates
    SET embedding = p_noise_vector,
        quality_norm = 0.0,
        status = 'shredded'
    WHERE uid = p_uid;

    -- Step C: Hard-delete the row from biometric_templates
    DELETE FROM biometric_templates
    WHERE uid = p_uid;

    GET DIAGNOSTICS v_rows_deleted = ROW_COUNT;
    RETURN v_rows_deleted > 0;
END;
$$;
