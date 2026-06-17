// Book.jsx — Hirer books a worker
import { useState, useEffect } from 'react';
import { useSearchParams, useNavigate } from 'react-router-dom';
import { doc, getDoc, addDoc, collection, serverTimestamp } from 'firebase/firestore';
import { motion, AnimatePresence } from 'framer-motion';
import { db } from '../firebase';
import { useAuthStore } from '../store/authStore';
import { useToast } from '../components/Toast';
import Navbar from '../components/Navbar';
import LocationPicker from '../components/LocationPicker';

export default function Book() {
  const [params] = useSearchParams();
  const workerId = params.get('worker');
  const navigate = useNavigate();
  const { user, profile } = useAuthStore();
  const toast = useToast();

  const [worker, setWorker] = useState(null);
  const [loading, setLoading] = useState(true);
  const [booking, setBooking] = useState(false);
  const [showLocationPicker, setShowLocationPicker] = useState(false);
  const [form, setForm] = useState({
    jobTitle: '',
    date: '',
    time: '',
    location: '',
    workLocation: null,
    duration: '',
    instructions: '',
    pay: '',
  });

  useEffect(() => {
    if (workerId) loadWorker();
  }, [workerId]);

  async function loadWorker() {
    try {
      const snap = await getDoc(doc(db, 'users', workerId));
      if (snap.exists()) setWorker({ id: snap.id, ...snap.data() });
    } catch (e) { console.error(e); }
    setLoading(false);
  }

  const set = (k, v) => setForm(f => ({ ...f, [k]: v }));

  async function handleBook() {
    if (!form.jobTitle || !form.date) { toast('Please fill Job Title and Date', 'error'); return; }
    setBooking(true);
    try {
      const bookingRef = await addDoc(collection(db, 'bookings'), {
        hirerId:    user.uid,
        hirerName:  profile?.name || user?.displayName || '',
        workerId:   worker.id,
        workerName: worker.name || '',
        jobTitle:   form.jobTitle,
        date:       form.date,
        time:       form.time,
        location:   form.location,
        workLocation: form.workLocation,
        duration:   form.duration,
        instructions: form.instructions,
        pay:        parseInt(form.pay) || worker.dailyRate || 0,
        status:     'PENDING',
        createdAt:  serverTimestamp(),
      });
      toast('✅ Booking sent! Worker will confirm.', 'success');
      navigate(`/chat?booking=${bookingRef.id}`);
    } catch (e) { toast(e.message, 'error'); }
    setBooking(false);
  }

  const STATUS_COLORS = { PENDING:'#D97706', CONFIRMED:'#16A34A' };
  const trade = (worker?.skills || [])[0] || 'Worker';

  return (
    <div style={{ minHeight: '100vh', background: 'var(--paper)' }}>
      <Navbar />
      <div style={{ maxWidth: 600, margin: '32px auto', padding: '0 20px' }}>
        {loading ? (
          <div style={{ display: 'flex', justifyContent: 'center', padding: 60 }}><div className="spinner" /></div>
        ) : !worker ? (
          <div className="card state-box"><p>Worker not found.</p></div>
        ) : (
          <motion.div initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.3 }}>
            {/* Worker summary card */}
            <div className="card" style={{ display: 'flex', gap: 14, alignItems: 'center', marginBottom: 20 }}>
              <div style={{ width: 56, height: 56, borderRadius: '50%', background: 'var(--saffron)', color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: '1.3rem', fontWeight: 700, flexShrink: 0, overflow: 'hidden' }}>
                {worker.photo ? <img src={worker.photo} alt="" style={{ width: 56, height: 56, objectFit: 'cover' }} /> : (worker.name || 'W')[0].toUpperCase()}
              </div>
              <div style={{ flex: 1 }}>
                <div style={{ fontFamily: "'Baloo Tamma 2',cursive", fontWeight: 700, fontSize: '1.05rem' }}>{worker.name}</div>
                <div style={{ fontSize: '0.8rem', color: 'var(--muted)' }}>{trade} · {worker.district}</div>
                <div style={{ fontSize: '0.82rem', color: 'var(--jade)', fontWeight: 600, marginTop: 4 }}>₹{worker.dailyRate || '—'}/day</div>
              </div>
              <span className="badge badge-worker">👷 Worker</span>
            </div>

            {/* Booking form */}
            <div className="card">
              <h3 style={{ marginBottom: 20 }}>📅 Book {worker.name?.split(' ')[0]}</h3>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
                <div className="form-group">
                  <label className="form-label">Job Title *</label>
                  <input className="form-input" value={form.jobTitle} onChange={e => set('jobTitle', e.target.value)} placeholder="e.g. House painting, Plumbing repair…" />
                </div>
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
                  <div className="form-group">
                    <label className="form-label">Date *</label>
                    <input className="form-input" type="date" value={form.date} onChange={e => set('date', e.target.value)} min={new Date().toISOString().split('T')[0]} />
                  </div>
                  <div className="form-group">
                    <label className="form-label">Time</label>
                    <input className="form-input" type="time" value={form.time} onChange={e => set('time', e.target.value)} />
                  </div>
                </div>
                <div className="form-group">
                  <label className="form-label">Location / Address</label>
                  <textarea
                    className="form-textarea"
                    value={form.location}
                    onChange={e => set('location', e.target.value)}
                    placeholder="Enter full address or landmark…"
                    rows={2}
                  />
                  
                  {/* Location Picker Button / Display */}
                  <div style={{ marginTop: 8 }}>
                    {form.workLocation ? (
                      <div style={{
                        background: 'var(--paper2)', border: '1px solid var(--border)',
                        borderRadius: 12, padding: '12px 14px', position: 'relative'
                      }}>
                        <div style={{ fontWeight: 600, fontSize: '0.85rem', marginBottom: 4 }}>
                          📍 Specific Map Location Added
                        </div>
                        <div style={{ fontSize: '0.8rem', color: 'var(--muted)', marginBottom: 8 }}>
                          {form.workLocation.address}
                        </div>
                        <div style={{ display: 'flex', gap: 8 }}>
                          <a href={form.workLocation.mapsUrl} target="_blank" rel="noreferrer" style={{
                            fontSize: '0.75rem', color: '#fff', background: '#4285F4',
                            padding: '4px 10px', borderRadius: 6, textDecoration: 'none', fontWeight: 600
                          }}>Open in Maps</a>
                          <button onClick={() => setShowLocationPicker(true)} style={{
                            fontSize: '0.75rem', color: 'var(--saffron)', background: 'transparent',
                            border: '1px solid var(--saffron)', padding: '4px 10px', borderRadius: 6, cursor: 'pointer', fontWeight: 600
                          }}>Change Position</button>
                        </div>
                      </div>
                    ) : (
                      <button
                        onClick={() => setShowLocationPicker(true)}
                        style={{
                          width: '100%', padding: '12px', borderRadius: 12,
                          background: 'var(--paper2)', border: '2px dashed var(--border)',
                          color: 'var(--ink)', fontWeight: 600, fontSize: '0.9rem',
                          cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8
                        }}
                      >
                        📍 Pin Location on Map (Optional)
                      </button>
                    )}
                  </div>
                </div>
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
                  <div className="form-group">
                    <label className="form-label">Duration</label>
                    <select className="form-select" value={form.duration} onChange={e => set('duration', e.target.value)}>
                      <option value="">Select</option>
                      <option>1 Day</option><option>2-3 Days</option><option>1 Week</option><option>2 Weeks</option><option>1 Month</option><option>Ongoing</option>
                    </select>
                  </div>
                  <div className="form-group">
                    <label className="form-label">Pay (₹/day)</label>
                    <input className="form-input" type="number" value={form.pay} onChange={e => set('pay', e.target.value)} placeholder={worker.dailyRate || '500'} />
                  </div>
                </div>
                <div className="form-group">
                  <label className="form-label">Special Instructions</label>
                  <textarea className="form-textarea" value={form.instructions} onChange={e => set('instructions', e.target.value)} placeholder="Any specific requirements…" rows={2} />
                </div>
                <motion.button className="btn btn-primary" onClick={handleBook} disabled={booking} whileTap={{ scale: 0.97 }} style={{ marginTop: 4 }}>
                  {booking ? '⏳ Sending Booking…' : '📅 Confirm Booking'}
                </motion.button>
                <p style={{ fontSize: '0.78rem', textAlign: 'center' }}>The worker will confirm your booking. You can chat after booking.</p>
              </div>
            </div>
          </motion.div>
        )}
      </div>

      <AnimatePresence>
        {showLocationPicker && (
          <LocationPicker
            value={form.workLocation}
            onChange={(loc) => setForm(f => ({ ...f, workLocation: loc }))}
            onClose={() => setShowLocationPicker(false)}
          />
        )}
      </AnimatePresence>
    </div>
  );
}
