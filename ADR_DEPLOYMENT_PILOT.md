# ADR-002: Sovereign Pilot Deployment & Cryptographic Security Architecture
**Subsystem:** Kelasagara BioMatch V9 / S2  
**Status:** Approved & Binding  
**Compliance Context:** Digital Personal Data Protection Act (DPDPA 2023), ISO/IEC 27001, Indian Sovereign Cloud Guidelines

---

## 1. Context & Business Drivers

The Kelasagara platform connects workers and hirers throughout Karnataka, India. Facial recognition data constitutes Sensitive Personal Data under the DPDPA 2023. Operating biometric inference requires uncompromising guarantees regarding:
1. Data localization within Indian sovereign territory.
2. Complete absence of unauthorized offshore transmission.
3. Cryptographic isolation against database breach or operator compromise.
4. Predictable operating cost within Firebase Spark free-tier operational limits.

---

## 2. Architecture Decisions

### 2.1 Geographic Localization & Infrastructure
- **Persistent Database:** Cloud Firestore deployed strictly in **`asia-south1` (Mumbai, India)**.
- **Compute Hosting:** Authoritative standalone Node.js inference backend hosted on sovereign instances in `asia-south1` (e.g. Google Cloud Run Mumbai or Sovereign Indian VPS).
- **Network Boundaries:** Client requests route via encrypted Indian PoPs. Strict VPC peering prevents data egress beyond the designated Indian data center region.

### 2.2 Transport Security (TLS 1.3 & HSTS)
- All traffic between client mobile devices and the BioMatch backend is terminated exclusively over **TLS 1.3** (fallback TLS 1.2 allowed only with AEAD ciphers).
- Strict Transport Security (`Strict-Transport-Security: max-age=63072000; includeSubDomains; preload`) enforced on all responses.
- Ephemeral Diffie-Hellman (`ECDHE`) key exchange ensures Perfect Forward Secrecy (PFS).

### 2.3 Cryptographic Key Management (Cloud KMS & Envelope Encryption)
- **Key Ring:** Dedicated Cloud KMS key ring located in `asia-south1`.
- **Envelope Encryption:** Every biometric template vector in `biometric_vault` is protected by per-subject salt (`crypto.randomBytes(16)`) and keyed cryptographic hashing (`HMAC-SHA256`).
- **Crypto-Shredding (DPDPA Sec 12):** When a user requests deletion, their salt and template record are purged from `biometric_vault`, instantly rendering any backup vector unrecoverable.

### 2.4 Data Processor Governance
- **Zero Third-Party Inference APIs:** No external cloud biometric APIs (e.g., AWS Rekognition, Azure Face, or third-party proprietary SAAS) are utilized.
- **Local Neural Runtime:** Autoritative inference executes directly on the Kelasagara backend using locally pinned ONNX Runtime binaries (`sface_2021dec.onnx`, `sface_2021dec_int8.onnx`).
- **No Client Vectors:** Client mobile devices never emit feature vectors or landmarks for authoritative authentication (Ticket T-01).

### 2.5 Operational Quota & Free Tier Protection
- Firestore flat gallery scans are bounded by `config.maxGalleryScanLimit` (default 500).
- Concurrency sessions and sliding rate limits (max 3 enrollments per 24h per user) protect against malicious denial-of-wallet / quota exhaustion.
