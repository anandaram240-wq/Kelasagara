import { useState, useEffect } from 'react';
import { useSearchParams, Link } from 'react-router-dom';
import { doc, getDoc, updateDoc } from 'firebase/firestore';
import { motion } from 'framer-motion';
import { db } from '../firebase';
import { useAuthStore } from '../store/authStore';
import { useToast } from '../components/Toast';
import Navbar from '../components/Navbar';

const STATUS_COLORS = { PENDING:'#D97706', CONFIRMED:'#16A34A', DECLINED:'#DC2626', COMPLETED:'#2563EB' };
const STATUS_BG = { PENDING:'#FEF3C7', CONFIRMED:'#DCFCE7', DECLINED:'#FEE2E2', COMPLETED:'#DBEAFE' };

export default function BookingDetail() {
  const [params] = useSearchParams();
  const bookingId = params.get('id');
  const { user, role } = useAuthStore();
  const toast = useToast();

  const [booking, setBooking] = useState(null);
  const [other, setOther] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => { if (bookingId) load(); }, [bookingId]);

  async function load() {
    try {
      const snap = await getDoc(doc(db, 'bookings', bookingId));
      if (!snap.exists()) { setLoading(false); return; }
      const b = { id: snap.id, ...snap.data() };
      setBooking(b);
      const otherId = role === 'hirer' ? b.workerId : b.hirerId;
      const oSnap = await getDoc(doc(db, 'users', otherId));
      setOther(oSnap.data());
    } catch (e) { console.error(e); }
    setLoading(false);
  }

  async function updateStatus(status) {
    try {
      await updateDoc(doc(db, 'bookings', bookingId), { status });
      setBooking(b => ({ ...b, status }));
      toast(`Booking ${status.toLowerCase()} ✅`, 'success');
    } catch (e) { toast(e.message, 'error'); }
  }

  if (loading) return <div style={{ display: 'flex', justifyContent: 'center', height: '60vh', alignItems: 'center' }}><div className="spinner" /></div>;
  if (!booking) return <div className="card state-box"><p>Booking not found.</p></div>;

  return (
    <div style={{ minHeight: '100vh', background: 'var(--paper)' }}>
      <Navbar />
      <div style={{ maxWidth: 640, margin: '32px auto', padding: '0 20px' }}>
        <motion.div initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.3 }}>
          <div className="card" style={{ marginBottom: 16 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 16 }}>
              <h2 style={{ fontSize: '1.2rem' }}>📋 {booking.jobTitle || 'Booking Details'}</h2>
              <span style={{ background: STATUS_BG[booking.status], color: STATUS_COLORS[booking.status], padding: '5px 14px', borderRadius: 20, fontWeight: 700, fontSize: '0.82rem' }}>
                {booking.status}
              </span>
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10, fontSize: '0.88rem' }}>
              {[
                ['👷 Worker', booking.workerName],
                ['🏗️ Hirer', booking.hirerName],
                ['📅 Date', `${booking.date || '—'} at ${booking.time || '—'}`],
                ['📍 Location', booking.location],
                ['⏱ Duration', booking.duration],
                ['💰 Pay', booking.pay ? `₹${booking.pay}/day` : '—'],
                ['📝 Instructions', booking.instructions],
              ].filter(([, v]) => v).map(([label, value]) => (
                <div key={label} style={{ display: 'flex', gap: 10 }}>
                  <span style={{ color: 'var(--muted)', minWidth: 120, flexShrink: 0 }}>{label}:</span>
                  <span style={{ color: 'var(--ink)', fontWeight: 500 }}>{value}</span>
                </div>
              ))}
            </div>
          </div>

          {/* Other person info */}
          {other && (
            <div className="card" style={{ display: 'flex', gap: 14, alignItems: 'center', marginBottom: 16 }}>
              <div style={{ width: 48, height: 48, borderRadius: '50%', background: 'var(--saffron)', color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', fontWeight: 700, fontSize: '1.1rem', overflow: 'hidden', flexShrink: 0 }}>
                {other.photo ? <img src={other.photo} alt="" style={{ width: 48, height: 48, objectFit: 'cover' }} /> : (other.name || '?')[0].toUpperCase()}
              </div>
              <div style={{ flex: 1 }}>
                <div style={{ fontWeight: 600 }}>{other.name}</div>
                <div style={{ fontSize: '0.78rem', color: 'var(--muted)' }}>{other.district} · {(other.skills || [])[0]}</div>
                {(booking.status === 'CONFIRMED' || booking.status === 'COMPLETED') && other.phone && (
                  <a href={`tel:${other.phone}`} style={{ fontSize: '0.8rem', color: 'var(--jade)', fontWeight: 600 }}>📞 {other.phone}</a>
                )}
              </div>
            </div>
          )}

          {/* Actions */}
          <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
            <Link to={`/chat?booking=${bookingId}`} className="btn btn-primary" style={{ flex: 1 }}>💬 Open Chat</Link>
            {role === 'worker' && booking.status === 'PENDING' && (
              <>
                <button onClick={() => updateStatus('CONFIRMED')} className="btn btn-secondary" style={{ flex: 1 }}>✅ Confirm</button>
                <button onClick={() => updateStatus('DECLINED')} className="btn btn-danger" style={{ flex: 1 }}>❌ Decline</button>
              </>
            )}
            {role === 'hirer' && booking.status === 'CONFIRMED' && (
              <button onClick={() => updateStatus('COMPLETED')} className="btn btn-ghost" style={{ flex: 1 }}>✔ Mark Complete</button>
            )}
          </div>
        </motion.div>
      </div>
    </div>
  );
}
