# KELASAGARA (v17) - ARCHITECTURAL BACKUP & MASTER DIRECTIVE
**Timestamp:** 2026-10-17 04:58 IST
**Branch:** `biomatch/s9-integration`
**System:** UIDAI FaceRD Level-0 Biometric Engine + ISO/IEC 30107-3 PAD + Siri Voice AI Directive

---

## 1. DEDUPLICATION SYSTEM FIX SUMMARY

### Root Cause
The Fourier trigonometric harmonic series expansion ($2^k \pi$ for $k \in [1, 8]$ up to $256\pi \approx 804.25$) previously implemented in `BiometricService.generateEmbeddingFromLandmarks` had a Lipschitz constant $> 800$.
A natural 1–3% camera distance or angle shift between sessions shifted normalized ratios by $\sim 0.005$, rotating phase components by $> 4$ radians ($230^\circ$). This collapsed cosine similarity between two sessions of the SAME person from $1.00$ down to $0.54$.
Since $0.54 < \tau = 0.74$, duplicate enrollment was bypassed.

### Permanent Resolution
Implemented **Standardized Anthropometric Metric Feature Encoder** in `lib/services/biometric_service.dart`:
- Scale-invariant biometric ratios ($Z$-score normalized $\frac{x_i - \mu_i}{\sigma_i}$) against human baseline distributions.
- Projected onto $\mathbb{S}^{127}$ via a deterministic Haar orthogonal matrix.
- Same-person cosine similarity under 1–5% natural jitter: $\ge 0.84 - 0.96$ ($\ge 0.74$ duplicate threshold).
- Unrelated individuals: $< 0.40$ (below $0.65$ ambiguity gate).
- 38/38 biometric tests passing (`test/biometric_deduplication_engine_test.dart`).

---

## 2. AADHAAR FaceRD L0 MODULES CREATED

1. **`lib/services/iso30107_pad_gate.dart`**: Two-stage PAD liveness gate ($90\text{--}450$ ms blink duration, $40 \le \sigma_L^2 \le 3800$ discrete 2D Laplacian texture variance).
2. **`lib/services/uidai_pid_builder.dart`**: WADH SHA-256 calculation (`appId|subAuaCode|ver|ts|txnId|nonce`) + AES-256-GCM `<PidData>` XML generator.
3. **`ml/calibrate_far_frr_det.py`**: Automated ROC/DET calibration engine for Karnataka's 31-district gallery ($N=100,000, \tau = 0.74$).
4. **`lib/services/biomatch_ffi_bridge.dart`**: Dart FFI service adapter.

---

## 3. MASTER PROMPT FOR ARGON / GEMINI PRO

```markdown
# ARCHITECTURAL DIRECTIVE: KELASAGARA (v17) 120 FPS FLUIDITY & SIRI-GRADE VOICE AI ENGINE

You are acting as the Principal Mobile Systems & Computer Vision/Audio Architect for "Kelasagara" (Karnataka's flagship informal worker marketplace, built on Flutter 3.24+, Android NDK C++17, and Firebase/Node.js).

The college evaluation panel and early users have tested the application. While the core features (Biometric Aadhaar FaceRD L0, GPS tracking, and job matching) are functional, the app requires two immediate systems-level upgrades:
1. **Buttery 60/120 FPS UI/UX Flow & Zero-Jank State Machine** across all screens (Worker Dashboard, Hirer Dashboard, Job Details, Applications, Profile).
2. **Next-Generation Siri-Grade Conversational Voice AI (Kannada + English/Kanglish)** featuring instantaneous sub-200ms audio activation, fluidic multi-layer animated orb with audio-amplitude reactivity, full-duplex conversational barge-in, and streaming actionable UI dialog cards.

Provide a production-grade, zero-stub engineering blueprint and drop-in Flutter/Dart & Native implementations addressing the requirements below:

---

### TRACK 1: APP-WIDE 60/120 FPS SMOOTHNESS & LATENCY OPTIMIZATION

#### 1. Zero-Frame-Drop Rendering Pipeline
- Diagnose and eliminate widget rebuild cascades: Replace heavy `context.watch<T>()` and broad `Consumer<T>` blocks with fine-grained `Selector<T, V>` and isolated ValueNotifiers so scrolling lists and telemetry timers never trigger root subtree redraws.
- Isolate complex animated cards (WorkerCard, JobCard, Live Radar) inside `RepaintBoundary` nodes to eliminate unnecessary raster cache invalidations.
- Provide fluid spring physics transitions (iOS-like `SlideTransition` with `Curves.easeOutCubic` / spring simulation, duration 260–300ms) replacing abrupt route jumps.
- Implement Apple-grade haptic orchestration: `HapticFeedback.selectionClick()` on tab switching, `HapticFeedback.lightImpact()` on filter chips, and `HapticFeedback.mediumImpact()` on primary booking/apply CTAs.

#### 2. Optimistic UI Updates & Instant-Feedback State Transitions
- Eliminate "tap-and-wait" deadframes: When applying for a job, booking a worker, or toggling availability, the UI must transition in the exact same frame (< 16.6ms) with an optimistic state, followed by background Firebase persistence and automated rollback on failure.
- Replace generic circular loaders with shimmer skeletons that match the exact typography, padding, and avatar layout of the real cards to prevent layout shifts (CLS = 0).

---

### TRACK 2: SIRI-GRADE CONVERSATIONAL VOICE AI (KANNADA + KANGLISH)

#### 1. Fluidic Multi-Layer Shader/Mesh-Gradient Siri Orb (`CustomPainter`)
- Replace the static icon button with a fluidic, organic glowing orb inspired by Apple Siri & Gemini Live:
  - 3 concentric oscillating harmonic wave layers driven by `AnimationController` and real-time mic amplitude RMS values ($A \in [0.0, 1.0]$).
  - Dynamic state colors: Ambient Idle (Purple `#7C3AED` to Saffron `#F5820A`), Listening/User Speaking (Cobalt Blue `#2563EB` to Cyan `#06B6D4`), Thinking/Querying (Deep Violet to Amber shimmer), and Assistant Speaking (Emerald Green `#059669` to Mint `#10B981`).
  - Smooth 60 FPS breathing pulse effect when idle, morphing into high-frequency liquid wave oscillations when receiving audio.

#### 2. Instant Voice Activation & Low-Latency Pipeline (< 200ms)
- Eliminate STT initialization delay: Warm up the speech recognition engine in the background when the user opens or hovers over the Voice AI tab so speech-to-text activates in $< 50\text{ ms}$ upon tapping.
- Support instant bilingual recognition: Auto-route between Kannada (`kn-IN`) and Indian English (`en-IN`), with deterministic regex normalization for vernacular Kannada dialects (e.g., Bengaluru, North Karnataka, Coastal/Mangaluru).

#### 3. Full-Duplex Conversational Barge-In (Echo Cancellation & Audio Interruption)
- Implement Siri-like "Barge-In": If the assistant is reading out worker results or speaking through TTS and the user begins speaking, the audio session must instantly pause TTS playback (< 80ms) and seamlessly switch to recording the user's new utterance without clipping or throwing `PlatformException`.

#### 4. Real-Time Actionable Siri Dialogue Bubbles & Card Carousels
- Utterances like *"5 km ಒಳಗೆ plumber ಹುಡುಕು"* or *"Tomorrow morning painter ಬೇಕು"* must not just speak back text, but immediately render:
  - Streaming user transcript bubble with auto-scrolling physics.
  - Interactive horizontally scrollable Worker Candidate Cards (Avatar with availability ring, distance tag, star rating, hourly pay, and one-tap "Book Now" CTA).
  - Floating Booking Confirmation Pill with countdown timer and haptic vibration.

---

### DELIVERABLES REQUIRED:
1. **`lib/widgets/voice/siri_fluid_orb.dart`**: Complete, self-contained `CustomPainter` + `AnimationController` widget with multi-layer organic wave physics and microphone amplitude input.
2. **`lib/services/voice/voice_session_manager.dart`**: High-performance session manager with sub-200ms activation, bilingual STT routing, and instant Barge-In interrupt handling.
3. **`lib/screens/voice/kannada_voice_screen.dart`**: Upgraded Siri-style interface featuring the dynamic fluid orb, conversational chat history, and rich worker recommendation cards.
4. **App-wide Smoothness Optimization Guide**: Targeted edits for `worker_dashboard.dart`, `job_card.dart`, and `home_shell.dart` to achieve lock-step 120 FPS performance.

Write clean, robust, production-ready Dart code with zero pseudo-code placeholders.
```
