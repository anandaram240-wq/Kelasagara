# 🚀 Kelasagara BioMatch Standalone Backend (Free-Tier Runbook)

A standalone Node.js/TypeScript backend for facial authentication and 1:N de-duplication on **Cloud Firestore** under the **Firebase Free Spark Plan**.

---

## 🏗 Architecture Overview

* **Sole Database:** Google Cloud Firestore (Project `kelasagara-f127a`).
* **No External Database:** Zero PostgreSQL, pgvector, Supabase, or Milvus.
* **No Paid Firebase Services:** Runs independently of Firebase Cloud Functions (no Blaze upgrade required).
* **Model Engine:** MobileFaceNet ONNX neural network (< 1M parameters, input: `112x112x3`, output: `128-D` on unit hypersphere $S^{127}$, ArcFace loss formulation).
* **Inference Runtime:** `onnxruntime-node` (executes locally on MacBook Air M4 CPU / Apple Silicon MPS or free Linux cloud container).
* **Matching Engine:**
  * Primary: Firestore native `findNearest` vector search where supported.
  * Fallback: Bounded exact similarity scan (hard limit: 500 gallery templates) to prevent Spark quota exhaustion.
* **Security:** Firebase Auth JWT verification on every protected route. All client writes to `biometric_vault` are denied by Firestore rules; only this backend's Admin SDK can write templates.

---

## 🛠 Local Setup & Running on MacBook Air M4

### 1. Prerequisites
* Node.js v20+ or v24+
* npm

### 2. Install Dependencies & Build
```bash
cd backend
npm install
npm run build
```

### 3. Run Automated Backend Tests
```bash
npx ts-node src/tests/biometric_backend.test.ts
```
Expected output:
```
✔ Test 1: L2 Normalization yields unit length 1.000000 on S^127
✔ Test 2: Cosine similarity identity and orthogonality verified
✔ Test 3: Metric cosine distance conversion verified (dist = 1 - sim)
✔ Test 4: Privacy-preserving DPDPA phone masking verified
✔ Test 5: Tri-state threshold classification (Duplicate/Ambiguity/Unique) verified
✔ Test 6: MobileFaceNet forward pass succeeded! Output D=128, Norm=1.000000
```

### 4. Start the Local Server
```bash
npm run dev
# Or production mode:
npm start
```
The server will bind to `http://localhost:5001`.
* For Android Emulator, access via: `http://10.0.2.2:5001/api/biometrics`
* For iOS Simulator / Web: `http://localhost:5001/api/biometrics`
* For Physical Android Device on same Wi-Fi: `http://<YOUR_MAC_IP>:5001/api/biometrics`

---

## 🌐 Free Cloud Prototype Deployment (Render Free)

You can host this backend for free on **Render Free Web Service** without paying for Firebase Blaze:

1. **Create a new Web Service on Render:**
   * Connect your GitHub repository.
   * Root Directory: `backend`
   * Environment: `Node`
   * Build Command: `npm install && npm run build`
   * Start Command: `npm start`
   * Instance Type: `Free` (0.1 CPU, 512 MB RAM)

2. **Environment Variables on Render:**
   * `PORT`: `10000` (or leave default, Render sets this)
   * `FIREBASE_PROJECT_ID`: `kelasagara-f127a`
   * `MODEL_PATH`: `models/kelasagara_mobilefacenet.onnx`
   * `DUPLICATE_THRESHOLD`: `0.74`
   * `AMBIGUITY_THRESHOLD`: `0.65`
   * `MAX_GALLERY_SCAN_LIMIT`: `500`

3. **Service Account Credentials:**
   * Generate a private key JSON from [Firebase Console > Project Settings > Service Accounts](https://console.firebase.google.com/project/kelasagara-f127a/settings/serviceaccounts/adminsdk).
   * In Render, set the secret environment variable `GOOGLE_APPLICATION_CREDENTIALS_JSON` with the JSON content, or pass the individual credentials.

4. **Render Free-Tier Limitations to Keep in Mind:**
   * **Cold Starts:** Free instances spin down after 15 minutes of inactivity. The first wake-up request takes ~30–50 seconds.
   * **Fail-Closed Design:** The Flutter client will never automatically approve a user if the backend is cold or restarting; it shows a friendly retry prompt.
   * **Memory:** The MobileFaceNet ONNX model uses < 25 MB RAM, comfortably inside Render's 512 MB allowance.

---

## 📱 Connecting Flutter App to the Backend

In `lib/services/biometric_service.dart`, the client automatically routes to:
* `http://10.0.2.2:5001/api/biometrics` when running in the Android Emulator.
* `http://localhost:5001/api/biometrics` when running on iOS or Web.

To point your Flutter app to your Render free hosted URL, call:
```dart
BiometricService.instance.setBackendBaseUrl('https://your-app.onrender.com/api/biometrics');
```

---

## 🔒 Security Summary

1. **Client Isolation:** The Flutter app has **zero permission** to read or write `biometric_vault` in Firestore.
2. **Server Decisions:** The backend verifies the user's Firebase JWT, runs the inference model, checks for 1:N duplicates against Cloud Firestore, and writes the biometric template atomically.
3. **Privacy First (DPDPA 2023):** Only 128-D embedding vectors are stored in Firestore. Raw face photos are discarded immediately after inference. Phone numbers returned to duplicate attempts are always masked (e.g. `+91 ******2345`).
