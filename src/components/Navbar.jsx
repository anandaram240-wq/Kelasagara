// src/components/Navbar.jsx — Full responsive navbar with hamburger menu
import { useRef, useState, useEffect } from 'react';
import { Link, NavLink, useNavigate, useLocation } from 'react-router-dom';
import { signOut } from 'firebase/auth';
import { motion, AnimatePresence } from 'framer-motion';
import { auth } from '../firebase';
import { useAuthStore } from '../store/authStore';
import NotificationBell from './Notifications';

const KN = {
  home: 'ಮನೆ', jobs: 'ಕೆಲಸ', worker: 'ಕೆಲಸಗಾರ', hirer: 'ನೇಮಕಗಾರ', admin: 'ನಿರ್ವಾಹಕ',
  dashboard: 'ಡ್ಯಾಶ್‌ಬೋರ್ಡ್', messages: 'ಸಂದೇಶಗಳು', logout: 'ಹೊರಹೋಗು',
};
const EN = {
  home: 'Home', jobs: 'Jobs', worker: 'Worker', hirer: 'Hirer', admin: 'Admin',
  dashboard: 'My Dashboard', messages: 'My Messages', logout: 'Logout',
};

export default function Navbar({ lang = 'en', onLangChange }) {
  const { user, profile, role, clearAuth } = useAuthStore();
  const [menuOpen, setMenuOpen]       = useState(false);  // account dropdown
  const [mobileOpen, setMobileOpen]   = useState(false);  // hamburger menu
  const menuRef   = useRef(null);
  const mobileRef = useRef(null);
  const navigate  = useNavigate();
  const location  = useLocation();
  const t = lang === 'kn' ? KN : EN;

  // Close menus on route change
  useEffect(() => {
    setMenuOpen(false);
    setMobileOpen(false);
  }, [location.pathname]);

  // Close account dropdown on outside click
  useEffect(() => {
    function close(e) {
      if (!menuRef.current?.contains(e.target)) setMenuOpen(false);
    }
    document.addEventListener('click', close);
    return () => document.removeEventListener('click', close);
  }, []);

  // Close mobile menu on outside click
  useEffect(() => {
    function close(e) {
      if (!mobileRef.current?.contains(e.target)) setMobileOpen(false);
    }
    document.addEventListener('click', close);
    return () => document.removeEventListener('click', close);
  }, []);

  async function handleLogout() {
    setMenuOpen(false);
    setMobileOpen(false);
    await signOut(auth);
    clearAuth();
    navigate('/login');
  }

  // Smart link destinations
  const workerDest = role === 'worker' ? '/worker-dashboard' : '/find-jobs';
  const hirerDest  = role === 'hirer'  ? '/hirer-dashboard'  : '/';

  const dashUrl = role === 'worker' ? '/worker-dashboard'
                : role === 'hirer'  ? '/hirer-dashboard'
                : '/setup-profile';

  const initials = (profile?.name || user?.displayName || 'U')
    .split(' ').map(n => n[0]).join('').slice(0, 2).toUpperCase();
  const name = profile?.name || user?.displayName?.split(' ')[0] || 'Account';

  // Nav items config — use stable unique ids, not `to`, as key
  const NAV_ITEMS = [
    { id: 'home',   to: '/',              label: `🏠 ${t.home}`,   end: true },
    { id: 'jobs',   to: '/find-jobs',     label: `🧳 ${t.jobs}` },
    { id: 'worker', to: workerDest,       label: `👷 ${t.worker}` },
    { id: 'hirer',  to: hirerDest,        label: `🏗️ ${t.hirer}` },
    { id: 'admin',  to: '/admin',         label: `👮 ${t.admin}` },
  ];

  return (
    <nav className="navbar" ref={mobileRef}>
      {/* Brand */}
      <Link to="/" className="nav-brand">
        <div className="nav-logo-icon">ಕ</div>
        <div>
          <div className="nav-brand-text">Kelasa<span>Gaara</span></div>
          <div style={{ fontSize: '0.62rem', color: 'var(--muted)', marginTop: -2 }}>ಕೆಲಸಗಾರ</div>
        </div>
      </Link>

      {/* Desktop nav links */}
      <div className="nav-links">
        {NAV_ITEMS.map(item => (
          <NavLink
            key={item.id}
            to={item.to}
            end={item.end}
            className={({ isActive }) => `nav-link${isActive ? ' active' : ''}`}
          >
            {item.label}
          </NavLink>
        ))}
      </div>

      {/* Right side */}
      <div className="nav-right">
        {/* Language toggle — desktop only */}
        <div className="lang-toggle nav-lang-desktop">
          <button
            className={`lang-btn ${lang === 'en' ? 'active' : ''}`}
            onClick={() => onLangChange?.('en')}
          >English</button>
          <button
            className={`lang-btn ${lang === 'kn' ? 'active' : ''}`}
            onClick={() => onLangChange?.('kn')}
          >ಕನ್ನಡ</button>
        </div>

        {/* Account dropdown — desktop */}
        {/* 🔔 Notification Bell — only shown to logged-in users */}
        {user && <div className="nav-account-desktop"><NotificationBell /></div>}
        {user ? (
          <div style={{ position: 'relative' }} ref={menuRef} className="nav-account-desktop">
            <button
              onClick={() => setMenuOpen(o => !o)}
              className="avatar-btn"
            >
              <div className="avatar-circle">
                {user.photoURL
                  ? <img src={user.photoURL} alt="" style={{ width: 28, height: 28, objectFit: 'cover' }} />
                  : initials}
              </div>
              <span className="avatar-name">{name.split(' ')[0].toUpperCase()}</span>
              <span style={{ fontSize: '0.7rem', opacity: 0.5 }}>▾</span>
            </button>

            <AnimatePresence>
              {menuOpen && (
                <motion.div
                  id="account-menu"
                  initial={{ opacity: 0, y: -8, scale: 0.97 }}
                  animate={{ opacity: 1, y: 0, scale: 1 }}
                  exit={{ opacity: 0, y: -8, scale: 0.97 }}
                  transition={{ duration: 0.18, ease: [0.4, 0, 0.2, 1] }}
                  style={{ position: 'absolute', right: 0, top: 'calc(100% + 8px)', zIndex: 200 }}
                >
                  <MenuLink to={dashUrl} onClick={() => setMenuOpen(false)}>📊 {t.dashboard}</MenuLink>
                  <MenuLink to="/chat"   onClick={() => setMenuOpen(false)}>💬 {t.messages}</MenuLink>
                  <div style={{ borderTop: '1px solid var(--border)', margin: '4px 0' }} />
                  <button onClick={handleLogout} className="menu-logout-btn">
                    🚪 {t.logout}
                  </button>
                </motion.div>
              )}
            </AnimatePresence>
          </div>
        ) : (
          <Link to="/login" className="btn btn-primary btn-sm nav-account-desktop">Login</Link>
        )}

        {/* ── Hamburger button — mobile only ── */}
        <button
          className="hamburger-btn"
          onClick={e => { e.stopPropagation(); setMobileOpen(o => !o); }}
          aria-label="Open menu"
        >
          <span className={`ham-line ${mobileOpen ? 'open-1' : ''}`} />
          <span className={`ham-line ${mobileOpen ? 'open-2' : ''}`} />
          <span className={`ham-line ${mobileOpen ? 'open-3' : ''}`} />
        </button>
      </div>

      {/* ── Mobile slide-down menu ── */}
      <AnimatePresence>
        {mobileOpen && (
          <motion.div
            className="mobile-nav"
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: 'auto' }}
            exit={{ opacity: 0, height: 0 }}
            transition={{ duration: 0.22, ease: [0.4, 0, 0.2, 1] }}
          >
            {/* Nav links */}
            {NAV_ITEMS.map(item => (
              <NavLink
                key={item.id}
                to={item.to}
                end={item.end}
                className={({ isActive }) => `mobile-nav-link${isActive ? ' active' : ''}`}
                onClick={() => setMobileOpen(false)}
              >
                {item.label}
              </NavLink>
            ))}

            <div className="mobile-nav-divider" />

            {/* Language toggle */}
            <div style={{ display: 'flex', gap: 8, padding: '8px 16px' }}>
              <button
                className={`lang-btn ${lang === 'en' ? 'active' : ''}`}
                onClick={() => { onLangChange?.('en'); }}
                style={{ flex: 1 }}
              >English</button>
              <button
                className={`lang-btn ${lang === 'kn' ? 'active' : ''}`}
                onClick={() => { onLangChange?.('kn'); }}
                style={{ flex: 1 }}
              >ಕನ್ನಡ</button>
            </div>

            {/* Auth actions */}
            {/* 🔔 Notification bell in mobile drawer */}
            {user && (
              <div style={{ padding: '10px 16px', display: 'flex', alignItems: 'center', gap: 10 }}>
                <span style={{ fontSize: '0.82rem', color: 'var(--muted)', fontWeight: 600 }}>Notifications</span>
                <NotificationBell />
              </div>
            )}
            <div className="mobile-nav-divider" />

            {user ? (
              <>
                <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '12px 16px' }}>
                  <div className="avatar-circle" style={{ width: 36, height: 36, fontSize: '0.9rem' }}>
                    {user.photoURL
                      ? <img src={user.photoURL} alt="" style={{ width: 36, height: 36, objectFit: 'cover' }} />
                      : initials}
                  </div>
                  <div>
                    <div style={{ fontWeight: 700, fontSize: '0.88rem' }}>{name}</div>
                    <div style={{ fontSize: '0.72rem', color: 'var(--muted)' }}>{user.email}</div>
                  </div>
                </div>
                <Link to={dashUrl} className="mobile-nav-link" onClick={() => setMobileOpen(false)}>
                  📊 {t.dashboard}
                </Link>
                <Link to="/chat" className="mobile-nav-link" onClick={() => setMobileOpen(false)}>
                  💬 {t.messages}
                </Link>
                <div className="mobile-nav-divider" />
                <button onClick={handleLogout} className="mobile-logout-btn">
                  🚪 {t.logout}
                </button>
              </>
            ) : (
              <Link to="/login" className="btn btn-primary" onClick={() => setMobileOpen(false)}
                style={{ margin: '12px 16px', display: 'block', textAlign: 'center' }}>
                Login
              </Link>
            )}
          </motion.div>
        )}
      </AnimatePresence>
    </nav>
  );
}

function MenuLink({ to, onClick, children }) {
  return (
    <Link to={to} onClick={onClick} style={{
      display: 'flex', alignItems: 'center', gap: 10,
      padding: '12px 16px', fontSize: '0.85rem', color: 'var(--ink)', textDecoration: 'none',
    }}
      onMouseEnter={e => e.currentTarget.style.background = 'var(--paper)'}
      onMouseLeave={e => e.currentTarget.style.background = ''}
    >
      {children}
    </Link>
  );
}
