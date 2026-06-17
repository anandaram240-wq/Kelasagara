// src/store/authStore.js — Zustand auth store
import { create } from 'zustand';
import { onAuthStateChanged } from 'firebase/auth';
import { doc, getDoc, setDoc } from 'firebase/firestore';
import { auth, db } from '../firebase';

export const useAuthStore = create((set, get) => ({
  user:     null,
  profile:  null,
  role:     null,
  loading:  true,
  ready:    false,

  init() {
    onAuthStateChanged(auth, async (user) => {
      if (!user) {
        set({ user: null, profile: null, role: null, loading: false, ready: true });
        return;
      }
      set({ user, loading: true });
      try {
        const snap = await getDoc(doc(db, 'users', user.uid));
        if (snap.exists()) {
          const profile = snap.data();
          set({ profile, role: profile.role, loading: false, ready: true });
        } else {
          set({ profile: null, role: null, loading: false, ready: true });
        }
      } catch {
        set({ loading: false, ready: true });
      }
    });
  },

  setProfile(profile) { set({ profile, role: profile?.role }); },
  clearAuth() { set({ user: null, profile: null, role: null }); },
}));
