// src/pages/PostJob.jsx — 3-step job posting wizard for hirers
import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { collection, addDoc, serverTimestamp } from 'firebase/firestore';
import { motion, AnimatePresence } from 'framer-motion';
import { db } from '../firebase';
import { useAuthStore } from '../store/authStore';
import { useToast } from '../components/Toast';
import Navbar from '../components/Navbar';
import { KARNATAKA_DISTRICTS, KARNATAKA_TALUKS } from '../data/karnataka';
import LocationPicker from '../components/LocationPicker';

const SKILLS = ['Mason','Plumber','Electrician','Carpenter','Painter','Driver','Cook','Gardener','Security Guard','Helper','Labour','Welder'];

const STEPS = ['📋 What', '📍 Where', '📅 When'];

const slideVariants = {
  enter: (dir) => ({ x: dir > 0 ? 60 : -60, opacity: 0 }),
  center: { x: 0, opacity: 1 },
  exit:  (dir) => ({ x: dir > 0 ? -60 : 60, opacity: 0 }),
};

export default function PostJob() {
  const { user, profile } = useAuthStore();
  const toast = useToast();
  const navigate = useNavigate();
  const [step, setStep] = useState(0);
  const [dir, setDir] = useState(1);
  const [posting, setPosting] = useState(false);
  // showLocationPicker controls the location picker modal
  const [showLocationPicker, setShowLocationPicker] = useState(false);
  const [form, setForm] = useState({
    title: '', skills: [], pay: '', description: '',
    district: profile?.district || '', taluk: profile?.taluk || '',
    location: '',
    // workLocation stores the full GPS/address object from LocationPicker
    // { lat, lng, address, mapsUrl }
    workLocation: null,
    date: '', time: '', duration: '', instructions: '',
  });

  const set = (k, v) => setForm(f=>({...f,[k]:v}));
  const toggleSkill = s => setForm(f=>({ ...f, skills: f.skills.includes(s)?f.skills.filter(x=>x!==s):[...f.skills,s] }));

  function goNext() {
    if (step === 0 && !form.title) { toast('Please enter a job title', 'error'); return; }
    if (step === 1 && !form.district) { toast('Please select a district', 'error'); return; }
    setDir(1); setStep(s=>s+1);
  }
  function goBack() { setDir(-1); setStep(s=>s-1); }

  async function submit() {
    if (!form.date) { toast('Please select a date', 'error'); return; }
    setPosting(true);
    try {
      await addDoc(collection(db, 'jobs'), {
        ...form,
        hirerId:   user.uid,
        hirerName: profile?.name || user?.displayName || '',
        status:    'open',
        applicants: [],
        createdAt: serverTimestamp(),
      });
      toast('✅ Job posted successfully!', 'success');
      navigate('/hirer-dashboard');
    } catch(e) { toast(e.message, 'error'); }
    setPosting(false);
  }

  return (
    <div style={{minHeight:'100vh',background:'var(--paper)'}}>
      <Navbar />
      <div style={{maxWidth:560,margin:'36px auto',padding:'0 20px'}}>
        {/* Progress */}
        <div style={{display:'flex',alignItems:'center',gap:0,marginBottom:32}}>
          {STEPS.map((s,i) => (
            <div key={s} style={{display:'flex',alignItems:'center',flex:1}}>
              <div style={{display:'flex',flexDirection:'column',alignItems:'center',gap:4}}>
                <div style={{
                  width:36,height:36,borderRadius:'50%',
                  background:i<=step?'var(--saffron)':'var(--paper2)',
                  color:i<=step?'#fff':'var(--muted)',
                  display:'flex',alignItems:'center',justifyContent:'center',
                  fontSize:'0.85rem',fontWeight:700,
                  transition:'all 0.3s',
                  boxShadow:i===step?'0 0 0 4px rgba(232,89,12,0.2)':'none',
                }}>{i < step ? '✓' : i+1}</div>
                <span style={{fontSize:'0.72rem',color:i<=step?'var(--saffron)':'var(--muted)',fontWeight:i===step?700:400,whiteSpace:'nowrap'}}>{s}</span>
              </div>
              {i < STEPS.length-1 && (
                <div style={{flex:1,height:2,background:i<step?'var(--saffron)':'var(--border)',transition:'background 0.3s',margin:'0 8px',marginBottom:20}}/>
              )}
            </div>
          ))}
        </div>

        <div className="card" style={{overflow:'hidden',position:'relative',minHeight:360}}>
          <AnimatePresence custom={dir} mode="wait">
            <motion.div key={step} custom={dir} variants={slideVariants} initial="enter" animate="center" exit="exit"
              transition={{duration:0.3,ease:[0.4,0,0.2,1]}}>

              {/* STEP 0: What */}
              {step === 0 && (
                <div>
                  <h3 style={{marginBottom:4}}>What do you need? 📋</h3>
                  <p style={{marginBottom:20,fontSize:'0.85rem'}}>Describe the job you want done</p>
                  <div style={{display:'flex',flexDirection:'column',gap:16}}>
                    <div className="form-group">
                      <label className="form-label">Job Title *</label>
                      <input className="form-input" value={form.title} onChange={e=>set('title',e.target.value)} placeholder="e.g. Painter needed, House wiring work…" />
                    </div>
                    <div className="form-group">
                      <label className="form-label">Skills Required</label>
                      <div style={{display:'flex',gap:8,flexWrap:'wrap'}}>
                        {SKILLS.map(s=>(
                          <button key={s} className={`pill ${form.skills.includes(s)?'active':''}`} onClick={()=>toggleSkill(s)}>{s}</button>
                        ))}
                      </div>
                    </div>
                    <div className="form-group">
                      <label className="form-label">Daily Pay (₹)</label>
                      <input className="form-input" type="number" value={form.pay} onChange={e=>set('pay',e.target.value)} placeholder="e.g. 600" />
                    </div>
                    <div className="form-group">
                      <label className="form-label">Description</label>
                      <textarea className="form-textarea" value={form.description} onChange={e=>set('description',e.target.value)} placeholder="Describe the work in detail…" rows={3}/>
                    </div>
                  </div>
                </div>
              )}

              {/* STEP 1: Where */}
              {step === 1 && (
                <div>
                  <h3 style={{marginBottom:4}}>Where is the job? 📍</h3>
                  <p style={{marginBottom:20,fontSize:'0.85rem'}}>Set the location for this job</p>
                  <div style={{display:'flex',flexDirection:'column',gap:16}}>
                    <div className="form-group">
                      <label className="form-label">District *</label>
                      {/* Single atomic setState — both district + taluk reset together */}
                      <select className="form-select" value={form.district}
                        onChange={e => setForm(f => ({ ...f, district: e.target.value, taluk: '' }))}
                      >
                        <option value="">Select District</option>
                        {KARNATAKA_DISTRICTS.map(d => (
                          <option key={d.en} value={d.en}>{d.en}</option>
                        ))}
                      </select>
                    </div>
                    <div className="form-group">
                      <label className="form-label">Taluk *</label>
                      {/* Dropdown updates when district changes */}
                      <select className="form-select" value={form.taluk}
                        onChange={e => setForm(f => ({ ...f, taluk: e.target.value }))}
                        disabled={!form.district}
                      >
                        <option value="">
                          {form.district ? '— Select Taluk —' : '— Select District First —'}
                        </option>
                        {(KARNATAKA_TALUKS[form.district] || []).map(t => (
                          <option key={t.en} value={t.en}>{t.en}</option>
                        ))}
                      </select>
                    </div>
                    <div className="form-group">
                      <label className="form-label">Full Address / Landmark</label>
                      <textarea className="form-textarea" value={form.location} onChange={e=>set('location',e.target.value)} placeholder="Enter full address or landmark…" rows={2}/>
                    </div>
                    {/* Location Picker Button / Display */}
                    <div style={{ marginTop: 8 }}>
                      {form.workLocation ? (
                        <div style={{
                          background: 'var(--paper2)', border: '1px solid var(--border)',
                          borderRadius: 12, padding: '12px 14px', position: 'relative'
                        }}>
                          <div style={{ fontWeight: 600, fontSize: '0.85rem', marginBottom: 4 }}>
                            📍 Specific Work Location
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
                            }}>Change</button>
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
                          📍 Add Specific Work Location (Optional)
                        </button>
                      )}
                    </div>
                  </div>
                </div>
              )}

              {/* STEP 2: When */}
              {step === 2 && (
                <div>
                  <h3 style={{marginBottom:4}}>When do you need it? 📅</h3>
                  <p style={{marginBottom:20,fontSize:'0.85rem'}}>Set the schedule</p>
                  <div style={{display:'flex',flexDirection:'column',gap:16}}>
                    <div className="form-group">
                      <label className="form-label">Date *</label>
                      <input className="form-input" type="date" value={form.date} onChange={e=>set('date',e.target.value)} min={new Date().toISOString().split('T')[0]} />
                    </div>
                    <div className="form-group">
                      <label className="form-label">Time</label>
                      <input className="form-input" type="time" value={form.time} onChange={e=>set('time',e.target.value)} />
                    </div>
                    <div className="form-group">
                      <label className="form-label">Duration</label>
                      <select className="form-select" value={form.duration} onChange={e=>set('duration',e.target.value)}>
                        <option value="">Select duration</option>
                        <option>1 Day</option><option>2-3 Days</option>
                        <option>1 Week</option><option>2 Weeks</option>
                        <option>1 Month</option><option>Ongoing</option>
                      </select>
                    </div>
                    <div className="form-group">
                      <label className="form-label">Special Instructions</label>
                      <textarea className="form-textarea" value={form.instructions} onChange={e=>set('instructions',e.target.value)} placeholder="Any specific requirements…" rows={2}/>
                    </div>

                    {/* Summary */}
                    <div style={{background:'var(--paper)',borderRadius:12,padding:'12px 16px',border:'1px solid var(--border)'}}>
                      <div style={{fontWeight:700,marginBottom:8,fontSize:'0.88rem'}}>📋 Job Summary</div>
                      <div style={{fontSize:'0.8rem',color:'var(--muted)',display:'flex',flexDirection:'column',gap:4}}>
                        <span>🔧 {form.title}</span>
                        <span>📍 {form.district}{form.taluk?`, ${form.taluk}`:''}</span>
                        <span>💰 ₹{form.pay||'—'}/day</span>
                        <span>📅 {form.date||'—'} {form.time||''}</span>
                      </div>
                    </div>
                  </div>
                </div>
              )}
            </motion.div>
          </AnimatePresence>

          {/* Navigation buttons */}
          <div style={{display:'flex',gap:10,marginTop:24}}>
            {step > 0 && (
              <button onClick={goBack} className="btn btn-ghost" style={{flex:1}}>← Back</button>
            )}
            {step < STEPS.length-1 ? (
              <motion.button whileTap={{scale:0.97}} onClick={goNext} className="btn btn-primary" style={{flex:2}}>
                Continue →
              </motion.button>
            ) : (
              <motion.button whileTap={{scale:0.97}} onClick={submit} className="btn btn-secondary" style={{flex:2}} disabled={posting}>
                {posting ? '⏳ Posting…' : '📋 Post Job'}
              </motion.button>
            )}
          </div>
        </div>
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
