# UIDAI Public Architecture Research & Biometric Identity Separation
## Authoritative Analysis of Aadhaar 1:1 Face Authentication, 1:N Enrolment De-Duplication, and Cryptographic Security Controls

**Platform:** Kelasagara Labor & Mobility Ecosystem  
**Target Architecture:** Kelasagara Biometric Engine V5.0  
**Status:** Research & Engineering Reference  
**Last Updated:** 2026-10-22  
**Classification:** Public Regulatory & Architectural Research  

---

## 1. Executive Summary & Regulatory Context

This document establishes the public architectural baseline of the **Unique Identification Authority of India (UIDAI)** identity system, based exclusively on publicly available statutory documents, technical specifications, and official annual reports.

The fundamental design lesson of the Aadhaar platform is the absolute, unyielding separation between:
1. **1:1 Face Authentication (Auth):** A lightweight, real-time, identity-asserted verification protocol that determines whether a fresh capture matches the reference template already registered for a specific claimed 12-digit Aadhaar number or Virtual ID (VID).
2. **1:N Enrolment De-Duplication (ABIS):** A heavy, asynchronous, large-scale search across the entire identity registry to prevent a single individual from acquiring multiple identity records under different demographic identities.

Confusing these two workflows is the single most common failure mode in commercial biometric engineering. Kelasagara Biometric Engine V5.0 adopts UIDAI's identity separation principles without reverse-engineering or claiming access to UIDAI's proprietary internal algorithms.

---

## 2. Official Source Directory & Citations

All statements in this document are attributed to official public sources:

| Document Title | Issuing Body | Publication / Version | Official URL / Citation |
| :--- | :--- | :--- | :--- |
| **Aadhaar Act 2016** | Parliament of India | Act No. 18 of 2016 (amended 2019) | [https://uidai.gov.in/en/my-aadhaar/about-aadhaar/aadhaar-act.html](https://uidai.gov.in/en/my-aadhaar/about-aadhaar/aadhaar-act.html) |
| **Face RD Service Specification** | UIDAI Technology Centre | Version 2.0 (and circulars) | [https://uidai.gov.in/en/authentication/face-rd-service.html](https://uidai.gov.in/en/authentication/face-rd-service.html) |
| **Aadhaar Authentication API Specification** | UIDAI | Version 2.5 (Rev 1) | [https://uidai.gov.in/en/authentication-documents.html](https://uidai.gov.in/en/authentication-documents.html) |
| **UIDAI Annual Report 2023-24** | Ministry of Electronics and IT, GoI | December 2024 Release | Chapter 4: "Biometric Matching & ABIS Infrastructure" |
| **UIDAI Circular on Face Authentication** | UIDAI Authentication Division | Circular No. 1 of 2018 | Implementation of Face Authentication in Telecom & Banking |
| **UIDAI Device Specification (L0 / L1)** | UIDAI Security & Biometrics | Rev 2.1 | Device-level key management and TEE isolation |

---

## 3. 1:1 Face Authentication Architecture

### 3.1 Documented Transaction Actors
According to UIDAI Face RD Service v2.0 and Auth API v2.5, an authentication transaction involves six distinct entities:
1. **Resident / Worker:** The individual presenting their face to the camera.
2. **Authentication Requesting Entity (AUA / KUA):** The merchant, bank, or application (e.g., Kelasagara) that requires identity verification to authorize a service or check-in.
3. **Authentication Service Agency (ASA):** The telecommunications / network pipeline providing secure, leased-line or mutual TLS connectivity to the CIDR.
4. **Face RD Service (Registered Device Service):** An isolated, cryptographically sealed client application running in Android TrustZone or TEE (Hardware KeyStore).
5. **Central Identities Data Repository (CIDR):** The secure data centers hosting the encrypted identity database and authentication matchers.
6. **Hardware Security Module (HSM):** Server-side cryptographic hardware that decrypts the sealed PID block using UIDAI's private keys.

### 3.2 Processing Sequence (Step-by-Step)
1. **Identity Assertion:** The resident provides their claimed identifier (12-digit Aadhaar or 16-digit VID).
2. **Challenge Acquisition:** The AUA requests a dynamic cryptographic nonce (Work Authorization Data Hash, or WADH) from its backend.
3. **RD Intent Launch:** The AUA launches an Android Intent to the certified Face RD Service, passing:
   - Challenge Nonce / WADH.
   - Required modalities (Face only, or Face + OTP).
   - Capture timeout (typically 10–30 seconds).
4. **On-Device ISO/IEC 30107-3 Liveness Test:** The RD Service captures camera frames and executes proprietary Presentation Attack Detection (passive texture, kinematic motion, 3D structure). The raw camera feed is never shared with the calling AUA application.
5. **PID Block Construction & Sealing:**
   - The captured face biometric record is packaged into a standard XML structure (`<PidData>`).
   - The RD Service generates an ephemeral 256-bit AES session key.
   - The PID XML is encrypted using **AES-256-GCM** with the session key.
   - The session key is encrypted with UIDAI's published 2048-bit RSA public key.
   - The entire payload is digitally signed with the RD vendor's certified device key.
6. **Encrypted Forwarding:** The sealed PID block is returned to the AUA app, which forwards it unchanged through the ASA to the CIDR.
7. **1:1 Comparison in CIDR:**
   - The CIDR HSM decrypts the session key using UIDAI's private RSA key.
   - The PID block is decrypted and validated against the signature and challenge nonce.
   - The matcher loads the stored reference template associated *exclusively* with the claimed Aadhaar ID.
   - The matcher executes a 1:1 similarity calculation:
     $$S = \text{Cosine}(\mathbf{E}_{\text{fresh}}, \mathbf{E}_{\text{reference}})$$
8. **Binary Response:** CIDR responds with a digital signature confirming `Y` (authenticated) or `N` (rejected), accompanied by an ISO-standard error code (e.g., Code 300: Biometric Mismatch).

---

## 4. 1:N Enrolment De-Duplication Architecture (ABIS)

### 4.1 Documented Enrolment Sequence
Enrolment is an asynchronous, multi-stage identity creation pipeline:
1. **Enrolment Submission:** Resident submits demographic details, 10 rolled/flat fingerprints, 2 iris captures, and 1 frontal portrait at an authorized Enrolment Centre.
2. **Packet Sealing:** The enrolment client validates ICAO / ISO 29794-5 image quality, encrypts the entire bundle with the UIDAI Enrolment Master Public Key, and uploads it.
3. **Demographic De-Duplication:** CIDR executes fuzzy demographic filtering (name, date of birth, parentage, address).
4. **Biometric Quality Assessment:** NFIQ 2.0 (fingerprints) and OFIQ-compliant facial geometry tests discard sub-standard samples.
5. **Multi-Vendor Automated Biometric Identification System (ABIS):**
   - As documented in the **UIDAI Annual Report 2023-24**, adult enrolments are processed through **three independent commercial ABIS systems** running in parallel.
   - Each vendor ABIS maintains its own proprietary feature representation and index of the entire gallery.
6. **Candidate Generation & Multi-Matcher Reconciliation:**
   - Each ABIS generates a candidate list of potential matching identities above a preliminary threshold.
   - Scores from fingerprint, iris, and facial modalities are fused.
7. **Two-Tier Human Adjudication:**
   - If an enrolment produces a high biometric similarity candidate against an existing identity, it is **never automatically purged or rejected**.
   - The candidate pair is routed to a portal where trained Biometric Adjudication Officers perform visual verification.
   - Field verification by district authorities may be dispatched in ambiguous adult cases.
8. **Final Decision:**
   - If proven duplicate: Enrolment rejected under Section 3 of the Aadhaar Act; fraud flag recorded.
   - If verified unique: New 12-digit Aadhaar number generated and allocated.

---

## 5. Population-Scale Identity Mathematics: Why 1.4 Billion Does Not Break

A common misconception is that authenticating an Aadhaar card requires comparing a face against 1.4 billion people:

$$\text{Authentication Complexity: } \mathcal{O}(1) \quad (\text{Direct index lookup by Aadhaar Number})$$
$$\text{Enrolment De-Duplication Complexity: } \mathcal{O}(N) \to \mathcal{O}(\log N) \quad (\text{Distributed Hierarchical Indexing})$$

### 5.1 Throughput vs. Gallery Size
- **Daily Transaction Throughput:** UIDAI reports handling over 80 million authentication transactions daily. Because each is a 1:1 lookup, each transaction requires only **one vector comparison** (latency $< 50\text{ ms}$).
- **Enrolment Throughput:** Enrolments and updates represent approximately 1 million transactions daily. These execute in distributed server clusters where the gallery is sharded across demographic, gender, age, and high-level feature partitions.

---

## 6. Publicly Documented Security Controls

1. **Zero Raw Biometric Access:** Third-party applications (AUAs) never touch raw images or biometric templates. The capture is completely encapsulated within the RD service.
2. **WADH Cryptographic Binding:** The Work Authorization Data Hash guarantees that a biometric capture intended for a bank login cannot be intercepted and replayed for a SIM card purchase.
3. **Ephemeral Session Encryption:** Every packet uses a fresh AES-256 session key, rendering network eavesdropping completely futile.
4. **Hardware Key Isolation:** L1 Registered Devices generate and store private keys inside CC EAL4+ or FIPS 140-2 Level 3 hardware security chips.

---

## 7. Confirmed Unknowns (Proprietary & Non-Public Aspects)

To maintain absolute scientific and engineering integrity, the following aspects are confirmed to be **proprietary and undisclosed by UIDAI**:
1. **Specific Neural Architectures:** The exact convolutional layers, loss functions, and weight parameters of the face recognition networks inside CIDR are trade secrets of the contracted ABIS vendors (historically IDEMIA, NEC, and Cogent/3M).
2. **Multi-Vendor Score Fusion Formula:** The exact mathematical weighting between iris, fingerprint, and face match scores during adjudication is not publicly disclosed.
3. **Internal Sharding & Approximate Nearest Neighbor Algorithms:** The specific clustering algorithms used within the ABIS hardware partitions are proprietary vendor implementations.

---

## 8. Architectural Lessons for Kelasagara V5.0

| UIDAI Identity Principle | Architectural Anti-Pattern in Legacy Kelasagara | Kelasagara V5.0 Production Architecture |
| :--- | :--- | :--- |
| **Strict 1:1 vs. 1:N Separation** | Attempting 1:N scan during regular login; confusing verification with fraud detection. | Decoupled endpoints: `/api/biometrics/verify-1to1` vs. `/api/biometrics/enroll-1toN`. |
| **Zero Raw Exposure** | Client downloading 500 competitor biometric vectors to phone RAM. | Server-authoritative matching in `InMemoryBiometricIndex`; Firestore vault read-locked to owner. |
| **Human Adjudication** | Automated irreversible rejection of user on 84% score. | `REVIEW_REQUIRED` state for ambiguous candidates $[0.65, 0.74)$; zero auto-punishment. |
| **Zero PII Disclosure** | Displaying matched worker's phone number and partial UID on duplicate sheet. | Strict DPDPA 2023 §8(3) compliance: Return only masked audit ticket (`BIODUP-...`). |
| **Cryptographic Binding** | Client sending raw vector with no nonce or hardware signature. | `buildPadBoundRequestHash()` binding server challenge nonce, IPD, and PAD telemetry. |
