// src/store/chatStore.js — Zustand chat store
import { create } from 'zustand';
import { ref, onChildAdded, onValue, push, update, off } from 'firebase/database';
import { rtdb } from '../firebase';

export const useChatStore = create((set, get) => ({
  messages:  {},   // { [threadId]: Message[] }
  listeners: {},   // { [threadId]: cleanup fn }
  typing:    {},   // { [threadId]: boolean }

  async sendMessage(threadId, myUid, myRole, otherUid, text) {
    if (!text?.trim()) return;
    await push(ref(rtdb, `chats/${threadId}/messages`), {
      senderId:    myUid,
      senderRole:  myRole,
      receiverId:  otherUid,
      messageText: text.trim(),
      timestamp:   Date.now(),
      isRead:      false,
    });
  },

  listenMessages(threadId) {
    if (get().listeners[threadId]) return;
    const r = ref(rtdb, `chats/${threadId}/messages`);
    onValue(r, snap => {
      if (!snap.exists()) { set(s=>({messages:{...s.messages,[threadId]:[]}})); return; }
      const msgs = [];
      snap.forEach(c => msgs.push({ id: c.key, ...c.val() }));
      set(s => ({ messages: { ...s.messages, [threadId]: msgs.sort((a,b)=>a.timestamp-b.timestamp) } }));
    });
    set(s => ({ listeners: { ...s.listeners, [threadId]: () => off(r) } }));
  },

  stopListening(threadId) {
    const fn = get().listeners[threadId];
    if (fn) { fn(); set(s=>{ const l={...s.listeners}; delete l[threadId]; return {listeners:l}; }); }
  },

  setTyping(threadId, uid, isTyping) {
    update(ref(rtdb, `typing/${threadId}/${uid}`), { typing: isTyping, ts: Date.now() });
  },
}));
