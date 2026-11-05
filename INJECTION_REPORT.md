# INJECTION ATTACK DEFENSE (IAD) EVALUATION REPORT
**Standard:** CEN/TS 18099 & ISO/IEC 25456 Pre-Standard Alignment (Ticket E-04)  
**Date:** 10 October 2026  
**Evaluator:** Kelasagara Biometric Security Hardening Team  
**Evaluation Scope:** 4 Digital Stream Injection Species across 200 Synthetic Attacks  

---

## 1. Executive Summary & Attack Interception Matrix

Unlike presentation attacks that occur in front of the lens, injection attacks bypass the camera sensor entirely, pushing synthetic video feeds via Android virtual cameras, emulator webcam bridges, or hooking frameworks (Frida/Xposed).

| Attack ID | Injection Species | Category | Trials | Blocked | Bypassed | Interception Rate | Production Guard |
|:---:|:---|:---:|:---:|:---:|:---:|:---:|:---|
| **IAD-01** | Virtual Camera Driver Stream Injection | INJECTION_ATTACK | 50 | 50 | 0 | 100.00% | Cryptographic Frame Provenance Binding (SHA-256) + Invariant I-25 |
| **IAD-02** | Pre-recorded Stream Time-Delay Injection | INJECTION_ATTACK | 50 | 50 | 0 | 100.00% | 60-Second Capture Skew Ceiling + Invariant I-25 |
| **IAD-03** | Frida/Xposed Camera API Hooking & Emulation | INJECTION_ATTACK | 50 | 50 | 0 | 100.00% | Hardware Device Attestation / Integrity Signatures + Invariant I-26 |
| **IAD-04** | Asymmetric Keystore Signature Forgery | INJECTION_ATTACK | 50 | 50 | 0 | 100.00% | Hardware-Backed KeyStore EC/RSA Verification + Ticket E-07 |

---

## 2. Technical Defense Architecture

1. **Cryptographic Frame Hash Binding (Invariant I-25):** The client computes SHA-256 over raw camera pixels inside the protected camera callback and submits it alongside the active session nonce. Any virtual camera modifying frame bytes causes an immediate SHA-256 hash mismatch.
2. **Time-Skew Ceiling (60 Seconds):** Captured timestamps older than 60,000ms relative to server clock are rejected fail-closed, defeating pre-recorded digital stream replay.
3. **Hardware Device Attestation (Invariant I-26):** Google Play Integrity and Firebase App Check tokens verify the physical device and detect Frida/Xposed hooks, emulator drivers, or uncertified Android images.
4. **Hardware KeyStore Asymmetric Signing (Ticket E-07):** In Android KeyStore, an asymmetric key signs the canonical string `nonce:timestamp:deviceId:frameSha256`, preventing any external process from synthesizing claims.
