// src/pages/FindJobs.jsx — Worker job feed (Browse open jobs posted by hirers)
import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { collection, getDocs, doc, updateDoc, arrayUnion, serverTimestamp } from 'firebase/firestore';
import { motion, AnimatePresence } from 'framer-motion';
import { db } from '../firebase';
import { useAuthStore } from '../store/authStore';
import { useToast } from '../components/Toast';
import Navbar from '../components/Navbar';

const STATUS_COLORS = { open: '#16A34A', closed: '#DC2626', filled: '#2563EB' };

export default function FindJobs() {
  const { user, profile } = useAuthStore();
  const toast = useToast();
  const [jobs, setJobs] = useState([]);
  const [loading, setLoading] = useState(true);
  const [applying, setApplying] = useState({});
  const [filter, setFilter] = useState({ district:'', skill:'' });
  const [search, setSearch] = useState('');

  useEffect(() => { loadJobs(); }, []);

  async function loadJobs() {
    setLoading(true);
    try {
      const snap = await getDocs(collection(db, 'jobs'));
      const list = snap.docs.map(d=>({id:d.id,...d.data()})).filter(j=>j.status !== 'closed');
      setJobs(list.sort((a,z)=>(z.createdAt?.seconds||0)-(a.createdAt?.seconds||0)));
    } catch(e) { console.error(e); }
    setLoading(false);
  }

  async function applyToJob(jobId) {
    if (!user) { toast('Please login to apply', 'error'); return; }
    if (!profile?.role === 'worker') { toast('Only workers can apply to jobs', 'error'); return; }
    setApplying(a=>({...a,[jobId]:true}));
    try {
      await updateDoc(doc(db,'jobs',jobId), {
        applicants: arrayUnion(user.uid),
        updatedAt: serverTimestamp(),
      });
      toast('✅ Applied successfully!', 'success');
      // Update local state
      setJobs(js=>js.map(j=>j.id===jobId?{...j,applicants:[...(j.applicants||[]),user.uid]}:j));
    } catch(e) { toast(e.message,'error'); }
    setApplying(a=>({...a,[jobId]:false}));
  }

  const filtered = jobs.filter(j => {
    if (filter.district && j.district !== filter.district) return false;
    if (filter.skill && !(j.skills||j.title||'').toLowerCase().includes(filter.skill.toLowerCase())) return false;
    if (search && !(j.title||'').toLowerCase().includes(search.toLowerCase()) && !(j.district||'').toLowerCase().includes(search.toLowerCase())) return false;
    return true;
  });

  return (
    <div style={{minHeight:'100vh',background:'var(--paper)'}}>
      <Navbar />
      <div style={{maxWidth:800,margin:'28px auto',padding:'0 20px'}}>
        <div style={{marginBottom:24}}>
          <h2 style={{marginBottom:4}}>📋 Find Jobs</h2>
          <p>Browse jobs posted by hirers in your area</p>
        </div>

        {/* Filters */}
        <div style={{display:'flex',gap:10,marginBottom:20,flexWrap:'wrap'}}>
          <input className="form-input" style={{flex:2,minWidth:200}} value={search}
            onChange={e=>setSearch(e.target.value)} placeholder="Search jobs…" />
          <input className="form-input" style={{flex:1,minWidth:150}} value={filter.district}
            onChange={e=>setFilter(f=>({...f,district:e.target.value}))} placeholder="Filter by district…" />
        </div>

        {loading ? (
          <div style={{display:'flex',justifyContent:'center',padding:60}}><div className="spinner"/></div>
        ) : filtered.length === 0 ? (
          <div className="card state-box">
            <p>No jobs posted yet in your area.</p>
            <p style={{marginTop:8,fontSize:'0.85rem'}}>Check back later or ask your network.</p>
          </div>
        ) : (
          <div style={{display:'flex',flexDirection:'column',gap:14}}>
            <AnimatePresence>
              {filtered.map((job, i) => {
                const hasApplied = (job.applicants||[]).includes(user?.uid);
                const applicantCount = (job.applicants||[]).length;

                return (
                  <motion.div
                    key={job.id}
                    className="card"
                    initial={{opacity:0,y:16}}
                    animate={{opacity:1,y:0}}
                    transition={{duration:0.25,delay:i*0.04}}
                    whileHover={{y:-2,boxShadow:'0 8px 28px rgba(0,0,0,0.1)'}}
                  >
                    <div style={{display:'flex',justifyContent:'space-between',alignItems:'flex-start',marginBottom:10}}>
                      <div>
                        <h3 style={{fontSize:'1rem',marginBottom:4}}>{job.title || 'Job Opening'}</h3>
                        <div style={{display:'flex',gap:8,flexWrap:'wrap'}}>
                          <span style={{fontSize:'0.75rem',color:'var(--muted)'}}>📍 {job.district}, {job.taluk||'Karnataka'}</span>
                          {job.pay && <span style={{fontSize:'0.75rem',color:'var(--jade)',fontWeight:600}}>₹{job.pay}/day</span>}
                          {job.duration && <span style={{fontSize:'0.75rem',color:'var(--muted)'}}>⏱ {job.duration}</span>}
                        </div>
                      </div>
                      <span style={{background:`${STATUS_COLORS[job.status]||'#9CA3AF'}15`,color:STATUS_COLORS[job.status]||'#9CA3AF',padding:'3px 10px',borderRadius:20,fontSize:'0.72rem',fontWeight:700,flexShrink:0}}>
                        {job.status || 'OPEN'}
                      </span>
                    </div>

                    {job.description && (
                      <p style={{fontSize:'0.83rem',color:'var(--muted)',marginBottom:12,lineHeight:1.5}}>{job.description}</p>
                    )}

                    {/* Specific Work Location with Maps Link */}
                    {job.workLocation && (
                      <div style={{
                        background: 'rgba(66,133,244,0.06)', border: '1px solid rgba(66,133,244,0.2)',
                        borderRadius: 8, padding: '8px 12px', marginBottom: 12,
                        display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 10
                      }}>
                        <div>
                          <div style={{fontSize:'0.75rem',fontWeight:700,color:'#4285F4',marginBottom:2}}>📍 Specific Location Added</div>
                          <div style={{fontSize:'0.72rem',color:'var(--muted)',overflow:'hidden',textOverflow:'ellipsis',display:'-webkit-box',WebkitLineClamp:2,WebkitBoxOrient:'vertical'}}>
                            {job.workLocation.address}
                          </div>
                        </div>
                        <a href={job.workLocation.mapsUrl} target="_blank" rel="noreferrer" style={{
                          background: '#4285F4', color: '#fff', fontSize: '0.7rem', fontWeight: 600,
                          padding: '4px 8px', borderRadius: 6, textDecoration: 'none', flexShrink: 0
                        }}>🗺 Maps</a>
                      </div>
                    )}

                    {job.skills && (
                      <div style={{display:'flex',gap:6,flexWrap:'wrap',marginBottom:12}}>
                        {(Array.isArray(job.skills) ? job.skills : [job.skills]).map(s=>(
                          <span key={s} style={{padding:'3px 10px',background:'var(--saffron-light)',color:'var(--saffron)',borderRadius:20,fontSize:'0.72rem',fontWeight:600}}>{s}</span>
                        ))}
                      </div>
                    )}

                    <div style={{display:'flex',alignItems:'center',justifyContent:'space-between'}}>
                      <span style={{fontSize:'0.75rem',color:'var(--muted)'}}>{applicantCount} applicant{applicantCount!==1?'s':''}</span>
                      {hasApplied ? (
                        <span style={{padding:'8px 20px',background:'var(--jade-light)',color:'var(--jade)',borderRadius:24,fontWeight:700,fontSize:'0.85rem'}}>✅ Applied</span>
                      ) : (
                        <motion.button
                          className="btn btn-primary"
                          style={{borderRadius:24}}
                          onClick={()=>applyToJob(job.id)}
                          disabled={applying[job.id]}
                          whileTap={{scale:0.96}}
                        >
                          {applying[job.id] ? '⏳ Applying…' : '⚡ Apply Now'}
                        </motion.button>
                      )}
                    </div>
                  </motion.div>
                );
              })}
            </AnimatePresence>
          </div>
        )}
      </div>
    </div>
  );
}
