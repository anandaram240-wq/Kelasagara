// src/components/Notifications.jsx
// ─────────────────────────────────────────────────────────────
// Real-time notification bell for workers & hirers.
// Stores notifications in Firebase RTDB under:
//   notifications/{userId}/{notifId}
// Triggered automatically when:
//   • Worker receives a booking request
//   • Worker's booking is confirmed / declined
//   • Hirer's job gets a new applicant
//   • New chat message received
// ─────────────────────────────────────────────────────────────
import { useState, useEffect, useRef } from 'react';
import { ref, onValue, update, remove, off, push, serverTimestamp } from 'firebase/database';
import { motion, AnimatePresence } from 'framer-motion';
import { rtdb } from '../firebase';
import { useAuthStore } from '../store/authStore';

// ── Helper: create a notification for any user ──────────────
export async function sendNotification(toUid, { title, body, type = 'info', link = '' }) {
  if (!toUid) return;
  try {
    await push(ref(rtdb, `notifications/${toUid}`), {
      title,
      body,
      type,      // 'booking' | 'message' | 'job' | 'info'
      link,
      read: false,
      createdAt: Date.now(),
    });
  } catch (e) {
    console.warn('sendNotification error:', e);
  }
}

// ── Icon map by type ─────────────────────────────────────────
const ICONS = {
  booking: '📋',
  message: '💬',
  job:     '💼',
  info:    'ℹ️',
  success: '✅',
  warning: '⚠️',
};

// ── Colour map by type ────────────────────────────────────────
const TYPE_COLORS = {
  booking: '#E8590C',  // 🎨 booking notification accent — change colour
  message: '#3B82F6',  // 🎨 message notification accent
  job:     '#10B981',  // 🎨 job notification accent
  info:    '#8B5CF6',  // 🎨 info notification accent
  success: '#10B981',
  warning: '#F59E0B',
};

export default function NotificationBell() {
  const { user } = useAuthStore();
  const [notifs, setNotifs]     = useState([]);
  const [open, setOpen]         = useState(false);
  const panelRef                = useRef(null);
  const bellRef                 = useRef(null);

  // Subscribe to RTDB notifications for current user
  useEffect(() => {
    if (!user?.uid) return;
    const r = ref(rtdb, `notifications/${user.uid}`);

    const handler = onValue(r, snap => {
      if (!snap.exists()) { setNotifs([]); return; }
      const list = [];
      snap.forEach(child => {
        list.push({ id: child.key, ...child.val() });
      });
      // Sort newest first
      list.sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0));
      setNotifs(list.slice(0, 30)); // cap at 30
    });

    return () => off(r, 'value', handler);
  }, [user?.uid]);

  // Close panel on outside click
  useEffect(() => {
    function handleClick(e) {
      if (!panelRef.current?.contains(e.target) &&
          !bellRef.current?.contains(e.target)) {
        setOpen(false);
      }
    }
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, []);

  const unread = notifs.filter(n => !n.read).length;

  async function markRead(id) {
    if (!user?.uid) return;
    await update(ref(rtdb, `notifications/${user.uid}/${id}`), { read: true });
  }

  async function markAllRead() {
    if (!user?.uid) return;
    const updates = {};
    notifs.filter(n => !n.read).forEach(n => {
      updates[`notifications/${user.uid}/${n.id}/read`] = true;
    });
    if (Object.keys(updates).length) await update(ref(rtdb), updates);
  }

  async function deleteNotif(id, e) {
    e.stopPropagation();
    if (!user?.uid) return;
    await remove(ref(rtdb, `notifications/${user.uid}/${id}`));
  }

  async function clearAll() {
    if (!user?.uid) return;
    await remove(ref(rtdb, `notifications/${user.uid}`));
  }

  function timeAgo(ts) {
    if (!ts) return '';
    const diff = Date.now() - ts;
    const m = Math.floor(diff / 60000);
    if (m < 1)  return 'just now';
    if (m < 60) return `${m}m ago`;
    const h = Math.floor(m / 60);
    if (h < 24) return `${h}h ago`;
    return `${Math.floor(h / 24)}d ago`;
  }

  if (!user) return null;

  return (
    <div style={{ position: 'relative' }}>
      {/* ── Bell Button ─────────────────────────────────── */}
      <button
        ref={bellRef}
        onClick={() => setOpen(o => !o)}
        aria-label="Notifications"
        style={{
          position: 'relative',
          width: 38, height: 38,
          borderRadius: '50%',
          background: open ? 'var(--paper)' : 'transparent',
          border: `1.5px solid ${open ? 'var(--saffron)' : 'var(--border)'}`,
          cursor: 'pointer',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontSize: '1.1rem',
          transition: 'all 0.2s',
          flexShrink: 0,
        }}
      >
        {/* 🎨 Bell icon — change emoji or replace with SVG */}
        🔔
        {/* Unread badge */}
        {unread > 0 && (
          <motion.span
            initial={{ scale: 0 }}
            animate={{ scale: 1 }}
            style={{
              position: 'absolute', top: -3, right: -3,
              // 🎨 Badge colour — change background
              background: '#EF4444',
              color: '#fff',
              borderRadius: '50%',
              width: 18, height: 18,
              fontSize: '0.65rem', fontWeight: 800,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              border: '2px solid #fff',
              lineHeight: 1,
            }}
          >
            {unread > 9 ? '9+' : unread}
          </motion.span>
        )}
      </button>

      {/* ── Notification Panel ──────────────────────────── */}
      <AnimatePresence>
        {open && (
          <motion.div
            ref={panelRef}
            initial={{ opacity: 0, y: -10, scale: 0.97 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: -10, scale: 0.97 }}
            transition={{ duration: 0.18, ease: [0.4, 0, 0.2, 1] }}
            style={{
              position: 'absolute', right: 0, top: 'calc(100% + 10px)',
              // 🎨 Panel width — change for wider/narrower panel
              width: 340,
              background: '#fff',
              borderRadius: 16,
              boxShadow: '0 8px 40px rgba(0,0,0,0.14)',
              border: '1px solid var(--border)',
              zIndex: 300,
              overflow: 'hidden',
              maxHeight: '80vh',
              display: 'flex', flexDirection: 'column',
            }}
          >
            {/* Panel header */}
            <div style={{
              padding: '14px 16px',
              borderBottom: '1px solid var(--border)',
              display: 'flex', alignItems: 'center', justifyContent: 'space-between',
              background: '#fff',
              flexShrink: 0,
            }}>
              <div>
                <span style={{ fontWeight: 700, fontSize: '0.95rem', color: 'var(--ink)' }}>
                  🔔 Notifications
                </span>
                {unread > 0 && (
                  <span style={{
                    marginLeft: 8,
                    background: '#EF4444',
                    color: '#fff', borderRadius: 20,
                    padding: '1px 7px', fontSize: '0.7rem', fontWeight: 700,
                  }}>{unread} new</span>
                )}
              </div>
              <div style={{ display: 'flex', gap: 8 }}>
                {unread > 0 && (
                  <button onClick={markAllRead} style={{
                    fontSize: '0.72rem', color: 'var(--saffron)', background: 'none',
                    border: 'none', cursor: 'pointer', fontWeight: 600,
                    fontFamily: "'DM Sans', sans-serif",
                  }}>Mark all read</button>
                )}
                {notifs.length > 0 && (
                  <button onClick={clearAll} style={{
                    fontSize: '0.72rem', color: 'var(--muted)', background: 'none',
                    border: 'none', cursor: 'pointer', fontFamily: "'DM Sans', sans-serif",
                  }}>Clear all</button>
                )}
              </div>
            </div>

            {/* Notification list */}
            <div style={{ overflowY: 'auto', flex: 1 }}>
              {notifs.length === 0 ? (
                <div style={{
                  padding: '40px 20px', textAlign: 'center',
                  color: 'var(--muted)', fontSize: '0.88rem',
                }}>
                  <div style={{ fontSize: '2rem', marginBottom: 8 }}>🔕</div>
                  No notifications yet
                </div>
              ) : (
                notifs.map(n => (
                  <motion.div
                    key={n.id}
                    layout
                    initial={{ opacity: 0, x: -10 }}
                    animate={{ opacity: 1, x: 0 }}
                    onClick={() => { markRead(n.id); setOpen(false); }}
                    style={{
                      padding: '12px 16px',
                      borderBottom: '1px solid var(--border)',
                      cursor: 'pointer',
                      display: 'flex', gap: 10, alignItems: 'flex-start',
                      // 🎨 Unread notification background — change rgba colour
                      background: n.read ? '#fff' : 'rgba(232,89,12,0.04)',
                      transition: 'background 0.15s',
                      position: 'relative',
                    }}
                    whileHover={{ background: '#faf7f4' }}
                  >
                    {/* Unread dot */}
                    {!n.read && (
                      <div style={{
                        position: 'absolute', left: 6, top: '50%',
                        transform: 'translateY(-50%)',
                        width: 6, height: 6, borderRadius: '50%',
                        background: 'var(--saffron)',
                      }} />
                    )}

                    {/* Type icon */}
                    <div style={{
                      width: 36, height: 36, borderRadius: '50%', flexShrink: 0,
                      // 🎨 Icon circle background — uses TYPE_COLORS
                      background: `${TYPE_COLORS[n.type] || '#8B5CF6'}18`,
                      display: 'flex', alignItems: 'center',
                      justifyContent: 'center', fontSize: '1rem',
                    }}>
                      {ICONS[n.type] || 'ℹ️'}
                    </div>

                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{
                        fontWeight: n.read ? 500 : 700,
                        fontSize: '0.85rem', color: 'var(--ink)',
                        marginBottom: 2,
                      }}>
                        {n.title}
                      </div>
                      {n.body && (
                        <div style={{
                          fontSize: '0.78rem', color: 'var(--muted)',
                          lineHeight: 1.4,
                          overflow: 'hidden', textOverflow: 'ellipsis',
                          display: '-webkit-box', WebkitLineClamp: 2,
                          WebkitBoxOrient: 'vertical',
                        }}>
                          {n.body}
                        </div>
                      )}
                      <div style={{
                        fontSize: '0.68rem', color: 'var(--muted)',
                        marginTop: 4,
                      }}>
                        {timeAgo(n.createdAt)}
                      </div>
                    </div>

                    {/* Delete button */}
                    <button
                      onClick={e => deleteNotif(n.id, e)}
                      style={{
                        background: 'none', border: 'none', cursor: 'pointer',
                        color: 'var(--muted)', fontSize: '0.85rem',
                        padding: '2px 4px', borderRadius: 4, flexShrink: 0,
                        opacity: 0.5,
                        transition: 'opacity 0.15s',
                      }}
                      onMouseEnter={e => e.currentTarget.style.opacity = '1'}
                      onMouseLeave={e => e.currentTarget.style.opacity = '0.5'}
                    >
                      ✕
                    </button>
                  </motion.div>
                ))
              )}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
