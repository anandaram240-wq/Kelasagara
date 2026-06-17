// ============================================================
// src/pages/Admin.jsx — KelasaGaara Admin Dashboard
// ============================================================
// 🎨 DESIGNER GUIDE — HOW TO CUSTOMISE THIS PAGE
// ─────────────────────────────────────────────
// Every important value has a comment next to it.
// Search for "🎨" to jump to any customisable spot.
//
// COLOUR PALETTE (dark theme):
//   Page background  → ADMIN_COLORS.bg      default: #0F1923
//   Card background  → ADMIN_COLORS.card    default: #1a2535
//   Border colour    → ADMIN_COLORS.border  default: rgba(255,255,255,0.07)
//   Primary orange   → #E8590C   (saffron brand colour)
//   Success green    → #10B981
//   Warning amber    → #F59E0B
//   Danger red       → #EF4444
//   Info blue        → #3B82F6
// ============================================================

import { useState, useEffect } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import {
  collection, getDocs, doc, updateDoc, deleteDoc,
} from 'firebase/firestore';
import { ref, get as rtdbGet, remove } from 'firebase/database';
import { signOut } from 'firebase/auth';
import { motion, AnimatePresence } from 'framer-motion';
import { db, rtdb, auth } from '../firebase';
import { useAuthStore } from '../store/authStore';
import { useToast } from '../components/Toast';

// 🎨 ADMIN EMAIL — only this email can access admin panel
const ADMIN_EMAIL = 'r66810812@gmail.com';

// 🎨 STATUS BADGE COLOURS — change these to restyle booking status pills
const STATUS_COLORS = {
  PENDING:   '#F59E0B', // amber
  CONFIRMED: '#10B981', // green
  DECLINED:  '#EF4444', // red
  COMPLETED: '#3B82F6', // blue
};

// 🎨 ADMIN COLOUR PALETTE — change any value to restyle the entire admin UI
const ADMIN_COLORS = {
  bg:     '#0F1923',                    // page background
  card:   '#1a2535',                    // card / panel background
  topbar: '#111c28',                    // top navigation bar
  border: 'rgba(255,255,255,0.07)',     // subtle divider lines
  text:   '#F0F4F8',                    // primary text
  muted:  'rgba(255,255,255,0.45)',     // secondary / muted text
  input:  '#1f3047',                    // input field background
};

// ── Avatar helper ──────────────────────────────────────────
function Avatar({ name, photo, size = 36 }) {
  const init = (name || '?')[0].toUpperCase();
  if (photo) return (
    <img src={photo} alt=""
      style={{ width: size, height: size, borderRadius: '50%', objectFit: 'cover' }} />
  );
  return (
    // 🎨 Avatar gradient — change the two colours to restyle initials circle
    <div style={{
      width: size, height: size, borderRadius: '50%', flexShrink: 0,
      background: 'linear-gradient(135deg, #E8590C, #D4920A)', // ← gradient colours
      color: '#fff', display: 'flex', alignItems: 'center',
      justifyContent: 'center', fontWeight: 700, fontSize: size * 0.38,
    }}>{init}</div>
  );
}

// ── Stat Card helper ───────────────────────────────────────
function StatCard({ value, label, color = '#E8590C', icon }) {
  return (
    // 🎨 STAT CARD — change background, borderRadius, padding here
    <div style={{
      background: ADMIN_COLORS.card,              // ← card background colour
      border: `1px solid ${ADMIN_COLORS.border}`,
      borderRadius: 14,                           // ← card corner radius (px)
      padding: '20px 18px',
      minWidth: 0,
    }}>
      {icon && <div style={{ fontSize: '1.4rem', marginBottom: 6 }}>{icon}</div>}
      {/* 🎨 STAT NUMBER — change fontSize to make number bigger/smaller */}
      <div style={{
        fontFamily: "'Baloo Tamma 2', cursive",
        fontSize: '2rem',      // ← number size
        fontWeight: 800,
        color,                 // ← number colour (passed as prop)
        lineHeight: 1,
      }}>{value}</div>
      {/* 🎨 STAT LABEL — change fontSize or color here */}
      <div style={{ fontSize: '0.75rem', color: ADMIN_COLORS.muted, marginTop: 6 }}>
        {label}
      </div>
    </div>
  );
}

// ── Main Admin Component ───────────────────────────────────
export default function Admin() {
  const { user, clearAuth, ready } = useAuthStore();
  const navigate = useNavigate();
  const toast    = useToast();

  const [tab, setTab]             = useState('users');
  const [allUsers, setAllUsers]   = useState([]);
  const [bookings, setBookings]   = useState([]);
  const [jobs, setJobs]           = useState([]);
  const [threads, setThreads]     = useState([]);
  const [loading, setLoading]     = useState(true);
  const [search, setSearch]       = useState('');
  const [roleFilter, setRoleFilter]     = useState('All Roles');
  const [statusFilter, setStatusFilter] = useState('All Status');
  const [editUser, setEditUser]   = useState(null);

  // ── Auth guard ──────────────────────────────────────────
  // Waits for Firebase auth to finish loading before redirecting.
  // This prevents the "flash redirect" bug where non-admin users
  // get kicked out before auth even loads.
  useEffect(() => {
    if (!ready) return;                                  // still loading — wait
    if (!user)  { navigate('/login'); return; }          // not logged in
    if (user.email !== ADMIN_EMAIL) { navigate('/'); }  // wrong user
  }, [user, ready]);

  // Load all data only when confirmed as admin
  useEffect(() => {
    if (ready && user?.email === ADMIN_EMAIL) loadAll();
  }, [user, ready]);

  // ── Data loader ────────────────────────────────────────
  async function loadAll() {
    setLoading(true);
    try {
      const [uSnap, bSnap, jSnap] = await Promise.all([
        getDocs(collection(db, 'users')),
        getDocs(collection(db, 'bookings')),
        getDocs(collection(db, 'jobs')),
      ]);

      const users    = uSnap.docs.map(d => ({ id: d.id, ...d.data() }));
      const bkgs     = bSnap.docs
        .map(d => ({ id: d.id, ...d.data() }))
        .sort((a, b) => (b.createdAt?.seconds || 0) - (a.createdAt?.seconds || 0));

      setAllUsers(users);
      setBookings(bkgs);
      setJobs(jSnap.docs.map(d => ({ id: d.id, ...d.data() })));

      // Load RTDB chat threads and enrich with user names from Firestore
      try {
        const snap = await rtdbGet(ref(rtdb, 'chats'));
        if (snap.exists()) {
          const list = [];
          snap.forEach(child => {
            const threadData = child.val();
            // Find matching booking for hirer/worker names
            const matchingBooking = bkgs.find(b =>
              b.hirerId === threadData.hirerId || b.workerId === threadData.workerId
            );
            list.push({
              id: child.key,
              ...threadData,
              hirerName:  matchingBooking?.hirerName  || threadData.hirerName  || '—',
              workerName: matchingBooking?.workerName || threadData.workerName || '—',
              date: threadData.createdAt
                ? new Date(threadData.createdAt).toLocaleDateString('en-IN')
                : matchingBooking?.date || '—',
            });
          });
          setThreads(list);
        }
      } catch (e) { console.warn('RTDB threads:', e); }

    } catch (e) {
      console.error(e);
      toast(e.message, 'error');
    }
    setLoading(false);
  }

  // ── Action handlers ────────────────────────────────────
  async function handleBlock(uid) {
    try {
      await updateDoc(doc(db, 'users', uid), { status: 'blocked', isApproved: false });
      setAllUsers(us => us.map(u => u.id === uid ? { ...u, status: 'blocked' } : u));
      toast('User blocked ✅', 'success');
    } catch (e) { toast(e.message, 'error'); }
  }

  async function handleSuspend(uid, current) {
    const newStatus = current === 'suspended' ? 'active' : 'suspended';
    try {
      await updateDoc(doc(db, 'users', uid), { status: newStatus });
      setAllUsers(us => us.map(u => u.id === uid ? { ...u, status: newStatus } : u));
      toast(`User ${newStatus} ✅`, 'success');
    } catch (e) { toast(e.message, 'error'); }
  }

  async function handleDeleteUser(uid) {
    if (!confirm('Delete this user? This cannot be undone.')) return;
    try {
      await deleteDoc(doc(db, 'users', uid));
      setAllUsers(us => us.filter(u => u.id !== uid));
      toast('User deleted', 'info');
    } catch (e) { toast(e.message, 'error'); }
  }

  async function handleDeleteBooking(id) {
    if (!confirm('Delete this booking?')) return;
    try {
      await deleteDoc(doc(db, 'bookings', id));
      setBookings(bs => bs.filter(b => b.id !== id));
      toast('Booking deleted', 'info');
    } catch (e) { toast(e.message, 'error'); }
  }

  async function handleDeleteThread(threadId) {
    if (!confirm('Delete this chat thread?')) return;
    try {
      await remove(ref(rtdb, `chats/${threadId}`));
      setThreads(ts => ts.filter(t => t.id !== threadId));
      toast('Thread deleted', 'info');
    } catch (e) { toast(e.message, 'error'); }
  }

  async function saveEditUser() {
    try {
      await updateDoc(doc(db, 'users', editUser.id), {
        name:      editUser.name,
        phone:     editUser.phone     || '',
        district:  editUser.district  || '',
        taluk:     editUser.taluk     || '',
        dailyRate: parseInt(editUser.dailyRate) || 0,
      });
      setAllUsers(us => us.map(u => u.id === editUser.id ? { ...u, ...editUser } : u));
      setEditUser(null);
      toast('User updated ✅', 'success');
    } catch (e) { toast(e.message, 'error'); }
  }

  async function handleLogout() {
    await signOut(auth);
    clearAuth();
    navigate('/login');
  }

  // ── Computed values ───────────────────────────────────
  const workers = allUsers.filter(u => u.role === 'worker');
  const hirers  = allUsers.filter(u => u.role === 'hirer');

  const filteredUsers = allUsers.filter(u => {
    const q = search.toLowerCase();
    const matchSearch = !q
      || (u.name  || '').toLowerCase().includes(q)
      || (u.email || '').toLowerCase().includes(q);
    const matchRole = roleFilter === 'All Roles'
      || u.role === roleFilter.toLowerCase();
    return matchSearch && matchRole;
  });

  const filteredBookings = bookings.filter(b =>
    statusFilter === 'All Status' || b.status === statusFilter
  );

  // 🎨 TAB ITEMS — add/remove/rename tabs here
  const TABS = [
    { id: 'users',    icon: '👤', label: 'Users'    },
    { id: 'bookings', icon: '📋', label: 'Bookings' },
    { id: 'jobs',     icon: '🏗',  label: 'Jobs'     },
    { id: 'reports',  icon: '📊', label: 'Reports'  },
    { id: 'messages', icon: '💬', label: 'Messages' },
  ];

  const dark = ADMIN_COLORS; // shorthand alias

  // ── Loading screen while auth resolves ───────────────
  if (!ready) {
    return (
      <div style={{
        minHeight: '100vh', background: dark.bg,
        display: 'flex', alignItems: 'center',
        justifyContent: 'center', flexDirection: 'column', gap: 16,
      }}>
        {/* 🎨 Loading spinner colour — change borderTopColor */}
        <div className="spinner" style={{ borderTopColor: '#E8590C', width: 40, height: 40 }} />
        <p style={{ color: dark.muted, fontFamily: "'DM Sans',sans-serif", fontSize: '0.88rem' }}>
          Verifying admin access…
        </p>
      </div>
    );
  }

  // ── Main render ───────────────────────────────────────
  return (
    <div style={{
      minHeight: '100vh',
      background: dark.bg,  // 🎨 Page background — change dark.bg at top of file
      color: dark.text,
      fontFamily: "'DM Sans', sans-serif",
    }}>

      {/* ══════════════════════════════════════════════════
          TOP BAR
          🎨 Change topbar background → dark.topbar value
          🎨 Change height → height: 56 (pixels)
      ════════════════════════════════════════════════════ */}
      <div style={{
        background: dark.topbar,                      // 🎨 topbar bg colour
        borderBottom: `1px solid ${dark.border}`,
        padding: '0 20px',
        height: 56,                                    // 🎨 topbar height (px)
        display: 'flex', alignItems: 'center', gap: 12,
        position: 'sticky', top: 0, zIndex: 100,      // sticky on scroll
        flexWrap: 'wrap',
      }}>
        {/* Back button */}
        <button onClick={() => navigate('/')} style={{
          background: 'rgba(255,255,255,0.07)',
          border: 'none', color: dark.text,
          padding: '6px 12px', borderRadius: 8,
          cursor: 'pointer', fontSize: '0.82rem', fontWeight: 600,
          display: 'flex', alignItems: 'center', gap: 6,
          whiteSpace: 'nowrap',
        }}>
          ← Back
        </button>

        {/* Brand */}
        <div style={{ fontFamily: "'Baloo Tamma 2', cursive", fontWeight: 800, fontSize: '1.05rem' }}>
          {/* 🎨 Brand text colour — change the span color */}
          Kelasa<span style={{ color: '#E8590C' }}>Gaara</span>
          <span style={{ fontSize: '0.68rem', color: dark.muted, fontFamily: "'DM Sans',sans-serif",
            fontWeight: 400, marginLeft: 8 }}>
            Admin Panel
          </span>
        </div>

        <div style={{ flex: 1 }} />

        {/* 🎨 SUPER ADMIN badge — change background to restyle the badge */}
        <span style={{
          background: '#E8590C',   // ← badge colour
          color: '#fff',
          padding: '3px 10px', borderRadius: 8,
          fontSize: '0.68rem', fontWeight: 800, letterSpacing: '0.06em',
          display: 'none',  // hidden on very small screens via class
        }} className="admin-badge">SUPER ADMIN</span>

        <span style={{ fontSize: '0.82rem', color: dark.muted, maxWidth: 120,
          overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
          {user?.displayName || 'Admin'}
        </span>

        {/* 🎨 Logout button style — change background/borderRadius */}
        <button onClick={handleLogout} style={{
          background: 'rgba(255,255,255,0.07)',
          border: `1px solid ${dark.border}`,
          color: dark.text, padding: '6px 12px',
          borderRadius: 8, cursor: 'pointer',
          fontSize: '0.82rem', fontWeight: 600,
          whiteSpace: 'nowrap',
        }}>
          Logout
        </button>
      </div>

      {/* ══════════════════════════════════════════════════
          MAIN CONTENT AREA
          🎨 Change maxWidth to make panel wider/narrower
          🎨 Change padding for more/less whitespace
      ════════════════════════════════════════════════════ */}
      <div style={{ maxWidth: 1100, margin: '0 auto', padding: '20px 16px' }}>

        {/* ── STATS GRID ──────────────────────────────────
            🎨 Stats grid layout:
              Desktop  → 4 columns (grid-template-columns: repeat(4,1fr))
              Tablet   → 2 columns (via .admin-stats CSS class)
              Mobile   → 2 columns
            🎨 To add a new stat card, copy one <StatCard> line and change props
        ────────────────────────────────────────────────── */}
        <div className="admin-stats">
          {/* 🎨 Each StatCard: value=number, label=text, color=number colour */}
          <StatCard value={allUsers.length} label="Total Users"  color="#E8590C" icon="👥" />
          <StatCard value={workers.length}  label="Workers"      color="#10B981" icon="👷" />
          <StatCard value={hirers.length}   label="Hirers"       color="#3B82F6" icon="🏗" />
          <StatCard value={jobs.length}     label="Jobs Posted"  color="#8B5CF6" icon="💼" />
          <StatCard value={bookings.length} label="Bookings"     color="#F59E0B" icon="📋" />
          <StatCard value={threads.length || '—'} label="Chat Threads" color="#EC4899" icon="💬" />
        </div>

        {/* ── TABS ────────────────────────────────────────
            🎨 Active tab underline colour → borderBottom color
            🎨 Tab text size → fontSize
        ────────────────────────────────────────────────── */}
        <div style={{
          display: 'flex', gap: 0, overflowX: 'auto',
          borderBottom: `2px solid ${dark.border}`,
          marginBottom: 20, marginTop: 20,
          scrollbarWidth: 'none',
        }}>
          {TABS.map(t => (
            <button key={t.id} onClick={() => setTab(t.id)} style={{
              padding: '10px 16px',
              background: 'none', border: 'none', cursor: 'pointer',
              fontFamily: "'DM Sans', sans-serif",
              fontSize: '0.85rem', fontWeight: 600,
              whiteSpace: 'nowrap',
              // 🎨 Active tab colour → change '#E8590C'
              color: tab === t.id ? '#E8590C' : dark.muted,
              borderBottom: `2px solid ${tab === t.id ? '#E8590C' : 'transparent'}`,
              marginBottom: -2,
              transition: 'color 0.2s',
            }}>
              {t.icon} {t.label}
            </button>
          ))}
        </div>

        {/* ── TAB CONTENT ─────────────────────────────── */}
        {loading ? (
          <div style={{ display: 'flex', justifyContent: 'center', padding: 80 }}>
            <div className="spinner" style={{ borderTopColor: '#E8590C' }} />
          </div>
        ) : (
          <AnimatePresence mode="wait">
            <motion.div
              key={tab}
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={{ duration: 0.18 }}
            >

              {/* ════════════════════════════════════════
                  USERS TAB
              ════════════════════════════════════════ */}
              {tab === 'users' && (
                <div>
                  {/* Search + Filter row */}
                  <div style={{ display: 'flex', gap: 10, marginBottom: 14, flexWrap: 'wrap' }}>
                    <div style={{ flex: 1, minWidth: 200, position: 'relative' }}>
                      <span style={{
                        position: 'absolute', left: 12, top: '50%',
                        transform: 'translateY(-50%)', color: dark.muted,
                      }}>🔍</span>
                      <input
                        value={search}
                        onChange={e => setSearch(e.target.value)}
                        placeholder="Search by name or email…"
                        style={{
                          width: '100%', padding: '10px 14px 10px 36px',
                          // 🎨 Search input background — change dark.input
                          background: dark.input,
                          border: `1px solid ${dark.border}`,
                          borderRadius: 10, color: dark.text,
                          fontFamily: "'DM Sans', sans-serif",
                          fontSize: '0.88rem', outline: 'none',
                          boxSizing: 'border-box',
                        }}
                      />
                    </div>
                    {/* 🎨 Role filter dropdown */}
                    <select
                      value={roleFilter}
                      onChange={e => setRoleFilter(e.target.value)}
                      style={{
                        padding: '10px 12px',
                        background: dark.input, border: `1px solid ${dark.border}`,
                        borderRadius: 10, color: dark.text,
                        fontFamily: "'DM Sans', sans-serif",
                        fontSize: '0.85rem', cursor: 'pointer',
                      }}
                    >
                      {['All Roles', 'Worker', 'Hirer'].map(r => (
                        <option key={r}>{r}</option>
                      ))}
                    </select>
                  </div>

                  {/* ── Desktop table / Mobile cards ── */}

                  {/* DESKTOP TABLE (hidden on mobile via CSS) */}
                  <div className="admin-table-wrap">
                    <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.82rem' }}>
                      <thead>
                        <tr style={{ borderBottom: `1px solid ${dark.border}` }}>
                          {/* 🎨 Table header text — change color or fontSize */}
                          {['USER', 'ROLE', 'STATUS', 'DISTRICT', 'TRADE / SKILLS', 'RATE', 'ACTIONS'].map(h => (
                            <th key={h} style={{
                              padding: '11px 14px', textAlign: 'left',
                              color: dark.muted, fontWeight: 600,
                              fontSize: '0.7rem', letterSpacing: '0.05em',
                            }}>{h}</th>
                          ))}
                        </tr>
                      </thead>
                      <tbody>
                        {filteredUsers.map((u, i) => (
                          <tr key={u.id} style={{
                            borderBottom: `1px solid ${dark.border}`,
                            // 🎨 Alternating row background — change the rgba colour
                            background: i % 2 === 0 ? 'transparent' : 'rgba(255,255,255,0.02)',
                          }}>
                            <td style={{ padding: '11px 14px' }}>
                              <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                                <Avatar name={u.name} photo={u.photo} size={34} />
                                <div>
                                  <div style={{ fontWeight: 600, color: dark.text, fontSize: '0.85rem' }}>
                                    {u.name || '—'}
                                  </div>
                                  <div style={{ fontSize: '0.7rem', color: dark.muted }}>
                                    {u.email}
                                  </div>
                                </div>
                              </div>
                            </td>
                            <td style={{ padding: '11px 14px' }}>
                              {/* 🎨 Role badge colours — change background and color */}
                              <span style={{
                                padding: '3px 9px', borderRadius: 20,
                                fontSize: '0.7rem', fontWeight: 700,
                                background: u.role === 'worker'
                                  ? 'rgba(232,89,12,0.15)'   // worker badge bg
                                  : 'rgba(27,107,69,0.2)',   // hirer badge bg
                                color: u.role === 'worker'
                                  ? '#E8590C'                // worker text colour
                                  : '#10B981',               // hirer text colour
                              }}>
                                {u.role === 'worker' ? '👷 Worker'
                                  : u.role === 'hirer' ? '🏗 Hirer' : '—'}
                              </span>
                            </td>
                            <td style={{ padding: '11px 14px' }}>
                              <span style={{
                                fontSize: '0.78rem', fontWeight: 600,
                                // 🎨 Status colours — blocked=red, suspended=amber, active=green
                                color: u.status === 'blocked'   ? '#EF4444'
                                     : u.status === 'suspended' ? '#F59E0B'
                                     : '#10B981',
                              }}>
                                {u.status === 'blocked'   ? '🚫 Blocked'
                                 : u.status === 'suspended' ? '⏸ Suspended'
                                 : '✔ Active'}
                              </span>
                            </td>
                            <td style={{ padding: '11px 14px', color: dark.muted, fontSize: '0.82rem' }}>
                              {u.district || '—'}
                            </td>
                            <td style={{ padding: '11px 14px', color: dark.muted, fontSize: '0.82rem' }}>
                              {(u.skills || []).slice(0, 2).join(', ') || u.trade || '—'}
                            </td>
                            <td style={{ padding: '11px 14px', color: dark.muted, fontSize: '0.82rem' }}>
                              {u.dailyRate ? `₹${u.dailyRate}` : '—'}
                            </td>
                            <td style={{ padding: '11px 14px' }}>
                              <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
                                {/* 🎨 Action buttons — change background/color to restyle */}
                                <button onClick={() => setEditUser({ ...u })} style={{
                                  padding: '4px 8px',
                                  background: 'rgba(59,130,246,0.15)', // blue tint
                                  border: 'none', borderRadius: 6,
                                  color: '#3B82F6', cursor: 'pointer', fontSize: '0.75rem',
                                }}>✏</button>
                                <button onClick={() => handleBlock(u.id)} style={{
                                  padding: '4px 8px',
                                  background: 'rgba(239,68,68,0.15)',  // red tint
                                  border: 'none', borderRadius: 6,
                                  color: '#EF4444', cursor: 'pointer', fontSize: '0.72rem',
                                }}>🚫 Block</button>
                                <button onClick={() => handleSuspend(u.id, u.status)} style={{
                                  padding: '4px 8px',
                                  background: 'rgba(245,158,11,0.15)', // amber tint
                                  border: 'none', borderRadius: 6,
                                  color: '#F59E0B', cursor: 'pointer', fontSize: '0.72rem',
                                }}>
                                  {u.status === 'suspended' ? '▶ Unsuspend' : '⏸ Suspend'}
                                </button>
                                <button onClick={() => handleDeleteUser(u.id)} style={{
                                  padding: '4px 8px',
                                  background: 'rgba(239,68,68,0.1)',   // light red
                                  border: 'none', borderRadius: 6,
                                  color: '#EF4444', cursor: 'pointer', fontSize: '0.75rem',
                                }}>🗑</button>
                              </div>
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                    {filteredUsers.length === 0 && (
                      <div style={{ textAlign: 'center', padding: 40, color: dark.muted }}>
                        No users found
                      </div>
                    )}
                  </div>

                  {/* MOBILE CARDS (shown only on mobile via CSS) */}
                  <div className="admin-mobile-cards">
                    {filteredUsers.map(u => (
                      // 🎨 Mobile user card — change background or borderRadius
                      <div key={u.id} style={{
                        background: dark.card,
                        border: `1px solid ${dark.border}`,
                        borderRadius: 12, padding: '14px',
                        marginBottom: 10,
                      }}>
                        <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 10 }}>
                          <Avatar name={u.name} photo={u.photo} size={40} />
                          <div style={{ flex: 1, minWidth: 0 }}>
                            <div style={{ fontWeight: 700, color: dark.text, fontSize: '0.9rem',
                              overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                              {u.name || '—'}
                            </div>
                            <div style={{ fontSize: '0.72rem', color: dark.muted,
                              overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                              {u.email}
                            </div>
                          </div>
                          <span style={{
                            padding: '3px 9px', borderRadius: 20, fontSize: '0.7rem', fontWeight: 700,
                            background: u.role === 'worker' ? 'rgba(232,89,12,0.15)' : 'rgba(27,107,69,0.2)',
                            color: u.role === 'worker' ? '#E8590C' : '#10B981',
                            flexShrink: 0,
                          }}>
                            {u.role === 'worker' ? 'Worker' : u.role === 'hirer' ? 'Hirer' : '—'}
                          </span>
                        </div>
                        <div style={{ fontSize: '0.78rem', color: dark.muted, marginBottom: 10,
                          display: 'flex', gap: 12, flexWrap: 'wrap' }}>
                          <span>📍 {u.district || '—'}</span>
                          <span>💰 {u.dailyRate ? `₹${u.dailyRate}` : '—'}</span>
                          <span style={{
                            color: u.status === 'blocked' ? '#EF4444'
                                 : u.status === 'suspended' ? '#F59E0B' : '#10B981',
                          }}>
                            {u.status === 'blocked' ? '🚫 Blocked'
                             : u.status === 'suspended' ? '⏸ Suspended' : '✔ Active'}
                          </span>
                        </div>
                        <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                          <button onClick={() => setEditUser({ ...u })} style={{
                            padding: '6px 10px', background: 'rgba(59,130,246,0.15)',
                            border: 'none', borderRadius: 8, color: '#3B82F6',
                            cursor: 'pointer', fontSize: '0.8rem', fontWeight: 600,
                          }}>✏ Edit</button>
                          <button onClick={() => handleBlock(u.id)} style={{
                            padding: '6px 10px', background: 'rgba(239,68,68,0.15)',
                            border: 'none', borderRadius: 8, color: '#EF4444',
                            cursor: 'pointer', fontSize: '0.8rem', fontWeight: 600,
                          }}>🚫 Block</button>
                          <button onClick={() => handleSuspend(u.id, u.status)} style={{
                            padding: '6px 10px', background: 'rgba(245,158,11,0.15)',
                            border: 'none', borderRadius: 8, color: '#F59E0B',
                            cursor: 'pointer', fontSize: '0.8rem', fontWeight: 600,
                          }}>
                            {u.status === 'suspended' ? '▶ Unsuspend' : '⏸ Suspend'}
                          </button>
                          <button onClick={() => handleDeleteUser(u.id)} style={{
                            padding: '6px 10px', background: 'rgba(239,68,68,0.1)',
                            border: 'none', borderRadius: 8, color: '#EF4444',
                            cursor: 'pointer', fontSize: '0.8rem', fontWeight: 600,
                          }}>🗑 Delete</button>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* ════════════════════════════════════════
                  BOOKINGS TAB
                  🎨 Booking card style → change background, borderRadius
              ════════════════════════════════════════ */}
              {tab === 'bookings' && (
                <div>
                  <div style={{ display: 'flex', justifyContent: 'space-between',
                    alignItems: 'center', marginBottom: 14, flexWrap: 'wrap', gap: 10 }}>
                    <h3 style={{ color: dark.text, margin: 0 }}>All Bookings</h3>
                    <select value={statusFilter} onChange={e => setStatusFilter(e.target.value)}
                      style={{
                        padding: '8px 12px', background: dark.input,
                        border: `1px solid ${dark.border}`,
                        borderRadius: 8, color: dark.text,
                        fontSize: '0.85rem', cursor: 'pointer',
                        fontFamily: "'DM Sans', sans-serif",
                      }}>
                      {['All Status', 'PENDING', 'CONFIRMED', 'DECLINED', 'COMPLETED'].map(s => (
                        <option key={s}>{s}</option>
                      ))}
                    </select>
                  </div>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                    {filteredBookings.map(b => (
                      // 🎨 BOOKING CARD — change background/borderRadius/padding
                      <div key={b.id} style={{
                        background: dark.card,           // ← card background
                        border: `1px solid ${dark.border}`,
                        borderRadius: 14,                // ← corner radius
                        padding: '14px 16px',
                      }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between',
                          alignItems: 'flex-start', gap: 10 }}>
                          <div style={{ flex: 1, minWidth: 0 }}>
                            <div style={{ fontWeight: 700, fontSize: '0.92rem',
                              marginBottom: 5, color: dark.text }}>
                              {b.jobTitle || 'Booking'}
                            </div>
                            <div style={{ fontSize: '0.72rem', color: dark.muted,
                              display: 'flex', gap: 12, flexWrap: 'wrap', marginBottom: 10 }}>
                              {b.location && <span>📍 {b.location}</span>}
                              {b.date     && <span>📅 {b.date} {b.time || ''}</span>}
                              {b.pay      && <span>💰 ₹{b.pay}</span>}
                            </div>
                            {/* HIRER → WORKER flow */}
                            <div style={{ display: 'flex', alignItems: 'center',
                              gap: 8, flexWrap: 'wrap' }}>
                              {/* 🎨 Hirer box — change background to restyle */}
                              <div style={{
                                background: 'rgba(255,255,255,0.05)',
                                border: `1px solid ${dark.border}`,
                                borderRadius: 8, padding: '7px 10px', fontSize: '0.7rem',
                              }}>
                                <div style={{ color: dark.muted, fontWeight: 600 }}>
                                  🏗 HIRER
                                </div>
                                <div style={{ color: dark.text, fontWeight: 700, marginTop: 2 }}>
                                  {b.hirerName || '—'}
                                </div>
                              </div>
                              <span style={{ color: dark.muted, fontSize: '1.1rem' }}>→</span>
                              {/* 🎨 Worker box — change background to restyle */}
                              <div style={{
                                background: 'rgba(255,255,255,0.05)',
                                border: `1px solid ${dark.border}`,
                                borderRadius: 8, padding: '7px 10px', fontSize: '0.7rem',
                              }}>
                                <div style={{ color: '#10B981', fontWeight: 600 }}>
                                  👷 WORKER
                                </div>
                                <div style={{ color: dark.text, fontWeight: 700, marginTop: 2 }}>
                                  {b.workerName || '—'}
                                </div>
                              </div>
                            </div>
                          </div>
                          <div style={{ display: 'flex', flexDirection: 'column',
                            gap: 8, alignItems: 'flex-end', flexShrink: 0 }}>
                            {/* 🎨 Status pill — colours come from STATUS_COLORS at top of file */}
                            <span style={{
                              padding: '4px 12px', borderRadius: 20,
                              fontWeight: 700, fontSize: '0.75rem',
                              background: `${STATUS_COLORS[b.status] || '#6B7280'}22`,
                              color: STATUS_COLORS[b.status] || '#6B7280',
                            }}>{b.status || 'PENDING'}</span>
                            {/* 🎨 Delete button — change background/color */}
                            <button onClick={() => handleDeleteBooking(b.id)} style={{
                              padding: '5px 10px',
                              background: '#EF444422',  // ← button background
                              border: 'none', borderRadius: 8,
                              color: '#EF4444',          // ← button text colour
                              cursor: 'pointer', fontSize: '0.75rem', fontWeight: 600,
                            }}>🗑 Delete</button>
                          </div>
                        </div>
                      </div>
                    ))}
                    {filteredBookings.length === 0 && (
                      <div style={{ textAlign: 'center', padding: 60, color: dark.muted }}>
                        No bookings found
                      </div>
                    )}
                  </div>
                </div>
              )}

              {/* ════════════════════════════════════════
                  JOBS TAB
              ════════════════════════════════════════ */}
              {tab === 'jobs' && (
                <div>
                  <h3 style={{ color: dark.text, marginBottom: 14 }}>🏗 All Jobs</h3>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                    {jobs.map(j => (
                      // 🎨 JOB CARD — change background/borderRadius
                      <div key={j.id} style={{
                        background: dark.card,
                        border: `1px solid ${dark.border}`,
                        borderRadius: 12, padding: '13px 16px',
                        display: 'flex', gap: 12,
                        alignItems: 'flex-start', justifyContent: 'space-between',
                        flexWrap: 'wrap',
                      }}>
                        <div>
                          <div style={{ fontWeight: 700, color: dark.text }}>{j.title || 'Job'}</div>
                          <div style={{ fontSize: '0.75rem', color: dark.muted,
                            marginTop: 4, display: 'flex', gap: 12, flexWrap: 'wrap' }}>
                            <span>📍 {j.district || '—'}</span>
                            <span>💰 ₹{j.pay || 0}/day</span>
                            <span>👥 {(j.applicants || []).length} applicants</span>
                          </div>
                        </div>
                        <button onClick={async () => {
                          if (!confirm('Delete this job?')) return;
                          const { deleteDoc, doc } = await import('firebase/firestore');
                          await deleteDoc(doc(db, 'jobs', j.id));
                          setJobs(js => js.filter(x => x.id !== j.id));
                          toast('Job deleted', 'info');
                        }} style={{
                          padding: '5px 12px',
                          background: '#EF444422', // ← delete button bg
                          border: 'none', borderRadius: 8,
                          color: '#EF4444',
                          cursor: 'pointer', fontSize: '0.75rem',
                          fontWeight: 600, flexShrink: 0,
                        }}>
                          🗑 Delete
                        </button>
                      </div>
                    ))}
                    {jobs.length === 0 && (
                      <div style={{ textAlign: 'center', padding: 60, color: dark.muted }}>
                        No jobs posted yet
                      </div>
                    )}
                  </div>
                </div>
              )}

              {/* ════════════════════════════════════════
                  REPORTS TAB
                  🎨 Report cards — change background, number colour
              ════════════════════════════════════════ */}
              {tab === 'reports' && (
                <div>
                  <h3 style={{ color: dark.text, marginBottom: 16 }}>📊 Platform Reports</h3>
                  {/* 🎨 Reports grid — change gridTemplateColumns for layout */}
                  <div className="admin-reports-grid">
                    {[
                      { label: 'Total Users',         value: allUsers.length,                               icon: '👥', color: '#E8590C' },
                      { label: 'Workers',              value: workers.length,                                icon: '👷', color: '#10B981' },
                      { label: 'Hirers',               value: hirers.length,                                icon: '🏗', color: '#3B82F6' },
                      { label: 'Total Bookings',       value: bookings.length,                              icon: '📋', color: '#F59E0B' },
                      { label: 'Confirmed Bookings',   value: bookings.filter(b => b.status === 'CONFIRMED').length, icon: '✅', color: '#10B981' },
                      { label: 'Pending Bookings',     value: bookings.filter(b => b.status === 'PENDING').length,   icon: '⏳', color: '#F59E0B' },
                      { label: 'Jobs Posted',          value: jobs.length,                                  icon: '💼', color: '#8B5CF6' },
                      { label: 'Active Chat Threads',  value: threads.length,                               icon: '💬', color: '#EC4899' },
                    ].map(r => (
                      // 🎨 Individual report card — change background/borderRadius
                      <div key={r.label} style={{
                        background: dark.card,
                        border: `1px solid ${dark.border}`,
                        borderRadius: 12, padding: '16px 18px',
                      }}>
                        <div style={{ fontSize: '1.5rem', marginBottom: 5 }}>{r.icon}</div>
                        {/* 🎨 Report number — change fontSize to make bigger */}
                        <div style={{
                          fontFamily: "'Baloo Tamma 2', cursive",
                          fontSize: '1.8rem', fontWeight: 800, color: r.color,
                        }}>{r.value}</div>
                        <div style={{ fontSize: '0.78rem', color: dark.muted }}>{r.label}</div>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* ════════════════════════════════════════
                  MESSAGES TAB
                  🎨 Thread card — change background/borderRadius
              ════════════════════════════════════════ */}
              {tab === 'messages' && (
                <div>
                  <h3 style={{ color: dark.text, marginBottom: 14 }}>
                    💬 Active Chat Threads
                    <span style={{ fontSize: '0.8rem', color: dark.muted,
                      fontWeight: 400, marginLeft: 8 }}>
                      ({threads.length} total)
                    </span>
                  </h3>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                    {/* Pull threads from RTDB — enriched with names from bookings */}
                    {threads.map(t => (
                      // 🎨 THREAD CARD — change background/borderRadius
                      <div key={t.id} style={{
                        background: dark.card,
                        border: `1px solid ${dark.border}`,
                        borderRadius: 12, padding: '13px 15px',
                        display: 'flex', alignItems: 'center',
                        gap: 12, flexWrap: 'wrap',
                      }}>
                        <span style={{ fontSize: '1.1rem', flexShrink: 0 }}>💬</span>
                        <div style={{ flex: 1, display: 'flex', gap: 8, flexWrap: 'wrap', minWidth: 0 }}>
                          {/* 🎨 Hirer info box — change background */}
                          <div style={{
                            background: 'rgba(255,255,255,0.05)',
                            borderRadius: 8, padding: '7px 10px',
                            fontSize: '0.72rem', minWidth: 110, flex: 1,
                          }}>
                            <div style={{ color: dark.muted, fontWeight: 600 }}>🏗 HIRER</div>
                            <div style={{ color: dark.text, fontWeight: 700, marginTop: 2 }}>
                              {t.hirerName || '—'}
                            </div>
                          </div>
                          {/* 🎨 Worker info box — change background */}
                          <div style={{
                            background: 'rgba(255,255,255,0.05)',
                            borderRadius: 8, padding: '7px 10px',
                            fontSize: '0.72rem', minWidth: 110, flex: 1,
                          }}>
                            <div style={{ color: '#10B981', fontWeight: 600 }}>👷 WORKER</div>
                            <div style={{ color: dark.text, fontWeight: 700, marginTop: 2 }}>
                              {t.workerName || '—'}
                            </div>
                          </div>
                        </div>
                        <div style={{ fontSize: '0.7rem', color: dark.muted,
                          flexShrink: 0, textAlign: 'right' }}>
                          {t.date}
                          <div style={{ marginTop: 2, opacity: 0.7 }}>
                            ID: {t.id.slice(0, 14)}…
                          </div>
                        </div>
                        {/* 🎨 Delete thread button */}
                        <button onClick={() => handleDeleteThread(t.id)} style={{
                          padding: '5px 10px',
                          background: '#EF444422',
                          border: 'none', borderRadius: 8,
                          color: '#EF4444', cursor: 'pointer',
                          fontSize: '0.75rem', fontWeight: 600, flexShrink: 0,
                        }}>🗑 Delete</button>
                      </div>
                    ))}
                    {/* Show bookings as fallback if no RTDB threads */}
                    {threads.length === 0 && bookings.filter(b => b.hirerId && b.workerId).map(b => (
                      <div key={b.id} style={{
                        background: dark.card,
                        border: `1px solid ${dark.border}`,
                        borderRadius: 12, padding: '13px 15px',
                        display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap',
                      }}>
                        <span style={{ fontSize: '1.1rem' }}>💬</span>
                        <div style={{ flex: 1, display: 'flex', gap: 8, flexWrap: 'wrap' }}>
                          <div style={{ background: 'rgba(255,255,255,0.05)',
                            borderRadius: 8, padding: '7px 10px', fontSize: '0.72rem', flex: 1 }}>
                            <div style={{ color: dark.muted, fontWeight: 600 }}>🏗 HIRER</div>
                            <div style={{ color: dark.text, fontWeight: 700 }}>
                              {b.hirerName || '—'}
                            </div>
                          </div>
                          <div style={{ background: 'rgba(255,255,255,0.05)',
                            borderRadius: 8, padding: '7px 10px', fontSize: '0.72rem', flex: 1 }}>
                            <div style={{ color: '#10B981', fontWeight: 600 }}>👷 WORKER</div>
                            <div style={{ color: dark.text, fontWeight: 700 }}>
                              {b.workerName || '—'}
                            </div>
                          </div>
                        </div>
                        <div style={{ fontSize: '0.7rem', color: dark.muted, flexShrink: 0 }}>
                          {b.date}
                        </div>
                      </div>
                    ))}
                    {threads.length === 0 && bookings.filter(b => b.hirerId && b.workerId).length === 0 && (
                      <div style={{ textAlign: 'center', padding: 60, color: dark.muted }}>
                        No chat threads found
                      </div>
                    )}
                  </div>
                </div>
              )}

            </motion.div>
          </AnimatePresence>
        )}
      </div>

      {/* ══════════════════════════════════════════════════
          EDIT USER MODAL
          🎨 Modal card — change background/maxWidth/borderRadius
      ════════════════════════════════════════════════════ */}
      <AnimatePresence>
        {editUser && (
          <motion.div
            initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
            style={{
              position: 'fixed', inset: 0,
              background: 'rgba(0,0,0,0.72)',  // 🎨 overlay darkness
              zIndex: 1000,
              display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 16,
            }}
            onClick={e => { if (e.target === e.currentTarget) setEditUser(null); }}
          >
            <motion.div
              initial={{ scale: 0.9, y: 20 }} animate={{ scale: 1, y: 0 }} exit={{ scale: 0.9 }}
              style={{
                background: dark.card,             // 🎨 modal background colour
                borderRadius: 16,                  // 🎨 modal corner radius
                padding: '24px',
                width: '100%', maxWidth: 420,      // 🎨 modal width
                border: `1px solid ${dark.border}`,
                maxHeight: '90vh', overflowY: 'auto',
              }}
            >
              <h3 style={{ color: dark.text, marginBottom: 18 }}>✏ Edit User</h3>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
                {[
                  ['Name',           'name'],
                  ['Phone',          'phone'],
                  ['District',       'district'],
                  ['Taluk',          'taluk'],
                  ['Daily Rate (₹)', 'dailyRate'],
                ].map(([label, key]) => (
                  <div key={key}>
                    <label style={{ fontSize: '0.75rem', color: dark.muted,
                      display: 'block', marginBottom: 4 }}>{label}</label>
                    {/* 🎨 Edit input — change background (dark.input) or borderRadius */}
                    <input
                      value={editUser[key] || ''}
                      onChange={e => setEditUser(u => ({ ...u, [key]: e.target.value }))}
                      style={{
                        width: '100%', padding: '9px 11px',
                        background: dark.input,
                        border: `1px solid ${dark.border}`,
                        borderRadius: 8, color: dark.text,
                        fontFamily: "'DM Sans', sans-serif",
                        fontSize: '0.88rem', outline: 'none',
                        boxSizing: 'border-box',
                      }}
                    />
                  </div>
                ))}
              </div>
              <div style={{ display: 'flex', gap: 10, marginTop: 18 }}>
                {/* 🎨 Cancel button */}
                <button onClick={() => setEditUser(null)} style={{
                  flex: 1, padding: '10px',
                  background: 'rgba(255,255,255,0.07)',
                  border: 'none', borderRadius: 8,
                  color: dark.muted, cursor: 'pointer',
                  fontFamily: "'DM Sans', sans-serif", fontWeight: 600,
                }}>Cancel</button>
                {/* 🎨 Save button — change background to restyle */}
                <button onClick={saveEditUser} style={{
                  flex: 2, padding: '10px',
                  background: '#E8590C',    // ← save button colour
                  border: 'none', borderRadius: 8,
                  color: '#fff', cursor: 'pointer',
                  fontFamily: "'DM Sans', sans-serif", fontWeight: 700,
                }}>Save Changes</button>
              </div>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
