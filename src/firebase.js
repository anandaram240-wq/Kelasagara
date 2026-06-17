// src/firebase.js — Central Firebase init
import { initializeApp } from 'firebase/app';
import { getAuth, GoogleAuthProvider } from 'firebase/auth';
import { getFirestore } from 'firebase/firestore';
import { getDatabase } from 'firebase/database';
import { getAnalytics } from 'firebase/analytics';

const firebaseConfig = {
  apiKey:            "AIzaSyAvV3uX383CaTJu9_uJ7pFGtqFwK2v73Pk",
  authDomain:        "kelasagara-f127a.firebaseapp.com",
  databaseURL:       "https://kelasagara-f127a-default-rtdb.asia-southeast1.firebasedatabase.app",
  projectId:         "kelasagara-f127a",
  storageBucket:     "kelasagara-f127a.firebasestorage.app",
  messagingSenderId: "993968093461",
  appId:             "1:993968093461:web:dc8424333fef88cb47d11c",
  measurementId:     "G-TT0VWJ1MT1"
};

const app      = initializeApp(firebaseConfig);
export const auth      = getAuth(app);
export const db        = getFirestore(app);
export const rtdb      = getDatabase(app);
export const analytics = getAnalytics(app);
export const googleProvider = new GoogleAuthProvider();
googleProvider.setCustomParameters({ prompt: 'select_account' });

export default app;
