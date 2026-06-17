import { useState, useEffect } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import {
  doc, getDoc, updateDoc, collection, query, where, getDocs, serverTimestamp, onSnapshot
} from 'firebase/firestore';
import { motion, AnimatePresence } from 'framer-motion';
import { db } from '../firebase';
import { useAuthStore } from '../store/authStore';
import { useToast } from '../components/Toast';
import Navbar from '../components/Navbar';
import { sendNotification } from '../components/Notifications';
import { KARNATAKA_DISTRICTS, KARNATAKA_TALUKS, TRADES, EXPERIENCE_OPTIONS } from '../data/karnataka';

// Normalize district string: trim whitespace so KARNATAKA_TALUKS lookup never fails
const normalizeDist = (d = '') => d.trim();
// Get taluks safely — returns array of {en, kn} objects
const getTaluks = (district) => KARNATAKA_TALUKS[normalizeDist(district)] || [];

const SKILLS = ['Mason','Plumber','Electrician','Carpenter','Painter','Driver','Cook','Gardener','Security Guard','Helper','Labour','Welder','Tailor','Mechanic'];
const STATUS_COLORS = {
  PENDING: '#D97706',
  CONFIRMED: '#16A34A',
  DECLINED: '#DC2626',
  COMPLETED: '#2563EB',
};

export default function WorkerDashboard() {
  const { user, profile, setProfile } = useAuthStore();
  const toast = useToast();
  const navigate = useNavigate();
  const [bookings, setBookings] = useState([]);
  const [appliedJobs, setAppliedJobs] = useState([]);
  const [conversations, setConversations] = useState([]);
  const [skills, setSkills] = useState(profile?.skills || []);
  const [newSkill, setNewSkill] = useState('');
  const [loading, setLoading] = useState(true);
  const [editOpen, setEditOpen] = useState(false);
  const [editForm, setEditForm] = useState({});

  useEffect(() => {
    if (!user) return;
    setSkills(profile?.skills || []);
    
    // Set up real-time listener for incoming bookings
    const qBookings = query(collection(db, 'bookings'), where('workerId', '==', user.uid));
    const unsubscribeBookings = onSnapshot(qBookings, async (snapshot) => {
      const bList = snapshot.docs.map(d => ({ id: d.id, ...d.data() }));
      const sorted = bList.sort((a, b) => (b.createdAt?.seconds || 0) - (a.createdAt?.seconds || 0));
      setBookings(sorted);

      // Trigger instant toast notification if worker is online when a new pending booking is created
      snapshot.docChanges().forEach((change) => {
        if (change.type === 'added') {
          const newDoc = change.doc.data();
          const isRecent = newDoc.createdAt && (Date.now() - newDoc.createdAt.toMillis() < 25000);
          if (newDoc.status === 'PENDING' && isRecent) {
            toast(`📋 New Request: "${newDoc.jobTitle}" from ${newDoc.hirerName || 'Hirer'}!`, 'info');
          }
        }
      });

      // Build real-time conversations
      const convs = await Promise.all(
        sorted.map(async b => {
          try {
            const hs = await getDoc(doc(db, 'users', b.hirerId));
            return { ...b, hirerData: hs.data() };
          } catch {
            return { ...b, hirerData: {} };
          }
        })
      );
      setConversations(convs.filter(c => c.hirerData?.name));
      setLoading(false);
    }, (err) => {
      console.error("Bookings snapshot error:", err);
      setLoading(false);
    });

    // Load static applied jobs
    async function loadAppliedJobs() {
      try {
        const jobSnap = await getDocs(query(collection(db, 'jobs'), where('applicants', 'array-contains', user.uid)));
        setAppliedJobs(jobSnap.docs.map(d => ({ id: d.id, ...d.data() })));
      } catch (e) {
        console.error(e);
      }
    }
    loadAppliedJobs();

    return () => {
      unsubscribeBookings();
    };
  }, [user, profile]);

  // Action function to Accept or Reject bookings
  async function handleUpdateStatus(bookingId, newStatus, hirerId, jobTitle) {
    try {
      await updateDoc(doc(db, 'bookings', bookingId), {
        status: newStatus,
        updatedAt: serverTimestamp()
      });
      toast(`Booking ${newStatus === 'CONFIRMED' ? 'accepted' : 'rejected'} successfully!`, 'success');

      // Send RTDB notification back to Hirer
      const notifTitle = newStatus === 'CONFIRMED' ? '✅ Booking Accepted' : '❌ Booking Declined';
      const notifBody = newStatus === 'CONFIRMED'
        ? `${profile?.name || user?.displayName || 'The worker'} has accepted your booking request for "${jobTitle}".`
        : `${profile?.name || user?.displayName || 'The worker'} has declined your booking request for "${jobTitle}".`;

      await sendNotification(hirerId, {
        title: notifTitle,
        body: notifBody,
        type: 'booking',
        link: '/hirer-dashboard'
      });
    } catch (e) {
      toast(e.message, 'error');
    }
  }


  async function saveSkills() {
    try {
      await updateDoc(doc(db, 'users', user.uid), { skills, updatedAt: serverTimestamp() });
      setProfile({ ...profile, skills });
      toast('Skills saved ✅', 'success');
    } catch (e) {
      toast(e.message, 'error');
    }
  }

  async function saveEditProfile() {
    try {
      const updates = {
        name:       editForm.name?.trim() || profile?.name,
        phone:      editForm.phone?.trim() || '',
        whatsapp:   editForm.whatsapp?.trim() || '',
        district:   normalizeDist(editForm.district),
        taluk:      editForm.taluk || '',
        village:    editForm.village?.trim() || '',
        trade:      editForm.trade || '',
        experience: editForm.experience || '',
        dailyRate:  parseInt(editForm.dailyRate) || 0,
        updatedAt:  serverTimestamp(),
      };
      await updateDoc(doc(db, 'users', user.uid), updates);
      setProfile({ ...profile, ...updates });
      setEditOpen(false);
      toast('Profile updated ✅', 'success');
      // Notify self that profile was updated
      await sendNotification(user.uid, {
        title: 'Profile Updated',
        body: `Your profile has been updated successfully.`,
        type: 'success',
      });
    } catch (e) { toast(e.message, 'error'); }
  }

  function addSkill() {
    const s = newSkill.trim();
    if (s && !skills.includes(s)) { setSkills(sk => [...sk, s]); }
    setNewSkill('');
  }

  const initials = (profile?.name || user?.displayName || 'U')
    .split(' ')
    .map(n => n[0])
    .join('')
    .slice(0, 2)
    .toUpperCase();

  return (
    <>
    <div style={{ minHeight: '100vh', background: 'var(--paper)' }}>
      <Navbar />
      {loading ? (
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '60vh' }}>
          <div className="spinner" />
        </div>
      ) : (
        <div className="dashboard-layout">
          {/* LEFT — Profile Sidebar */}
          <motion.div
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ duration: 0.35 }}
          >
            <div className="profile-card">
              <div className="profile-banner" />
              <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', padding: '0 16px 16px' }}>
                <div className="profile-avatar" style={{ marginTop: -32 }}>
                  {user?.photoURL
                    ? <img src={user.photoURL} alt="" style={{ width: 64, height: 64, borderRadius: '50%', objectFit: 'cover' }} />
                    : initials}
                </div>
                <div className="profile-name" style={{ marginTop: 12 }}>{profile?.name || user?.displayName}</div>
                <div className="profile-email">{user?.email}</div>
                <span className="badge badge-worker" style={{ marginTop: 8 }}>👷 Worker</span>
              </div>
              <div className="profile-details">
                {[
                  ['📍', 'District', profile?.district],
                  ['🏘️', 'Taluk', profile?.taluk],
                  ['🔧', 'Trade', (profile?.skills || [])[0]],
                  ['📅', 'Experience', profile?.experience],
                  ['💰', 'Daily Rate', profile?.dailyRate ? `₹${profile.dailyRate}/day` : null],
                  ['📞', 'Phone', profile?.phone],
                ].map(([icon, label, val]) =>
                  val ? (
                    <div key={label} className="profile-detail-row">
                      <span>{icon}</span>
                      <span><strong>{label}:</strong> {val}</span>
                    </div>
                  ) : null
                )}
              </div>
              <div style={{ padding: '0 16px 16px' }}>
                <button
                  onClick={() => {
                    // Always init fresh from latest profile so district/taluk pre-fill correctly
                    setEditForm({
                      name:       profile?.name || '',
                      phone:      profile?.phone || '',
                      whatsapp:   profile?.whatsapp || '',
                      district:   normalizeDist(profile?.district),
                      taluk:      profile?.taluk || '',
                      village:    profile?.village || '',
                      trade:      profile?.trade || '',
                      experience: profile?.experience || '',
                      dailyRate:  profile?.dailyRate || '',
                    });
                    setEditOpen(true);
                  }}
                  className="btn btn-ghost"
                  style={{ width: '100%', fontSize: '0.82rem' }}
                >
                  ✏️ Edit Profile
                </button>
              </div>
            </div>
          </motion.div>

          {/* RIGHT — Main Content */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
            {/* Skills Section */}
            <motion.div
              className="card"
              initial={{ opacity: 0, y: 16 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.3, delay: 0.1 }}
            >
              <h3 style={{ marginBottom: 14 }}>⚙️ My Skills / ಕೌಶಲ್ಯಗಳು</h3>
              <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginBottom: 12 }}>
                {skills.map(s => (
                  <span
                    key={s}
                    style={{
                      display: 'inline-flex',
                      alignItems: 'center',
                      gap: 6,
                      padding: '5px 12px',
                      background: 'var(--saffron-light)',
                      color: 'var(--saffron)',
                      border: '1px solid var(--saffron)',
                      borderRadius: 20,
                      fontSize: '0.82rem',
                      fontWeight: 600,
                    }}
                  >
                    {s}
                    <button
                      onClick={() => setSkills(sk => sk.filter(x => x !== s))}
                      style={{
                        background: 'none',
                        border: 'none',
                        cursor: 'pointer',
                        color: 'var(--saffron)',
                        fontWeight: 700,
                        fontSize: '1rem',
                        lineHeight: 1,
                      }}
                    >
                      ×
                    </button>
                  </span>
                ))}
              </div>
              <div style={{ display: 'flex', gap: 8 }}>
                <input
                  className="form-input"
                  style={{ flex: 1 }}
                  value={newSkill}
                  onChange={e => setNewSkill(e.target.value)}
                  onKeyDown={e => e.key === 'Enter' && addSkill()}
                  placeholder="Add a skill e.g. Mason, Driver"
                />
                <button className="btn btn-secondary btn-sm" onClick={addSkill}>Add</button>
              </div>
              <button className="btn btn-ghost btn-sm" style={{ marginTop: 10 }} onClick={saveSkills}>
                💾 Save Skills
              </button>
            </motion.div>

            {/* Messages Section */}
            {conversations.length > 0 && (
              <motion.div
                className="card"
                initial={{ opacity: 0, y: 16 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.3, delay: 0.15 }}
              >
                <h3 style={{ marginBottom: 14 }}>💬 Messages</h3>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                  {conversations.slice(0, 3).map(c => (
                    <div
                      key={c.id}
                      style={{
                        display: 'flex',
                        alignItems: 'center',
                        gap: 12,
                        padding: '10px 0',
                        borderBottom: '1px solid var(--border)',
                      }}
                    >
                      <div className="conv-avatar" style={{ width: 44, height: 44 }}>
                        {c.hirerData?.photo
                          ? <img src={c.hirerData.photo} style={{ width: 44, height: 44, borderRadius: '50%', objectFit: 'cover' }} alt="" />
                          : (c.hirerData?.name || 'H')[0].toUpperCase()}
                      </div>
                      <div style={{ flex: 1 }}>
                        <div style={{ fontWeight: 600, fontSize: '0.9rem' }}>{c.hirerData?.name}</div>
                        <div style={{ fontSize: '0.75rem', color: 'var(--muted)' }}>
                          {(c.hirerData?.skills || [])[0] || 'Hirer'}
                        </div>
                      </div>
                      <Link to={`/chat?booking=${c.id}`} className="btn btn-primary btn-sm">
                        💬 Open Chat
                      </Link>
                    </div>
                  ))}
                </div>
              </motion.div>
            )}

            {/* Incoming Booking Requests */}
            <motion.div
              className="card"
              initial={{ opacity: 0, y: 16 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.3, delay: 0.2 }}
            >
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14 }}>
                <h3>📋 Incoming Booking Requests</h3>
                <span style={{ fontSize: '0.78rem', color: 'var(--muted)', background: 'var(--paper)', padding: '3px 10px', borderRadius: 20 }}>
                  {bookings.length} total
                </span>
              </div>
              {bookings.length === 0 ? (
                <div className="state-box" style={{ padding: '30px 20px' }}>
                  <p>No booking requests yet.</p>
                </div>
              ) : (
                <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                  {bookings.map(b => (
                    <div key={b.id} className="booking-card">
                      <div style={{ flex: 1 }}>
                        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6 }}>
                          <span className="booking-trade">🔧 {b.jobTitle || 'Booking'}</span>
                          <span
                            className="badge"
                            style={{
                              background: `${STATUS_COLORS[b.status] || '#9CA3AF'}20`,
                              color: STATUS_COLORS[b.status] || '#9CA3AF',
                            }}
                          >
                            {b.status}
                          </span>
                        </div>
                        <div className="booking-meta">
                          <span>👤 Hirer: {b.hirerName || '—'}</span>
                          <span>📅 {b.date || '—'} {b.time || ''}</span>
                          {b.location && <span>📍 {b.location}</span>}
                          {b.workLocation && (
                            <div style={{
                              marginTop: 6, background: 'rgba(66,133,244,0.06)', border: '1px solid rgba(66,133,244,0.2)',
                              borderRadius: 8, padding: '8px', display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 10
                            }}>
                              <div style={{fontSize:'0.72rem',color:'var(--muted)',lineHeight:1.4}}>
                                <span style={{fontWeight:700,color:'#4285F4'}}>📍 Specific Location: </span>
                                {b.workLocation.address}
                              </div>
                              <a href={b.workLocation.mapsUrl} target="_blank" rel="noreferrer" style={{
                                background: '#4285F4', color: '#fff', fontSize: '0.7rem', fontWeight: 600,
                                padding: '4px 8px', borderRadius: 6, textDecoration: 'none', flexShrink: 0
                              }}>🗺 Maps</a>
                            </div>
                          )}
                        </div>
                      </div>
                      <div style={{ display: 'flex', flexDirection: 'column', gap: 6, justifyContent: 'center', minWidth: 100 }}>
                        <Link to={`/chat?booking=${b.id}`} className="btn btn-ghost btn-sm" style={{ fontSize: '0.75rem', padding: '6px 12px' }}>
                          💬 Chat
                        </Link>
                        {b.status === 'PENDING' && (
                          <>
                            <button
                              onClick={() => handleUpdateStatus(b.id, 'CONFIRMED', b.hirerId, b.jobTitle || 'Booking')}
                              className="btn btn-sm"
                              style={{ background: '#16A34A', color: '#fff', fontSize: '0.75rem', fontWeight: 700, padding: '6px 12px', border: 'none', borderRadius: 8, cursor: 'pointer' }}
                            >
                              ✅ Accept
                            </button>
                            <button
                              onClick={() => handleUpdateStatus(b.id, 'DECLINED', b.hirerId, b.jobTitle || 'Booking')}
                              className="btn btn-sm"
                              style={{ background: '#DC2626', color: '#fff', fontSize: '0.75rem', fontWeight: 700, padding: '6px 12px', border: 'none', borderRadius: 8, cursor: 'pointer' }}
                            >
                              ❌ Reject
                            </button>
                          </>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </motion.div>

            {/* Jobs I Applied To */}
            <motion.div
              className="card"
              initial={{ opacity: 0, y: 16 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.3, delay: 0.25 }}
            >
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14 }}>
                <h3>💼 Jobs I Applied To</h3>
                <Link to="/find-jobs" className="btn btn-secondary btn-sm">+ Find More</Link>
              </div>
              {appliedJobs.length === 0 ? (
                <div className="state-box" style={{ padding: '30px 20px' }}>
                  <p>You haven't applied to any jobs yet.</p>
                  <Link to="/find-jobs" style={{ color: 'var(--saffron)', fontWeight: 600, display: 'block', marginTop: 8 }}>
                    Browse jobs →
                  </Link>
                </div>
              ) : (
                <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                  {appliedJobs.map(j => (
                    <div key={j.id} className="booking-card">
                      <div>
                        <div className="booking-trade">{j.title || 'Job'}</div>
                        <div className="booking-meta">
                          <span>📍 {j.district}</span>
                          <span>💰 ₹{j.pay}/day</span>
                          {j.workLocation && (
                            <div style={{ marginTop: 6, display: 'flex', alignItems: 'center', gap: 6 }}>
                              <span style={{fontSize:'0.7rem',color:'#4285F4',fontWeight:700}}>📍 Exact Location Added</span>
                              <a href={j.workLocation.mapsUrl} target="_blank" rel="noreferrer" style={{
                                background: 'rgba(66,133,244,0.1)', color: '#4285F4', fontSize: '0.65rem', fontWeight: 700,
                                padding: '2px 6px', borderRadius: 4, textDecoration: 'none'
                              }}>View Map</a>
                            </div>
                          )}
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </motion.div>
          </div>
        </div>
      )}
    </div>

    {/* ── Edit Profile Modal ── */}
    <AnimatePresence>
      {editOpen && (
        <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
          style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.55)', zIndex: 1000, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 16 }}
          onClick={e => { if (e.target === e.currentTarget) setEditOpen(false); }}>
          <motion.div initial={{ scale: 0.92, y: 20 }} animate={{ scale: 1, y: 0 }} exit={{ scale: 0.92 }}
            style={{ background: '#fff', borderRadius: 18, padding: '28px 28px 24px', width: '100%', maxWidth: 500, maxHeight: '90vh', overflowY: 'auto', boxShadow: '0 20px 60px rgba(0,0,0,0.2)' }}>
            <h3 style={{ marginBottom: 20, fontFamily: "'Baloo Tamma 2',cursive" }}>✏️ Edit Profile</h3>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 13 }}>
              {/* Name */}
              <div className="form-group">
                <label className="form-label">Display Name *</label>
                <input className="form-input" value={editForm.name || ''} onChange={e => setEditForm(f => ({ ...f, name: e.target.value }))} placeholder="Your full name" />
              </div>
              {/* Phone */}
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
                <div className="form-group">
                  <label className="form-label">Phone *</label>
                  <input className="form-input" type="tel" maxLength={10} value={editForm.phone || ''} onChange={e => setEditForm(f => ({ ...f, phone: e.target.value.replace(/\D/g,'') }))} placeholder="10-digit" />
                </div>
                <div className="form-group">
                  <label className="form-label">WhatsApp</label>
                  <input className="form-input" type="tel" maxLength={10} value={editForm.whatsapp || ''} onChange={e => setEditForm(f => ({ ...f, whatsapp: e.target.value.replace(/\D/g,'') }))} placeholder="Optional" />
                </div>
              </div>
              {/* District */}
              <div className="form-group">
                <label className="form-label">District *</label>
                <select className="form-select" value={editForm.district || ''} onChange={e => setEditForm(f => ({ ...f, district: e.target.value, taluk: '' }))}>
                  <option value="">— Select District —</option>
                  {KARNATAKA_DISTRICTS.map(d => <option key={d.en} value={d.en}>{d.en}</option>)}
                </select>
              </div>
              {/* Taluk */}
              <div className="form-group">
                <label className="form-label">Taluk *</label>
                <select className="form-select" value={editForm.taluk || ''}
                  onChange={e => setEditForm(f => ({ ...f, taluk: e.target.value }))}
                  disabled={!editForm.district}
                >
                  <option value="">{editForm.district ? '— Select Taluk —' : '— Select District First —'}</option>
                  {getTaluks(editForm.district).map(t => (
                    <option key={t.en} value={t.en}>{t.en}</option>
                  ))}
                </select>
              </div>
              {/* Village */}
              <div className="form-group">
                <label className="form-label">Village / Town</label>
                <input className="form-input" value={editForm.village || ''} onChange={e => setEditForm(f => ({ ...f, village: e.target.value }))} placeholder="e.g. Hunsur, Sargur" />
              </div>
              {/* Trade */}
              <div className="form-group">
                <label className="form-label">Primary Trade / Skill *</label>
                <select className="form-select" value={editForm.trade || ''} onChange={e => setEditForm(f => ({ ...f, trade: e.target.value }))}>
                  <option value="">— Select Trade —</option>
                  {TRADES.map(tr => <option key={tr.en} value={tr.en}>{tr.en}</option>)}
                </select>
              </div>
              {/* Experience + Daily Rate */}
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
                <div className="form-group">
                  <label className="form-label">Experience</label>
                  <select className="form-select" value={editForm.experience || ''} onChange={e => setEditForm(f => ({ ...f, experience: e.target.value }))}>
                    <option value="">— Select —</option>
                    {EXPERIENCE_OPTIONS.map(ex => <option key={ex.en} value={ex.en}>{ex.en}</option>)}
                  </select>
                </div>
                <div className="form-group">
                  <label className="form-label">Daily Rate (₹)</label>
                  <input className="form-input" type="number" value={editForm.dailyRate || ''} onChange={e => setEditForm(f => ({ ...f, dailyRate: e.target.value }))} placeholder="e.g. 500" />
                </div>
              </div>
            </div>
            <div style={{ display: 'flex', gap: 10, marginTop: 22 }}>
              <button onClick={() => setEditOpen(false)} className="btn btn-ghost" style={{ flex: 1 }}>✕ Cancel</button>
              <motion.button onClick={saveEditProfile} className="btn btn-primary" whileTap={{ scale: 0.97 }} style={{ flex: 2 }}>
                💾 Save Profile
              </motion.button>
            </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
    </>
  );
}
