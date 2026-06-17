import { useState, useEffect } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { collection, query, where, getDocs, doc, getDoc, updateDoc, serverTimestamp } from 'firebase/firestore';
import { motion, AnimatePresence } from 'framer-motion';
import { db } from '../firebase';
import { useAuthStore } from '../store/authStore';
import { useToast } from '../components/Toast';
import Navbar from '../components/Navbar';
import { sendNotification } from '../components/Notifications';
import { KARNATAKA_DISTRICTS, KARNATAKA_TALUKS } from '../data/karnataka';

// Normalize district key — trims whitespace so KARNATAKA_TALUKS[district] never fails
const normalizeDist = (d = '') => d.trim();
const getTaluks = (d) => KARNATAKA_TALUKS[normalizeDist(d)] || [];

const STATUS_COLORS = { PENDING:'#D97706', CONFIRMED:'#16A34A', DECLINED:'#DC2626', COMPLETED:'#2563EB' };

const tabVariants = {
  initial: { opacity: 0, y: 10 },
  animate: { opacity: 1, y: 0 },
  exit:    { opacity: 0, y: -10 },
};

export default function HirerDashboard() {
  const { user, profile, setProfile } = useAuthStore();
  const toast = useToast();
  const navigate = useNavigate();
  const [activeTab, setActiveTab] = useState('bookings');
  const [bookings, setBookings] = useState([]);
  const [postedJobs, setPostedJobs] = useState([]);
  const [loading, setLoading] = useState(true);
  const [editForm, setEditForm] = useState({});

  useEffect(() => { if (user) loadData(); }, [user]);

  async function loadData() {
    setLoading(true);
    try {
      const [bSnap, jSnap] = await Promise.all([
        getDocs(query(collection(db,'bookings'), where('hirerId','==',user.uid))),
        getDocs(query(collection(db,'jobs'), where('hirerId','==',user.uid))),
      ]);
      // Enrich bookings with worker profiles
      const bList = await Promise.all(bSnap.docs.map(async d => {
        const b = { id:d.id, ...d.data() };
        try { const ws = await getDoc(doc(db,'users',b.workerId)); b.workerData = ws.data(); } catch { b.workerData = {}; }
        return b;
      }));
      setBookings(bList.sort((a,z)=>(z.createdAt?.seconds||0)-(a.createdAt?.seconds||0)));
      setPostedJobs(jSnap.docs.map(d=>({id:d.id,...d.data()})));
    } catch(e) { console.error(e); }
    setLoading(false);
  }

  async function saveProfile() {
    try {
      const updates = {
        name:     editForm.name?.trim()     || profile?.name     || '',
        phone:    editForm.phone?.trim()    || '',
        whatsapp: editForm.whatsapp?.trim() || '',
        district: normalizeDist(editForm.district),
        taluk:    editForm.taluk            || '',
        village:  editForm.village?.trim()  || '',
        company:  editForm.company?.trim()  || '',
        updatedAt: serverTimestamp(),
      };
      await updateDoc(doc(db,'users',user.uid), updates);
      setProfile({ ...profile, ...updates });
      toast('Profile updated ✅', 'success');
      await sendNotification(user.uid, {
        title: 'Profile Updated',
        body: 'Your hirer profile has been saved successfully.',
        type: 'success',
      });
    } catch(e) { toast(e.message, 'error'); }
  }

  const initials = (profile?.name||user?.displayName||'H').split(' ').map(n=>n[0]).join('').slice(0,2).toUpperCase();
  const conversations = bookings.filter(b=>b.workerData?.name);

  const TABS = [
    { id:'bookings',  label:'📋 My Bookings' },
    { id:'convs',     label:'💬 Conversations' },
    { id:'jobs',      label:'🏗️ Posted Jobs' },
    { id:'profile',   label:'👤 Profile' },
  ];

  // Seed editForm fresh whenever profile tab is opened
  // This prevents the stale-fallback bug where old taluk persists
  function openProfileTab() {
    setEditForm({
      name:     profile?.name     || '',
      phone:    profile?.phone    || '',
      whatsapp: profile?.whatsapp || '',
      district: normalizeDist(profile?.district),
      taluk:    profile?.taluk    || '',
      village:  profile?.village  || '',
      company:  profile?.company  || '',
    });
    setActiveTab('profile');
  }

  return (
    <div style={{minHeight:'100vh',background:'var(--paper)'}}>
      <Navbar />
      <div style={{maxWidth:900,margin:'28px auto',padding:'0 20px'}}>
        {/* Profile Card */}
        <motion.div className="card" style={{display:'flex',alignItems:'center',gap:16,marginBottom:24}} initial={{opacity:0,y:-16}} animate={{opacity:1,y:0}}>
          <div style={{width:60,height:60,borderRadius:'50%',background:'var(--saffron)',color:'#fff',display:'flex',alignItems:'center',justifyContent:'center',fontSize:'1.4rem',fontWeight:700,flexShrink:0}}>
            {user?.photoURL ? <img src={user.photoURL} alt="" style={{width:60,height:60,borderRadius:'50%',objectFit:'cover'}}/> : initials}
          </div>
          <div>
            <div style={{fontFamily:"'Baloo Tamma 2',cursive",fontWeight:700,fontSize:'1.1rem'}}>{profile?.name||user?.displayName}</div>
            <div style={{fontSize:'0.8rem',color:'var(--muted)'}}>{user?.email}</div>
            <span className="badge badge-hirer" style={{marginTop:4}}>🏗️ Hirer</span>
          </div>
        </motion.div>

        {/* Tabs */}
        <div className="tabs" style={{marginBottom:20}}>
          {TABS.map(t => (
            <button
              key={t.id}
              className={`tab-btn ${activeTab===t.id?'active':''}`}
              onClick={() => t.id === 'profile' ? openProfileTab() : setActiveTab(t.id)}
            >{t.label}</button>
          ))}
        </div>

        {loading ? (
          <div style={{display:'flex',alignItems:'center',justifyContent:'center',height:'40vh'}}><div className="spinner"/></div>
        ) : (
          <AnimatePresence mode="wait">
            <motion.div key={activeTab} variants={tabVariants} initial="initial" animate="animate" exit="exit" transition={{duration:0.2,ease:[0.4,0,0.2,1]}}>

              {/* MY BOOKINGS */}
              {activeTab === 'bookings' && (
                <div>
                  <div style={{display:'flex',justifyContent:'space-between',alignItems:'center',marginBottom:16}}>
                    <h3>My Worker Bookings</h3>
                    <Link to="/" className="btn btn-primary btn-sm">+ Book a Worker</Link>
                  </div>
                  {bookings.length === 0 ? (
                    <div className="card state-box"><p>No bookings yet.</p><Link to="/" style={{color:'var(--saffron)'}}>Browse Workers →</Link></div>
                  ) : (
                    <div style={{display:'flex',flexDirection:'column',gap:12}}>
                      {bookings.map(b => (
                        <motion.div key={b.id} className="card" style={{display:'flex',alignItems:'flex-start',justifyContent:'space-between',gap:12}} whileHover={{y:-2,boxShadow:'0 8px 24px rgba(0,0,0,0.1)'}}>
                          <div style={{flex:1}}>
                            <div style={{display:'flex',alignItems:'center',gap:8,marginBottom:6}}>
                              <span style={{fontFamily:"'Baloo Tamma 2',cursive",fontWeight:700}}>🔧 {b.jobTitle||'Booking'}</span>
                              <span className="badge" style={{background:`${STATUS_COLORS[b.status]}20`,color:STATUS_COLORS[b.status]}}>{b.status}</span>
                            </div>
                            <div style={{fontSize:'0.8rem',color:'var(--muted)',display:'flex',flexDirection:'column',gap:2}}>
                              <span>👷 Worker: {b.workerData?.name||b.workerName||'—'}</span>
                              <span>📅 {b.date||'—'} at {b.time||'—'}</span>
                              {b.location && <span>📍 {b.location}</span>}
                            </div>
                          </div>
                          <div style={{display:'flex',gap:8,flexShrink:0}}>
                            <Link to={`/chat?booking=${b.id}`} className="btn btn-primary btn-sm">💬 Open Chat</Link>
                            <Link to={`/booking-detail?id=${b.id}`} className="btn btn-ghost btn-sm">View Details</Link>
                          </div>
                        </motion.div>
                      ))}
                    </div>
                  )}
                </div>
              )}

              {/* CONVERSATIONS */}
              {activeTab === 'convs' && (
                <div>
                  <h3 style={{marginBottom:16}}>💬 My Conversations</h3>
                  {conversations.length === 0 ? (
                    <div className="card state-box"><p>No conversations yet.</p></div>
                  ) : (
                    <div style={{display:'flex',flexDirection:'column',gap:10}}>
                      {conversations.map(b => {
                        const initB = (b.workerData?.name||'W')[0].toUpperCase();
                        const trade = (b.workerData?.skills||[])[0] || 'Worker';
                        const dateStr = b.date || (b.createdAt ? new Date(b.createdAt.seconds*1000).toLocaleDateString('en-IN') : '');
                        return (
                          <motion.div key={b.id} style={{display:'flex',alignItems:'center',gap:12,padding:'14px 16px',background:'var(--white)',border:'1px solid var(--border)',borderRadius:12}} whileHover={{y:-1,boxShadow:'0 4px 16px rgba(0,0,0,0.08)'}}>
                            <div style={{width:44,height:44,borderRadius:'50%',background:'var(--saffron)',color:'#fff',display:'flex',alignItems:'center',justifyContent:'center',fontSize:'1rem',fontWeight:700,flexShrink:0}}>
                              {b.workerData?.photo ? <img src={b.workerData.photo} alt="" style={{width:44,height:44,borderRadius:'50%',objectFit:'cover'}}/> : initB}
                            </div>
                            <div style={{flex:1}}>
                              <div style={{fontWeight:600}}>{b.workerData?.name}</div>
                              <div style={{fontSize:'0.75rem',color:'var(--muted)'}}>{trade} · {dateStr}</div>
                            </div>
                            <Link to={`/chat?booking=${b.id}`} className="btn btn-primary btn-sm">💬 Open Chat</Link>
                          </motion.div>
                        );
                      })}
                    </div>
                  )}
                </div>
              )}

              {/* POSTED JOBS */}
              {activeTab === 'jobs' && (
                <div>
                  <div style={{display:'flex',justifyContent:'space-between',alignItems:'center',marginBottom:16}}>
                    <h3>🏗️ Posted Jobs</h3>
                    <Link to="/post-job" className="btn btn-primary btn-sm">+ Post New Job</Link>
                  </div>
                  {postedJobs.length === 0 ? (
                    <div className="card state-box"><p>No jobs posted yet.</p><Link to="/post-job" style={{color:'var(--saffron)',display:'block',marginTop:8}}>Post a Job →</Link></div>
                  ) : (
                    <div style={{display:'flex',flexDirection:'column',gap:10}}>
                      {postedJobs.map(j => (
                        <motion.div key={j.id} className="card" whileHover={{y:-2}}>
                          <div style={{display:'flex',justifyContent:'space-between',alignItems:'flex-start'}}>
                            <div>
                              <div style={{fontFamily:"'Baloo Tamma 2',cursive",fontWeight:700}}>{j.title}</div>
                              <div style={{fontSize:'0.78rem',color:'var(--muted)',marginTop:4}}>📍 {j.district} · 💰 ₹{j.pay}/day · {(j.applicants||[]).length} applicant{(j.applicants||[]).length!==1?'s':''}</div>
                            </div>
                          </div>
                        </motion.div>
                      ))}
                    </div>
                  )}
                </div>
              )}

              {/* PROFILE */}
              {activeTab === 'profile' && (
                <div className="card" style={{maxWidth:520}}>
                  <h3 style={{marginBottom:20}}>👤 My Profile</h3>
                  <div style={{display:'flex',flexDirection:'column',gap:14}}>

                    <div className="form-group">
                      <label className="form-label">Name *</label>
                      <input className="form-input" value={editForm.name||profile?.name||''} onChange={e=>setEditForm(f=>({...f,name:e.target.value}))} placeholder="Your full name" />
                    </div>

                    <div style={{display:'grid',gridTemplateColumns:'1fr 1fr',gap:10}}>
                      <div className="form-group">
                        <label className="form-label">Phone</label>
                        <input className="form-input" type="tel" maxLength={10}
                          value={editForm.phone || ''}
                          onChange={e => setEditForm(f => ({ ...f, phone: e.target.value.replace(/\D/g,'') }))}
                          placeholder="10-digit" />
                      </div>
                      <div className="form-group">
                        <label className="form-label">WhatsApp</label>
                        <input className="form-input" type="tel" maxLength={10}
                          value={editForm.whatsapp || ''}
                          onChange={e => setEditForm(f => ({ ...f, whatsapp: e.target.value.replace(/\D/g,'') }))}
                          placeholder="Optional" />
                      </div>
                    </div>

                    {/* District */}
                    <div className="form-group">
                      <label className="form-label">District *</label>
                      <select className="form-select"
                        value={editForm.district || ''}
                        onChange={e => setEditForm(f => ({ ...f, district: e.target.value, taluk: '' }))}
                      >
                        <option value="">— Select District —</option>
                        {KARNATAKA_DISTRICTS.map(d => (
                          <option key={d.en} value={d.en}>{d.en}</option>
                        ))}
                      </select>
                    </div>

                    {/* Taluk — options come from selected district only */}
                    <div className="form-group">
                      <label className="form-label">Taluk *</label>
                      <select className="form-select"
                        value={editForm.taluk || ''}
                        onChange={e => setEditForm(f => ({ ...f, taluk: e.target.value }))}
                        disabled={!editForm.district}
                      >
                        <option value="">
                          {editForm.district ? '— Select Taluk —' : '— Select District First —'}
                        </option>
                        {getTaluks(editForm.district).map(t => (
                          <option key={t.en} value={t.en}>{t.en}</option>
                        ))}
                      </select>
                    </div>

                    <div className="form-group">
                      <label className="form-label">Village / Town</label>
                      <input className="form-input"
                        value={editForm.village || ''}
                        onChange={e => setEditForm(f => ({ ...f, village: e.target.value }))}
                        placeholder="e.g. Hunsur, Sargur" />
                    </div>

                    <div className="form-group">
                      <label className="form-label">Company / Business Name</label>
                      <input className="form-input"
                        value={editForm.company || ''}
                        onChange={e => setEditForm(f => ({ ...f, company: e.target.value }))}
                        placeholder="Optional" />
                    </div>

                    <motion.button whileTap={{scale:0.97}} className="btn btn-primary" onClick={saveProfile}>
                      💾 Save Profile
                    </motion.button>
                  </div>
                </div>
              )}

            </motion.div>
          </AnimatePresence>
        )}
      </div>
    </div>
  );
}
