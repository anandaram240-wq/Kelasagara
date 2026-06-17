// src/pages/Login.jsx
// ─────────────────────────────────────────────────────────────
// Login page — matches the original KelasaGaara design exactly:
//   • Login / Sign Up tabs
//   • Worker / Hirer role cards (radio-style)
//   • Google login button (disabled until role selected)
//   • Back to Home + Admin Login links
// ─────────────────────────────────────────────────────────────
import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { signInWithPopup } from 'firebase/auth';
import { doc, getDoc } from 'firebase/firestore';
import { motion, AnimatePresence } from 'framer-motion';
import { auth, db, googleProvider } from '../firebase';
import { useAuthStore } from '../store/authStore';
import { useToast } from '../components/Toast';

// 🎨 Only this email gets admin access — change if needed
const ADMIN_EMAIL = 'r66810812@gmail.com';

export default function Login() {
  const { user, role, ready } = useAuthStore();
  const navigate = useNavigate();
  const toast    = useToast();

  // 'login' | 'signup'
  const [tab, setTab]           = useState('login');
  // 'worker' | 'hirer' | ''
  const [selectedRole, setSelectedRole] = useState('');
  const [loading, setLoading]   = useState(false);

  // ── Auto-redirect when already logged in ──────────────────
  useEffect(() => {
    if (!ready || !user) return;
    if (user.email === ADMIN_EMAIL)  { navigate('/admin',            { replace: true }); return; }
    if (role === 'worker')            navigate('/worker-dashboard',   { replace: true });
    else if (role === 'hirer')        navigate('/hirer-dashboard',    { replace: true });
    else if (user)                    navigate('/setup-profile',      { replace: true });
  }, [user, role, ready]);

  // ── Google Sign-In ─────────────────────────────────────────
  async function handleGoogle() {
    if (!selectedRole && tab !== 'login') {
      toast('Please select Worker or Hirer first', 'error');
      return;
    }
    setLoading(true);
    try {
      const result = await signInWithPopup(auth, googleProvider);
      const fbUser = result.user;

      // Admin bypass
      if (fbUser.email === ADMIN_EMAIL) {
        navigate('/admin', { replace: true });
        return;
      }

      const snap = await getDoc(doc(db, 'users', fbUser.uid));
      if (!snap.exists()) {
        // New user — go to setup with pre-selected role hint
        navigate('/setup-profile', { state: { roleHint: selectedRole } });
      } else {
        const data = snap.data();
        if (data.role === 'worker') navigate('/worker-dashboard');
        else                        navigate('/hirer-dashboard');
      }
    } catch (e) {
      toast('Login failed: ' + e.message, 'error');
    }
    setLoading(false);
  }

  // ── Role card component ────────────────────────────────────
  function RoleCard({ value, emoji, title, sub }) {
    const active = selectedRole === value;
    return (
      <motion.div
        onClick={() => setSelectedRole(value)}
        whileHover={{ scale: 1.03 }}
        whileTap={{ scale: 0.97 }}
        style={{
          flex: 1,
          border: `2px solid ${active ? 'var(--saffron)' : 'var(--border)'}`,
          // 🎨 Role card background — change '#fff' or add gradient
          background: active ? 'rgba(232,89,12,0.06)' : '#fff',
          borderRadius: 14,
          padding: '18px 12px',
          cursor: 'pointer',
          textAlign: 'center',
          transition: 'all 0.2s',
          position: 'relative',
        }}
      >
        {/* Radio dot */}
        <div style={{
          position: 'absolute', top: 10, left: 10,
          width: 16, height: 16, borderRadius: '50%',
          border: `2px solid ${active ? 'var(--saffron)' : '#ccc'}`,
          background: active ? 'var(--saffron)' : 'transparent',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          {active && <div style={{ width: 6, height: 6, borderRadius: '50%', background: '#fff' }} />}
        </div>

        <div style={{ fontSize: '2rem', marginBottom: 8 }}>{emoji}</div>
        <div style={{
          fontFamily: "'Baloo Tamma 2', cursive",
          fontWeight: 700, fontSize: '1rem',
          // 🎨 Role title colour
          color: active ? 'var(--saffron)' : 'var(--ink)',
          marginBottom: 4,
        }}>{title}</div>
        <div style={{ fontSize: '0.75rem', color: 'var(--muted)', lineHeight: 1.4 }}>{sub}</div>
      </motion.div>
    );
  }

  const canLogin = tab === 'login' || selectedRole !== '';

  return (
    <motion.div
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.35, ease: [0.4, 0, 0.2, 1] }}
      style={{
        minHeight: '100vh',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        // 🎨 Page background colour
        background: 'var(--paper)',
        padding: '20px',
      }}
    >
      <div className="card" style={{
        maxWidth: 420, width: '100%',
        // 🎨 Card padding
        padding: '32px 28px',
        boxShadow: '0 8px 40px rgba(0,0,0,0.10)',
      }}>

        {/* ── Logo ─────────────────────────────── */}
        <div style={{ textAlign: 'center', marginBottom: 24 }}>
          <div style={{
            width: 56, height: 56, borderRadius: 14, margin: '0 auto 10px',
            // 🎨 Logo gradient — change colours
            background: 'linear-gradient(135deg, var(--saffron), var(--gold))',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontSize: '1.7rem', color: '#fff',
          }}>ಕ</div>
          <h2 style={{
            fontFamily: "'Baloo Tamma 2', cursive",
            fontSize: '1.45rem', color: 'var(--ink)', margin: 0,
          }}>
            Kelasa<span style={{ color: 'var(--saffron)' }}>Gaara</span>
          </h2>
        </div>

        {/* ── Login / Sign Up Tabs ──────────────── */}
        <div style={{
          display: 'flex', background: 'var(--paper2)',
          borderRadius: 12, padding: 4, marginBottom: 22,
        }}>
          {['login', 'signup'].map(t => (
            <button
              key={t}
              onClick={() => { setTab(t); setSelectedRole(''); }}
              style={{
                flex: 1, padding: '9px 0', borderRadius: 9, border: 'none',
                cursor: 'pointer', fontSize: '0.88rem', fontWeight: 700,
                fontFamily: "'DM Sans', sans-serif",
                // 🎨 Active tab bg and text colour
                background: tab === t ? '#fff' : 'transparent',
                color:      tab === t ? 'var(--ink)' : 'var(--muted)',
                boxShadow:  tab === t ? '0 1px 6px rgba(0,0,0,0.08)' : 'none',
                transition: 'all 0.18s',
              }}
            >
              {t === 'login' ? '🔑 Login' : '✨ Sign Up'}
            </button>
          ))}
        </div>

        {/* ── Info Banner ───────────────────────── */}
        <AnimatePresence mode="wait">
          <motion.div
            key={tab}
            initial={{ opacity: 0, y: 6 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -6 }}
            transition={{ duration: 0.18 }}
          >
            {/* Banner */}
            <div style={{
              // 🎨 Info banner background — change rgba colour
              background: 'rgba(232,89,12,0.08)',
              border: '1px solid rgba(232,89,12,0.18)',
              borderRadius: 10, padding: '10px 14px',
              fontSize: '0.82rem', color: 'var(--saffron)',
              marginBottom: 20, lineHeight: 1.5,
            }}>
              {tab === 'login'
                ? '👋 Already have an account? Select your role and sign in with Google.'
                : '✨ New here? Pick your role and create your account with Google.'}
            </div>

            {/* ── Role Cards (always shown) ─────── */}
            <div style={{ marginBottom: 16 }}>
              <div style={{
                fontSize: '0.7rem', fontWeight: 700, letterSpacing: '0.08em',
                color: 'var(--muted)', marginBottom: 10, textTransform: 'uppercase',
              }}>I AM A…</div>
              <div style={{ display: 'flex', gap: 12 }}>
                <RoleCard
                  value="worker"
                  emoji="👷"
                  title="Worker"
                  sub="Find daily wage jobs"
                />
                <RoleCard
                  value="hirer"
                  emoji="🏗️"
                  title="Hirer"
                  sub="Post jobs & hire workers"
                />
              </div>
            </div>

            {/* Helper text */}
            <p style={{
              textAlign: 'center', fontSize: '0.78rem',
              color: selectedRole ? 'var(--jade)' : 'var(--muted)',
              marginBottom: 16, transition: 'color 0.2s',
            }}>
              {selectedRole
                ? `✅ ${selectedRole === 'worker' ? 'Worker' : 'Hirer'} selected — ready to sign in`
                : 'Select your role to continue'}
              <br />
              <span style={{ color: 'var(--muted)' }}>Sign in with Google</span>
            </p>

            {/* ── Google Button ─────────────────── */}
            <motion.button
              onClick={handleGoogle}
              disabled={loading}
              whileHover={canLogin && !loading ? { scale: 1.02, boxShadow: '0 6px 20px rgba(0,0,0,0.14)' } : {}}
              whileTap={canLogin && !loading ? { scale: 0.97 } : {}}
              style={{
                width: '100%',
                display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 10,
                padding: '13px 20px', borderRadius: 12, border: 'none',
                cursor: loading ? 'wait' : 'pointer',
                fontSize: '0.95rem', fontWeight: 700,
                fontFamily: "'DM Sans', sans-serif",
                // 🎨 Google button colour — changes when role is selected
                background: loading
                  ? '#ccc'
                  : selectedRole
                    ? 'var(--ink)'
                    : '#9CA3AF',            // grey when no role picked
                color: '#fff',
                transition: 'all 0.22s',
              }}
            >
              {/* Google G logo */}
              {!loading && (
                <svg width="18" height="18" viewBox="0 0 24 24">
                  <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
                  <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
                  <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
                  <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
                </svg>
              )}
              {loading
                ? 'Signing in…'
                : selectedRole
                  ? `Login as ${selectedRole === 'worker' ? 'Worker' : 'Hirer'} with Google`
                  : 'Login with Google'}
            </motion.button>

          </motion.div>
        </AnimatePresence>

        {/* ── Footer Links ──────────────────────── */}
        <div style={{
          marginTop: 20, display: 'flex',
          justifyContent: 'space-between', alignItems: 'center',
          fontSize: '0.78rem',
        }}>
          <Link to="/" style={{ color: 'var(--muted)', textDecoration: 'none' }}>
            ← Back to Home
          </Link>
          <Link to="/admin" style={{ color: 'var(--muted)', textDecoration: 'none' }}>
            Admin Login →
          </Link>
        </div>

        {/* Terms */}
        <p style={{
          marginTop: 14, fontSize: '0.7rem',
          color: 'var(--muted)', textAlign: 'center', lineHeight: 1.5,
        }}>
          By continuing, you agree to our{' '}
          <span style={{ color: 'var(--saffron)', cursor: 'pointer' }}>Terms of Service</span>
          {' '}and{' '}
          <span style={{ color: 'var(--saffron)', cursor: 'pointer' }}>Privacy Policy</span>.
        </p>

      </div>
    </motion.div>
  );
}
