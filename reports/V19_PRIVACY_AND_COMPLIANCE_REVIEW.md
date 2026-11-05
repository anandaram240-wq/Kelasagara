# V19 Privacy, Accountability and Legal Compliance Review

## 1. Statutory Context: Phased DPDP Act Commencement
Claims of "blanket compliance" are legally invalid. Under the official Gazette commencement notification published on **13 November 2025**:
- Key substantive provisions (Sections 3 through 17) of the Digital Personal Data Protection Act, 2023, along with the DPDP Rules, 2025, are subject to phased commencement (many scheduled 18 months from notification, taking full effect around **13 May 2027**).
- Technical mechanisms (AES-GCM encryption, masked identifiers, RAM buffer zeroing) provide defensive engineering controls, but do **not** replace formal qualified legal counsel or statutory Data Protection Officer (DPO) audits.

## 2. Technical Privacy & Data Minimization Controls
1. **Purpose Limitation & Explicit Consent:** Biometric data collection is strictly limited to 1:1 worker authentication and 1:N duplicate registration prevention.
2. **Ephemeral Image Processing:** Raw camera frame bytes are held transiently in memory for neural inference and immediately released. No raw worker facial photography is stored unencrypted in long-term databases.
3. **No Biometric Vector Leakage to Client:**
   - Client applications never receive raw 128-D template vectors from the server.
   - Client applications are strictly forbidden from submitting client-computed identity vectors.
4. **Anti-Enumeration Safeguards (DPDPA §8(3)):**
   - In Journey B (duplicate account attempt), an unauthenticated applicant is **never** shown an existing user's name, phone number, or photo.
   - Masked reference hints (`KLS-WRK***42-8819`) are revealed **only** after the applicant successfully proves control via registered phone OTP.

## 3. Clear Boundaries on UIDAI & Aadhaar Claims
- **Inspiration vs Certification:** Kelasagara's biometric architecture adopts UIDAI FaceRD architectural best practices (WADH cryptographic binding, challenge nonces, hardware-first camera, localized Kannada guidance).
- **Zero Official Certification Claim:** Kelasagara is **NOT** a certified UIDAI Registered Device (RD) service, is **NOT** an authorized AUA/KUA entity, and does **NOT** access the Central Identities Data Repository (CIDR).
- The mobile UI strictly refrains from using government emblems, Aadhaar logos, or misleading certification claims.
