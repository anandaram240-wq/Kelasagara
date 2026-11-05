# KELASAGARA V20.10: ADVERSARIAL TEST REPORT
## Verification of the 20 Mandatory Attack Scenarios

**System:** Kelasagara Major Project  
**Phase:** 20.10  
**Auditor:** Mobile Application Red-Team & Security Evaluator  
**Date:** November 1, 2026

---

### 1. Test Harness Execution Matrix

The 20 mandatory adversarial scenarios defined in the directive were tested in `phase20_10_capture_wire_verification.test.ts`:

| Drill # | Attack Scenario Description | Test Method | Expected Result | Observed Result | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **01** | Plane layout buffer corruption | Buffer smaller than $W \times H$ | `BUFFER_OUT_OF_BOUNDS` error | Throws typed error | **PASS** |
| **02** | Invalid crop metadata | Crop bounds exceeding raw frame | `Crop boundary out of bounds` | Throws typed error | **PASS** |
| **03** | Rotation mismatch tampering | Modifying rotation metadata | Signature mismatch | Rejected fail-closed | **PASS** |
| **04** | Channel-order corruption | Swapping Red and Blue channels | Chroma inequality check | Channels distinct | **PASS** |
| **05** | Image-byte substitution | 1-bit flip in transmitted frame | `FRAME_DIGEST_MISMATCH` | Caught by server hash | **PASS** |
| **06** | Frame reordering attack | Reordering frames $[1, 0]$ | `FRAME_SEQUENCE_DISCONTINUITY` | Rejected fail-closed | **PASS** |
| **07** | Payload truncation attack | Truncating 5 bytes from frame | `FRAME_LENGTH_MISMATCH` | Rejected fail-closed | **PASS** |
| **08** | Payload extension attack | Appending 3 garbage bytes | `FRAME_LENGTH_MISMATCH` | Rejected fail-closed | **PASS** |
| **09** | Duplicate frame replay | Feeding identical duplicate frames | Freeze attack detection | Rejected ($\text{MSE}=0$) | **PASS** |
| **10** | Timestamp reversal attack | $t_1 < t_0$ | Monotonicity violation | Rejected ($dt \le 0$) | **PASS** |
| **11** | Invalid ECDSA signature | Corrupting signature base64 | `DEVICE_SIGNATURE_INVALID` | Cryptographic fail | **PASS** |
| **12** | Unknown / Attacker Public Key | Signature from rogue private key | `DEVICE_SIGNATURE_INVALID` | Cryptographic fail | **PASS** |
| **13** | Device Key ID mismatch | Splicing foreign deviceKeyId | Challenge verification fail | Rejected fail-closed | **PASS** |
| **14** | Play Integrity hash mismatch | Forged requestHash | `PLAY_INTEGRITY_MISMATCH` | Rejected fail-closed | **PASS** |
| **15** | Missing Play Integrity token | Omitted token when required | `MISSING_PLAY_INTEGRITY` | Rejected fail-closed | **PASS** |
| **16** | Nonce replay attack | Resubmitting consumed nonce | `CHALLENGE_REPLAYED` | Rejected fail-closed | **PASS** |
| **17** | Concurrent nonce race | Two requests in `PROCESSING` | `CONCURRENT_SUBMISSION` | Rejected fail-closed | **PASS** |
| **18** | Algorithm downgrade attack | Splicing legacy algorithm string | Signature invalidation | Rejected fail-closed | **PASS** |
| **19** | Unsupported protocol version | Submitting unknown wire version | `UNSUPPORTED_PROTOCOL` | Rejected fail-closed | **PASS** |
| **20** | Empty / Mismatched frame count | Declaring 1 frame, sending 0 | `FRAME_COUNT_MISMATCH` | Rejected fail-closed | **PASS** |

---

### 2. Forensic Red-Team Conclusion

Every adversarial vector was verified against the actual production code under test without mocking out core validation functions. The system fails closed across 100% of adversarial drills.
