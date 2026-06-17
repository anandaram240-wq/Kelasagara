// src/pages/SetupProfile.jsx — Multi-step registration wizard (matches live app)
import { useState } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { doc, setDoc, serverTimestamp } from 'firebase/firestore';
import { motion, AnimatePresence } from 'framer-motion';
import { db } from '../firebase';
import { useAuthStore } from '../store/authStore';
import { useToast } from '../components/Toast';
import {
  KARNATAKA_DISTRICTS,
  KARNATAKA_TALUKS,
  TRADES,
  EXPERIENCE_OPTIONS,
} from '../data/karnataka';

/* ───────── i18n strings ───────── */
const T = {
  en: {
    step1Title: '👤 Basic Info',       step1Sub: 'Tell us a bit about yourself',
    step2Title: '📍 Your Location',    step2Sub: 'Select your district and taluk in Karnataka',
    step3Title: '🛠 Work Details',     step3Sub: 'Your skills and experience',
    step4Title: '🧤 Skills & Tools',  step4Sub: 'Add all your skills so hirers can find you',
    step5Title: '✅ Review Profile',   step5Sub: 'Confirm your details before saving',
    name: 'Display Name', namePh: 'Your full name',
    phone: 'Phone Number *', phonePh: '10-digit mobile number',
    whatsapp: 'WhatsApp Number (optional)', whatsappPh: 'If different from phone',
    district: 'District *', selectDistrict: '— Select District —',
    taluk: 'Taluk *', selectTalukFirst: '— Select District First —', selectTaluk: '— Select Taluk —',
    village: 'Village / Town', villagePh: 'e.g. Hunsur, Sargur',
    role: 'I am a *',
    worker: '👷 Worker (I look for work)',
    hirer: '🏗️ Hirer (I hire workers)',
    trade: 'Primary Trade / Skill *', selectTrade: '— Select Trade —',
    experience: 'Experience *', selectExp: '— Select —',
    dailyRate: 'Daily Rate (₹) *', dailyRatePh: 'e.g. 500, 800, 1200',
    skillInput: 'Type a skill e.g. Mason, Tiling…',
    quickAdd: 'Quick add:',
    add: 'Add',
    back: '← Back',
    nextLocation: 'Next → Location →',
    nextWork: 'Next → Work Details →',
    nextSkills: 'Next → Skills →',
    reviewProfile: 'Review Profile →',
    saveProfile: '🚀 Save & Go to Dashboard',
    edit: '← Edit',
    saving: '⏳ Saving…',
    nameLabel: '👤 Name:', phoneLabel: '📱 Phone:', districtLabel: '📍 District:',
    talukLabel: '🏘 Taluk:', tradeLabel: '🛠 Trade:', expLabel: '📅 Experience:',
    rateLabel: '💰 Daily Rate:', skillsLabel: '🧤 Skills:', roleLabel: '📋 Role:',
    noneAdded: 'None added',
  },
  kn: {
    step1Title: '👤 ಮೂಲ ಮಾಹಿತಿ',        step1Sub: 'ನಿಮ್ಮ ಬಗ್ಗೆ ಸ್ವಲ್ಪ ಹೇಳಿ',
    step2Title: '📍 ನಿಮ್ಮ ಸ್ಥಳ',         step2Sub: 'ಕರ್ನಾಟಕದ ಜಿಲ್ಲೆ ಮತ್ತು ತಾಲ್ಲೂಕು ಆಯ್ಕೆ ಮಾಡಿ',
    step3Title: '🛠 ಕೆಲಸದ ವಿವರ',        step3Sub: 'ನಿಮ್ಮ ಕೌಶಲ್ಯ ಮತ್ತು ಅನುಭವ',
    step4Title: '🧤 ಕೌಶಲ್ಯ & ಸಾಧನ',     step4Sub: 'ಎಲ್ಲ ಕೌಶಲ್ಯಗಳನ್ನು ಸೇರಿಸಿ',
    step5Title: '✅ ಪ್ರೊಫೈಲ್ ಪರಿಶೀಲನೆ',  step5Sub: 'ಉಳಿಸುವ ಮೊದಲು ವಿವರಗಳನ್ನು ಖಚಿತಪಡಿಸಿ',
    name: 'ಪ್ರದರ್ಶನ ಹೆಸರು', namePh: 'ನಿಮ್ಮ ಪೂರ್ಣ ಹೆಸರು',
    phone: 'ಫೋನ್ ಸಂಖ್ಯೆ *', phonePh: '10-ಅಂಕಿ ಮೊಬೈಲ್ ಸಂಖ್ಯೆ',
    whatsapp: 'ವಾಟ್ಸ್ ಆ್ಯಪ್ ಸಂಖ್ಯೆ (ಐಚ್ಛಿಕ)', whatsappPh: 'ಫೋನ್‌ಗಿಂತ ಭಿನ್ನವಾಗಿದ್ದರೆ',
    district: 'ಜಿಲ್ಲೆ *', selectDistrict: '— ಜಿಲ್ಲೆ ಆಯ್ಕೆ ಮಾಡಿ —',
    taluk: 'ತಾಲ್ಲೂಕು *', selectTalukFirst: '— ಮೊದಲು ಜಿಲ್ಲೆ ಆಯ್ಕೆ ಮಾಡಿ —', selectTaluk: '— ತಾಲ್ಲೂಕು ಆಯ್ಕೆ ಮಾಡಿ —',
    village: 'ಗ್ರಾಮ / ಪಟ್ಟಣ', villagePh: 'ಉದಾ: ಹುಣಸೂರು, ಸಾಗರ',
    role: 'ನಾನು *',
    worker: '👷 ಕೆಲಸಗಾರ (ಕೆಲಸ ಹುಡುಕುತ್ತೇನೆ)',
    hirer: '🏗️ ನೇಮಕಗಾರ (ಕೆಲಸಗಾರರನ್ನು ಬಾಡಿಗೆ ಮಾಡುತ್ತೇನೆ)',
    trade: 'ಪ್ರಾಥಮಿಕ ಕೌಶಲ್ಯ *', selectTrade: '— ಕೌಶಲ್ಯ ಆಯ್ಕೆ ಮಾಡಿ —',
    experience: 'ಅನುಭವ *', selectExp: '— ಆಯ್ಕೆ ಮಾಡಿ —',
    dailyRate: 'ದಿನದ ವೇತನ (₹) *', dailyRatePh: 'ಉದಾ: 500, 800, 1200',
    skillInput: 'ಕೌಶಲ್ಯ ಟೈಪ್ ಮಾಡಿ ಉದಾ: ಮೇಸ್ತ್ರಿ, ಟೈಲಿಂಗ್…',
    quickAdd: 'ತ್ವರಿತ ಸೇರ್ಪಡೆ:',
    add: 'ಸೇರಿಸಿ',
    back: '← ಹಿಂದೆ',
    nextLocation: 'ಮುಂದೆ → ಸ್ಥಳ →',
    nextWork: 'ಮುಂದೆ → ಕೆಲಸದ ವಿವರ →',
    nextSkills: 'ಮುಂದೆ → ಕೌಶಲ್ಯ →',
    reviewProfile: 'ಪ್ರೊಫೈಲ್ ಪರಿಶೀಲಿಸಿ →',
    saveProfile: '🚀 ಉಳಿಸಿ ಮತ್ತು ಡ್ಯಾಶ್‌ಬೋರ್ಡ್‌ಗೆ ಹೋಗಿ',
    edit: '← ಸಂಪಾದಿಸಿ',
    saving: '⏳ ಉಳಿಸಲಾಗುತ್ತಿದೆ…',
    nameLabel: '👤 ಹೆಸರು:', phoneLabel: '📱 ಫೋನ್:', districtLabel: '📍 ಜಿಲ್ಲೆ:',
    talukLabel: '🏘 ತಾಲ್ಲೂಕು:', tradeLabel: '🛠 ಕೌಶಲ್ಯ:', expLabel: '📅 ಅನುಭವ:',
    rateLabel: '💰 ದಿನದ ವೇತನ:', skillsLabel: '🧤 ಕೌಶಲ್ಯಗಳು:', roleLabel: '📋 ಪಾತ್ರ:',
    noneAdded: 'ಯಾವುದೂ ಇಲ್ಲ',
  },
};

const QUICK_SKILLS = ['Mason','Plumber','Electrician','Carpenter','Painter','Driver','Cook','Welder','Tiling','Helper'];

/* ───────── Progress dots ───────── */
function StepDots({ step, total }) {
  const colors = ['#1B6B45','#E8590C','#E8590C'];
  return (
    <div style={{ display:'flex', gap:8, justifyContent:'center', marginBottom:20 }}>
      {Array.from({ length: total }, (_, i) => (
        <div key={i} style={{
          width: i === step ? 28 : 10, height: 10, borderRadius: 5,
          background: i < step ? '#22C55E' : i === step ? 'var(--saffron)' : '#D1D5DB',
          transition: 'all 0.3s ease',
        }} />
      ))}
    </div>
  );
}

/* ───────── Card wrapper ───────── */
const cardAnim = {
  initial: { opacity: 0, x: 40 },
  animate: { opacity: 1, x: 0 },
  exit:    { opacity: 0, x: -40 },
};

export default function SetupProfile() {
  const { user, setProfile } = useAuthStore();
  const navigate = useNavigate();
  const location = useLocation();
  const toast = useToast();
  const [lang, setLang] = useState('en');
  const t = T[lang];

  const [step, setStep] = useState(0);
  const [saving, setSaving] = useState(false);

  // Form state — pre-fill role from Login page hint if provided
  const roleHint = location.state?.roleHint || '';
  const [form, setForm] = useState({
    name:        user?.displayName || '',
    phone:       '',
    whatsapp:    '',
    role:        roleHint,   // pre-selected if user chose Worker/Hirer on Login
    district:    '',
    taluk:       '',
    village:     '',
    trade:       '',
    experience:  '',
    dailyRate:   '',
    skills:      [],
  });

  const [skillInput, setSkillInput] = useState('');

  const upd = (k, v) => setForm(f => ({ ...f, [k]: v }));

  // Steps: 0=Basic, 1=Location, 2=WorkDetails(worker only), 3=Skills(worker only), 4=Review
  const totalSteps = form.role === 'worker' ? 5 : 3;
  const steps = form.role === 'worker'
    ? ['basic', 'location', 'work', 'skills', 'review']
    : ['basic', 'location', 'review'];
  const currentStep = steps[step] || 'basic';

  // Available taluks for selected district
  const taluks = form.district ? (KARNATAKA_TALUKS[form.district] || []) : [];

  function addSkill(s) {
    const sk = s.trim();
    if (sk && !form.skills.includes(sk)) upd('skills', [...form.skills, sk]);
    setSkillInput('');
  }

  function next() {
    // Validate current step
    if (currentStep === 'basic') {
      if (!form.name.trim()) { toast(lang === 'kn' ? 'ಹೆಸರು ಅಗತ್ಯ' : 'Name is required', 'error'); return; }
      if (!form.phone.trim() || form.phone.replace(/\D/g, '').length !== 10) {
        toast(lang === 'kn' ? '10 ಅಂಕಿ ಫೋನ್ ಸಂಖ್ಯೆ ನಮೂದಿಸಿ' : 'Enter a valid 10-digit phone number', 'error'); return;
      }
      if (!form.role) { toast(lang === 'kn' ? 'ಪಾತ್ರ ಆಯ್ಕೆ ಮಾಡಿ' : 'Please select Worker or Hirer', 'error'); return; }
    }
    if (currentStep === 'location') {
      if (!form.district) { toast(lang === 'kn' ? 'ಜಿಲ್ಲೆ ಆಯ್ಕೆ ಮಾಡಿ' : 'Please select a District', 'error'); return; }
      if (!form.taluk) { toast(lang === 'kn' ? 'ತಾಲ್ಲೂಕು ಆಯ್ಕೆ ಮಾಡಿ' : 'Please select a Taluk', 'error'); return; }
    }
    if (currentStep === 'work') {
      if (!form.trade) { toast(lang === 'kn' ? 'ಕೌಶಲ್ಯ ಆಯ್ಕೆ ಮಾಡಿ' : 'Please select your primary trade', 'error'); return; }
      if (!form.experience) { toast(lang === 'kn' ? 'ಅನುಭವ ಆಯ್ಕೆ ಮಾಡಿ' : 'Please select your experience', 'error'); return; }
      if (!form.dailyRate) { toast(lang === 'kn' ? 'ದಿನದ ವೇತನ ನಮೂದಿಸಿ' : 'Please enter your daily rate', 'error'); return; }
    }
    setStep(s => s + 1);
  }

  async function save() {
    setSaving(true);
    try {
      const data = {
        uid:            user.uid,
        email:          user.email,
        name:           form.name.trim(),
        phone:          form.phone.trim(),
        whatsapp:       form.whatsapp.trim() || form.phone.trim(),
        role:           form.role,
        district:       form.district,
        taluk:          form.taluk,
        village:        form.village.trim(),
        trade:          form.trade,
        experience:     form.experience,
        dailyRate:      parseInt(form.dailyRate) || 0,
        skills:         form.skills.length ? form.skills : [form.trade].filter(Boolean),
        photo:          user.photoURL || '',
        profileComplete: true,
        isApproved:     true,
        status:         'active',
        rating:         0,
        createdAt:      serverTimestamp(),
      };
      await setDoc(doc(db, 'users', user.uid), data);
      setProfile(data);
      toast(lang === 'kn' ? 'ಪ್ರೊಫೈಲ್ ಉಳಿಸಲಾಗಿದೆ! ಸ್ವಾಗತ 🎉' : 'Profile saved! Welcome to KelasaGaara 🎉', 'success');
      navigate(form.role === 'worker' ? '/worker-dashboard' : '/hirer-dashboard');
    } catch (e) { toast(e.message, 'error'); }
    setSaving(false);
  }

  // District label in selected language
  const districtLabel = form.district
    ? (KARNATAKA_DISTRICTS.find(d => d.en === form.district)?.[lang] || form.district)
    : '';
  const talukLabel = form.taluk
    ? (taluks.find(t => t.en === form.taluk)?.[lang] || form.taluk)
    : '';
  const tradeLabel = form.trade
    ? (TRADES.find(tr => tr.en === form.trade)?.[lang] || form.trade)
    : '';
  const expLabel = form.experience
    ? (EXPERIENCE_OPTIONS.find(e => e.en === form.experience)?.[lang] || form.experience)
    : '';

  return (
    <div style={{
      minHeight: '100vh', background: '#F5EFE4',
      display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
      padding: '20px',
    }}>
      {/* Language toggle — top right */}
      <div style={{ position:'fixed', top:16, right:16, zIndex:50 }}>
        <div className="lang-toggle">
          <button className={`lang-btn ${lang==='en'?'active':''}`} onClick={()=>setLang('en')}>English</button>
          <button className={`lang-btn ${lang==='kn'?'active':''}`} onClick={()=>setLang('kn')}>ಕನ್ನಡ</button>
        </div>
      </div>

      {/* Card */}
      <div style={{
        width: '100%', maxWidth: 420,
        background: '#FFFFFF', borderRadius: 18,
        boxShadow: '0 8px 40px rgba(0,0,0,0.12)',
        overflow: 'hidden',
      }}>
        {/* Tricolor progress bar */}
        <div style={{ height: 5, display:'flex' }}>
          <div style={{ flex:1, background:'#138808' }} />
          <div style={{ flex:1, background:'#FFFFFF', borderTop:'1px solid #eee' }} />
          <div style={{
            flex: step / (totalSteps - 1),
            background: 'var(--saffron)', transition:'flex 0.4s ease',
            minWidth: step > 0 ? 8 : 0,
          }} />
          <div style={{ flex: 1 - step / (totalSteps - 1), background:'#eee' }} />
        </div>

        <div style={{ padding:'28px 30px 32px' }}>
          {/* Step dots */}
          <StepDots step={step} total={totalSteps} />

          <AnimatePresence mode="wait">
            <motion.div key={currentStep} variants={cardAnim} initial="initial" animate="animate" exit="exit" transition={{ duration:0.22 }}>

              {/* ── STEP 0: Basic Info ── */}
              {currentStep === 'basic' && (
                <div>
                  <h3 style={{marginBottom:4}}>{t.step1Title}</h3>
                  <p style={{fontSize:'0.82rem',marginBottom:20}}>{t.step1Sub}</p>

                  {/* Role selector */}
                  <div className="form-group" style={{marginBottom:14}}>
                    <label className="form-label">{t.role}</label>
                    <div style={{display:'flex',gap:10}}>
                      {(['worker','hirer']).map(r => (
                        <button key={r} onClick={()=>upd('role',r)} style={{
                          flex:1, padding:'11px 10px', borderRadius:10, cursor:'pointer',
                          fontFamily:"'DM Sans',sans-serif", fontWeight:600, fontSize:'0.82rem',
                          border:`2px solid ${form.role===r?'var(--saffron)':'var(--border)'}`,
                          background: form.role===r?'var(--saffron-light)':'#fff',
                          color: form.role===r?'var(--saffron)':'var(--muted)',
                          transition:'all 0.2s',
                        }}>
                          {t[r]}
                        </button>
                      ))}
                    </div>
                  </div>

                  <div className="form-group" style={{marginBottom:12}}>
                    <label className="form-label">{t.name} *</label>
                    <input className="form-input" value={form.name} onChange={e=>upd('name',e.target.value)} placeholder={t.namePh}/>
                  </div>
                  <div className="form-group" style={{marginBottom:12}}>
                    <label className="form-label">{t.phone}</label>
                    <input className="form-input" type="tel" maxLength={10} value={form.phone} onChange={e=>upd('phone',e.target.value.replace(/\D/g,''))} placeholder={t.phonePh}/>
                  </div>
                  <div className="form-group" style={{marginBottom:22}}>
                    <label className="form-label">{t.whatsapp}</label>
                    <input className="form-input" type="tel" maxLength={10} value={form.whatsapp} onChange={e=>upd('whatsapp',e.target.value.replace(/\D/g,''))} placeholder={t.whatsappPh}/>
                  </div>

                  <button className="btn btn-primary" onClick={next} style={{width:'100%',padding:'13px'}}>
                    {t.nextLocation}
                  </button>
                </div>
              )}

              {/* ── STEP 1: Location ── */}
              {currentStep === 'location' && (
                <div>
                  <h3 style={{marginBottom:4}}>{t.step2Title}</h3>
                  <p style={{fontSize:'0.82rem',marginBottom:20}}>{t.step2Sub}</p>

                  <div className="form-group" style={{marginBottom:12}}>
                    <label className="form-label">{t.district}</label>
                    <select className="form-select" value={form.district}
                      onChange={e => setForm(f => ({ ...f, district: e.target.value, taluk: '' }))}
                    >
                      <option value="">{t.selectDistrict}</option>
                      {KARNATAKA_DISTRICTS.map(d => (
                        <option key={d.en} value={d.en}>{d[lang]} {lang==='kn'?`(${d.en})`:''}</option>
                      ))}
                    </select>
                  </div>

                  <div className="form-group" style={{marginBottom:12}}>
                    <label className="form-label">{t.taluk}</label>
                    <select className="form-select" value={form.taluk} onChange={e=>upd('taluk',e.target.value)} disabled={!form.district}>
                      <option value="">{form.district ? t.selectTaluk : t.selectTalukFirst}</option>
                      {taluks.map(tk => (
                        <option key={tk.en} value={tk.en}>{tk[lang]} {lang==='kn'?`(${tk.en})`:''}</option>
                      ))}
                    </select>
                  </div>

                  <div className="form-group" style={{marginBottom:22}}>
                    <label className="form-label">{t.village}</label>
                    <input className="form-input" value={form.village} onChange={e=>upd('village',e.target.value)} placeholder={t.villagePh}/>
                  </div>

                  <div style={{display:'flex',gap:10}}>
                    <button className="btn btn-ghost" onClick={()=>setStep(s=>s-1)} style={{flex:1}}>{t.back}</button>
                    <button className="btn btn-primary" onClick={next} style={{flex:2}}>
                      {form.role==='worker' ? t.nextWork : t.reviewProfile}
                    </button>
                  </div>
                </div>
              )}

              {/* ── STEP 2: Work Details (worker only) ── */}
              {currentStep === 'work' && (
                <div>
                  <h3 style={{marginBottom:4}}>{t.step3Title}</h3>
                  <p style={{fontSize:'0.82rem',marginBottom:20}}>{t.step3Sub}</p>

                  <div className="form-group" style={{marginBottom:12}}>
                    <label className="form-label">{t.trade}</label>
                    <select className="form-select" value={form.trade} onChange={e=>upd('trade',e.target.value)}>
                      <option value="">{t.selectTrade}</option>
                      {TRADES.map(tr => (
                        <option key={tr.en} value={tr.en}>{tr[lang]} {lang==='kn'?`(${tr.en})`:''}</option>
                      ))}
                    </select>
                  </div>

                  <div className="form-group" style={{marginBottom:12}}>
                    <label className="form-label">{t.experience}</label>
                    <select className="form-select" value={form.experience} onChange={e=>upd('experience',e.target.value)}>
                      <option value="">{t.selectExp}</option>
                      {EXPERIENCE_OPTIONS.map(ex => (
                        <option key={ex.en} value={ex.en}>{ex[lang]}</option>
                      ))}
                    </select>
                  </div>

                  <div className="form-group" style={{marginBottom:22}}>
                    <label className="form-label">{t.dailyRate}</label>
                    <input className="form-input" type="number" value={form.dailyRate} onChange={e=>upd('dailyRate',e.target.value)} placeholder={t.dailyRatePh}/>
                  </div>

                  <div style={{display:'flex',gap:10}}>
                    <button className="btn btn-ghost" onClick={()=>setStep(s=>s-1)} style={{flex:1}}>{t.back}</button>
                    <button className="btn btn-primary" onClick={next} style={{flex:2}}>{t.nextSkills}</button>
                  </div>
                </div>
              )}

              {/* ── STEP 3: Skills (worker only) ── */}
              {currentStep === 'skills' && (
                <div>
                  <h3 style={{marginBottom:4}}>{t.step4Title}</h3>
                  <p style={{fontSize:'0.82rem',marginBottom:20}}>{t.step4Sub}</p>

                  {/* Added skills */}
                  {form.skills.length > 0 && (
                    <div style={{display:'flex',gap:7,flexWrap:'wrap',marginBottom:14}}>
                      {form.skills.map(sk=>(
                        <span key={sk} style={{
                          display:'inline-flex',alignItems:'center',gap:5,
                          padding:'5px 11px',background:'var(--saffron-light)',color:'var(--saffron)',
                          border:'1px solid var(--saffron)',borderRadius:20,fontSize:'0.8rem',fontWeight:600,
                        }}>
                          {sk}
                          <button onClick={()=>upd('skills',form.skills.filter(x=>x!==sk))} style={{background:'none',border:'none',cursor:'pointer',color:'var(--saffron)',fontWeight:700,fontSize:'1rem',padding:0,lineHeight:1}}>×</button>
                        </span>
                      ))}
                    </div>
                  )}

                  {/* Skill input */}
                  <div style={{display:'flex',gap:8,marginBottom:14}}>
                    <input className="form-input" value={skillInput} onChange={e=>setSkillInput(e.target.value)}
                      onKeyDown={e=>e.key==='Enter'&&addSkill(skillInput)}
                      placeholder={t.skillInput} style={{flex:1}}/>
                    <button className="btn btn-primary btn-sm" onClick={()=>addSkill(skillInput)} style={{flexShrink:0}}>
                      {t.add}
                    </button>
                  </div>

                  {/* Quick add chips */}
                  <div style={{marginBottom:20}}>
                    <div style={{fontSize:'0.78rem',color:'var(--muted)',marginBottom:8}}>{t.quickAdd}</div>
                    <div style={{display:'flex',gap:7,flexWrap:'wrap'}}>
                      {QUICK_SKILLS.filter(s=>!form.skills.includes(s)).map(s=>(
                        <button key={s} onClick={()=>addSkill(s)} style={{
                          padding:'5px 11px',background:'#fff',border:'1.5px solid var(--border)',
                          borderRadius:20,fontSize:'0.78rem',cursor:'pointer',color:'var(--muted)',
                          fontFamily:"'DM Sans',sans-serif",transition:'all 0.18s',
                        }}
                          onMouseEnter={e=>{e.currentTarget.style.borderColor='var(--saffron)';e.currentTarget.style.color='var(--saffron)';}}
                          onMouseLeave={e=>{e.currentTarget.style.borderColor='var(--border)';e.currentTarget.style.color='var(--muted)';}}
                        >
                          + {s}
                        </button>
                      ))}
                    </div>
                  </div>

                  <div style={{display:'flex',gap:10}}>
                    <button className="btn btn-ghost" onClick={()=>setStep(s=>s-1)} style={{flex:1}}>{t.back}</button>
                    <button className="btn btn-primary" onClick={next} style={{flex:2}}>{t.reviewProfile}</button>
                  </div>
                </div>
              )}

              {/* ── STEP 4/2: Review ── */}
              {currentStep === 'review' && (
                <div>
                  <h3 style={{marginBottom:4}}>{t.step5Title}</h3>
                  <p style={{fontSize:'0.82rem',marginBottom:20}}>{t.step5Sub}</p>

                  <div style={{
                    background:'var(--paper)', borderRadius:12,
                    padding:'18px 20px', marginBottom:20,
                    display:'flex', flexDirection:'column', gap:10, fontSize:'0.88rem',
                  }}>
                    {[
                      [t.nameLabel,     form.name],
                      [t.phoneLabel,    form.phone],
                      [t.districtLabel, districtLabel],
                      [t.talukLabel,    talukLabel || form.taluk],
                      ...(form.role === 'worker' ? [
                        [t.tradeLabel,  tradeLabel || form.trade],
                        [t.expLabel,    expLabel || form.experience],
                        [t.rateLabel,   form.dailyRate ? `₹${form.dailyRate}` : '—'],
                        [t.skillsLabel, form.skills.join(', ') || t.noneAdded],
                      ] : []),
                      [t.roleLabel,     form.role === 'worker' ? '👷 Worker' : '🏗️ Hirer'],
                    ].map(([label, val]) => val ? (
                      <div key={label} style={{display:'flex',gap:10,alignItems:'flex-start'}}>
                        <span style={{color:'var(--muted)',minWidth:120,flexShrink:0,fontSize:'0.82rem'}}>{label}</span>
                        <span style={{color:'var(--ink)',fontWeight:500}}>{val}</span>
                      </div>
                    ) : null)}
                  </div>

                  <div style={{display:'flex',gap:10}}>
                    <button className="btn btn-ghost" onClick={()=>setStep(s=>s-1)} style={{flex:1}}>{t.edit}</button>
                    <motion.button className="btn btn-primary" onClick={save} disabled={saving} whileTap={{scale:0.97}} style={{flex:2,padding:'13px'}}>
                      {saving ? t.saving : t.saveProfile}
                    </motion.button>
                  </div>
                </div>
              )}

            </motion.div>
          </AnimatePresence>
        </div>
      </div>

      {/* Branding below card */}
      <div style={{marginTop:20,textAlign:'center'}}>
        <div style={{fontFamily:"'Baloo Tamma 2',cursive",fontWeight:700,color:'var(--ink)',fontSize:'1rem'}}>
          Kelasa<span style={{color:'var(--saffron)'}}>Gaara</span>
        </div>
        <div style={{fontSize:'0.72rem',color:'var(--muted)'}}>ಕೆಲಸಗಾರ — Karnataka's Worker Platform</div>
      </div>
    </div>
  );
}
