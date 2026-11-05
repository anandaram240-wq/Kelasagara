# KELASAGARA BIOMETRIC ENGINE V19.2.2: EMBEDDING COMPATIBILITY & MULTI-SPACE DEDUPLICATION

## 1. Mathematical Flaw in Legacy Deduplication (Phase 17 Finding)
In earlier revisions, candidate deduplication attempted cross-space score blending:
$$\text{Score}_{\text{blended}} = \max(\text{Sim}(\mathbf{z}_{\text{probe}}, \mathbf{v}_{\text{vault}}), \text{Sim}(\mathbf{g}_{\text{probe}}, \mathbf{v}_{\text{vault}}))$$
Because $\mathbf{z}$ is drawn from CASIA-WebFace trained convolutional feature maps and $\mathbf{g}$ is drawn from Fourier positional landmark encodings, computing $\mathbf{z} \cdot \mathbf{g}$ projects into an uncorrelated space. Applying a single arbitrary scalar threshold across mixed spaces causes:
1. False Negatives (Missed Duplicates) when comparing across unaligned representations.
2. False Positives (False Impostor Interceptions) when high dot-product noise exceeds the lower SFace threshold (0.363).

---

## 2. Multi-Space Isolated Deduplication Architecture (V19.2.2)
Kelasagara V19.2.2 resolves this structural defect by implementing **Logically Isolated Metric Spaces**:

```
                  ┌───────────────────────────────────────────────┐
                  │ Probe Input: Image + Landmark Vector          │
                  └──────────────────────┬────────────────────────┘
                                         │
                 ┌───────────────────────┴───────────────────────┐
                 │                                               │
                 ▼                                               ▼
   [SFACE_NEURAL_SPACE]                            [LEGACY_LANDMARK_SPACE]
   Probe: SFace ONNX 128-D                         Probe: Fourier Positional 128-D
   Gallery: Stored SFace Vectors                   Gallery: Stored Landmark Vectors
   Calibrated Threshold: 0.78                      Calibrated Threshold: 0.88
   Rejection Clean Floor: 0.363                    Rejection Clean Floor: 0.80
                 │                                               │
                 ▼                                               ▼
         SFace Duplicate?                              Landmark Duplicate?
                 │                                               │
                 └───────────────────────┬───────────────────────┘
                                         ▼
                            AUTHORITATIVE DECISION:
            If SFaceMatch OR LandmarkMatch → DUPLICATE FOUND (HTTP 409)
            Else → CLEAN ENROLLMENT APPROVED (HTTP 200)
```

### 2.1 Formal Decision Rule
$$\text{Duplicate}(\text{probe}) \iff \left( \exists i \in \mathcal{V}_{\text{SFace}} : \hat{z}_{\text{probe}} \cdot \hat{z}_i \ge 0.78 \right) \lor \left( \exists j \in \mathcal{V}_{\text{Landmark}} : \hat{g}_{\text{probe}} \cdot \hat{g}_j \ge 0.88 \right)$$

$$\text{CleanFloor}(\text{probe}) \iff \left( \forall i \in \mathcal{V}_{\text{SFace}} : \hat{z}_{\text{probe}} \cdot \hat{z}_i < 0.363 \right) \land \left( \forall j \in \mathcal{V}_{\text{Landmark}} : \hat{g}_{\text{probe}} \cdot \hat{g}_j < 0.80 \right)$$

Under this dual-space contract:
- No vector is ever compared outside its native representation.
- Legacy vault documents (Kingking, Raja, RAMU, etc.) are matched in `LEGACY_LANDMARK_SPACE`.
- Newly enrolled users store both representations, ensuring backwards and forwards deduplication compatibility.
