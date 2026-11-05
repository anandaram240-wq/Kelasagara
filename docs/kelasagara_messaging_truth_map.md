# Kelasagara Real-Time Private Messaging Truth Map
**Document Version:** 1.0.0 (Hardened)  
**Author:** Principal Messaging Architect & Applied Cryptography Lead  
**Classification:** Engineering Specification & Forensic Truth Map

---

## 1. Forensic Baseline & Current System Failure

### 1.1 Original Message Send/Receive Failure
In the original implementation (`lib/services/chat_booking_service.dart`), messages failed to send or receive reliably, and the chat screen frequently hung on `"Connecting..."`.

Forensic investigation reveals four fundamental root causes:

1. **Permission Denied on `markSeen` (Primary Fatal Crash):**
   - In `lib/services/chat_booking_service.dart:83`, `ChatService.markSeen` attempts a Firestore batch update:
     ```dart
     batch.update(doc.reference, {'seenBy': FieldValue.arrayUnion([uid])});
     ```
   - In `firestore.rules:331`:
     ```javascript
     match /conversations/{convId}/messages/{msgId} {
       allow update: if false; // Messages strictly immutable!
     }
     ```
   - When `ChatScreen.initState()` called `await ChatService.markSeen(_convId!, myUid);`, Firestore immediately threw `[cloud_firestore/permission-denied]`.
   - `_initChat()` caught this exception and set `_connected = false`.
   - Because execution halted before the message stream was attached, the stream listener `_msgSub` was never registered, rendering the chat screen dead/perpetually disconnected.

2. **Divergent Conversation IDs for Direct Hires:**
   - In `lib/screens/home/hirer_dashboard.dart:764`, the hirer passed:
     `jobId: 'direct_hire_${worker.uid}'`
   - In `lib/screens/profile/hirer_profile_sheet.dart:259`, the worker passed:
     `jobId: 'direct_${hirerId}'`
   - In `lib/widgets/worker_card.dart:82`, the hirer passed:
     `jobId: 'direct_${worker.uid}'`
   - Because `ChatService.convId` is `${sorted[0]}_${sorted[1]}_$jobId`, the hirer and the worker resolved to two completely different Firestore document IDs. The hirer's messages were written to document room A, while the worker listened to document room B. Neither party ever received the other's messages.

3. **Malformed Unindexed Query:**
   - In `ChatService.markSeen`:
     ```dart
     .where('seenBy', whereNotIn: [[uid]])
     ```
   - Passing a nested list `[[uid]]` is invalid in Firestore, threw query evaluation exceptions, and required non-existent composite indexes.

4. **Plaintext Storage & Server Vulnerability:**
   - `ChatService.sendMessage` wrote plaintext strings directly to Firestore field `text: text`.
   - Plaintext message contents were fully readable by database administrators, indexers, and anyone with read access to Firestore.

---

## 2. Canonical Conversation Schema & Deterministic Resolver

### 2.1 The Canonical Conversation ID Contract
All 1:1 conversations must resolve to a deterministic, order-independent canonical conversation ID:

1. **Job/Booking-Scoped Conversations:**
   When messaging in the context of an actual marketplace job or booking:
   $$\text{ConvID} = \min(\text{uid}_1, \text{uid}_2) + \text{"\_"} + \max(\text{uid}_1, \text{uid}_2) + \text{"\_"} + \text{bookingId}$$
   *Preserves complete backwards-compatibility with existing Firestore records.*

2. **Direct/Profile Conversations:**
   When messaging directly without an active job booking, or when given `direct_*` or `direct_hire_*` legacy parameters:
   $$\text{ConvID} = \text{"direct\_"} + \min(\text{uid}_1, \text{uid}_2) + \text{"\_"} + \max(\text{uid}_1, \text{uid}_2)$$
   *Both participants always compute the exact same conversation ID regardless of who initiates.*

### 2.2 Canonical Conversation Document Schema (`conversations/{convId}`)
```json
{
  "id": "direct_hirer123_worker456",
  "participants": ["hirer123", "worker456"],
  "participantNames": {
    "hirer123": "Ramesh Gowda",
    "worker456": "Suresh Kumar"
  },
  "jobId": "direct",
  "jobTitle": "Direct Consultation",
  "lastMessageAt": "2026-10-03T08:30:00Z",
  "lastMessageSenderId": "hirer123",
  "lastCiphertextPreview": "[Encrypted message]",
  "unreadCount": {
    "hirer123": 0,
    "worker456": 1
  },
  "typing": {
    "hirer123": false,
    "worker456": false
  },
  "createdAt": "2026-10-03T08:00:00Z",
  "version": 1
}
```

---

## 3. Canonical Message Schema (`conversations/{convId}/messages/{clientMessageId}`)

Each message is identified by a client-generated UUID `clientMessageId`, guaranteeing idempotency and preventing duplicate creation upon network retries.

```json
{
  "clientMessageId": "c4b3f81e-7b3a-4e2b-93f5-6a12d84c8a2b",
  "conversationId": "direct_hirer123_worker456",
  "senderId": "hirer123",
  "senderDeviceId": "dev_a1b2c3d4",
  "recipientId": "worker456",
  "type": "text",
  "version": 1,
  
  "envelope": {
    "ephemeralDhPublicKey": "base64_32_bytes_x25519_pubkey",
    "sequenceNumber": 4,
    "previousChainLength": 0,
    "nonce": "base64_12_bytes_iv",
    "ciphertext": "base64_encrypted_payload",
    "mac": "base64_16_bytes_poly1305_tag",
    "protocolVersion": 1
  },

  "sentAt": "2026-10-03T08:30:00.120Z",
  "status": "sent",
  "deliveredAt": null,
  "readAt": null,
  "seenBy": ["hirer123"]
}
```

> **Zero Plaintext Rule:** The server never receives or stores a `text` field for version 1 messages. The message content exists solely in `envelope.ciphertext`.

---

## 4. Delivery & Read Receipt Contract

### 4.1 Immutability-Safe Receipt Protocol
To honor the invariant that message content must remain immutable (`allow update: if false;` on content) while supporting delivery and read ticks:

1. **Firestore Rule Exception for Receipts:**
   Updating a message document is permitted **only** if:
   - The user is the **recipient** (`request.auth.uid == resource.data.recipientId`).
   - The diff affected keys are strictly restricted to `['seenBy', 'status', 'deliveredAt', 'readAt']`.
   - Content, sender, envelope, and timestamp fields cannot be altered.

2. **Receipt State Flow:**
   - `queued` $\to$ `sending` $\to$ `sent` ($\checkmark$)
   - Recipient device receives stream, authenticates AEAD tag, decrypts $\to$ updates `status: 'delivered'`, `deliveredAt: serverTimestamp()` ($\checkmark\checkmark$ gray)
   - Recipient opens chat screen $\to$ updates `status: 'read'`, `readAt: serverTimestamp()`, `seenBy: arrayUnion([recipientUid])` ($\checkmark\checkmark$ blue)

---

## 5. Offline Outbox & Retry Engine

1. **Immediate Optimistic UI:**
   On message submission, the message is added to the in-memory & local Outbox in `QUEUED` state. The UI displays the message bubble in $<10\text{ms}$.
2. **Outbox Worker:**
   A dedicated worker processes queued messages sequentially:
   - Checks/establishes crypto session with recipient.
   - Encrypts plaintext into AEAD envelope.
   - Writes to Firestore with doc ID = `clientMessageId`.
   - Updates status to `SENT`.
3. **Exponential Backoff with Jitter:**
   If offline or network drops, retry delay formula:
   $$T_{\text{wait}} = \min(30\text{s}, 2^{\text{attempt}} \times 1\text{s}) \pm \text{jitter}(0, 500\text{ms})$$
   Max 5 automatic attempts. If permanently disconnected, status becomes `FAILED` with manual retry.
