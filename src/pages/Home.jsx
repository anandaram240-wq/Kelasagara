// src/pages/Home.jsx — Complete home page matching live app exactly
import { useState, useEffect, useCallback } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { collection, getDocs, query, where } from 'firebase/firestore';
import { ref, onValue } from 'firebase/database';
import { motion, AnimatePresence } from 'framer-motion';
import { db, rtdb } from '../firebase';
import { useAuthStore } from '../store/authStore';
import Navbar from '../components/Navbar';
import { KARNATAKA_DISTRICTS, KARNATAKA_TALUKS } from '../data/karnataka';
import { useToast } from '../components/Toast';


// ── Districts & Taluks — from karnataka.js (all 31 districts, full taluk lists) ──
const DISTRICTS = KARNATAKA_DISTRICTS.map(d => d.en); // English names for filter matching

const CATEGORIES_EN = ['All','Painter','Plumber','Electrician','Mason','Carpenter','Driver','Cook','Gardener','Security','Helper'];
const CATEGORIES_KN = ['ಎಲ್ಲ','ಪೇಂಟರ್','ಪ್ಲಂಬರ್','ಎಲೆಕ್ಟ್ರಿಷಿಯನ್','ಮೇಸ್ತ್ರಿ','ಮರಗೆಲಸ','ಡ್ರೈವರ್','ಅಡಿಗೆ','ತೋಟಗಾರ','ಸೆಕ್ಯುರಿಟಿ','ಸಹಾಯ'];
const CAT_ICONS = ['🌟','🎨','🔧','⚡','🏗️','🪚','🚗','🍳','🌳','🔒','🤝'];

const TICKER_ITEMS = [
  '★ Google Login — No Password',
  '★ 0% Commission',
  '★ Find Workers Instantly',
  '★ Post Jobs in 2 Minutes',
  '★ Secure Google Auth',
  '★ 31 Karnataka Districts',
  '★ Verified Workers Only',
  '★ Real-time Chat',
];

const PAGE_SIZE = 12;
const STATUS_COLORS = { PENDING:'#D97706', CONFIRMED:'#16A34A', DECLINED:'#DC2626', COMPLETED:'#2563EB' };

export default function Home() {
  const { user, role } = useAuthStore();
  const navigate = useNavigate();
  const toast = useToast();
  const [lang, setLang] = useState('en');

  const [workers, setWorkers]     = useState([]);
  const [filtered, setFiltered]   = useState([]);
  const [loading, setLoading]     = useState(true);
  const [onlineCount, setOnlineCount] = useState(0);
  const [jobsCount, setJobsCount] = useState(0);

  const [district, setDistrict]   = useState('');
  const [taluk, setTaluk]         = useState('');
  const [search, setSearch]       = useState('');
  const [category, setCategory]   = useState('All');
  const [sortBy, setSortBy]       = useState('');
  const [page, setPage]           = useState(1);

  useEffect(() => { loadData(); }, []);

  useEffect(() => {
    // Track online presence count
    const presRef = ref(rtdb, 'presence');
    const unsub = onValue(presRef, snap => {
      if (!snap.exists()) { setOnlineCount(0); return; }
      let cnt = 0;
      snap.forEach(c => { if (c.val()?.online) cnt++; });
      setOnlineCount(cnt);
    });
    return () => unsub();
  }, []);

  useEffect(() => { applyFilter(); }, [workers, district, taluk, search, category, sortBy]);

  async function loadData() {
    setLoading(true);
    try {
      const [wSnap, jSnap] = await Promise.all([
        getDocs(query(collection(db, 'users'), where('role', '==', 'worker'))),
        getDocs(collection(db, 'jobs')),
      ]);
      const list = wSnap.docs
        .map(d => ({ id: d.id, ...d.data() }))
        .filter(w => w.isApproved !== false && w.status !== 'inactive');
      setWorkers(list);
      setJobsCount(jSnap.size);
    } catch (e) { console.error(e); }
    setLoading(false);
  }

  function applyFilter() {
    let f = [...workers];
    if (district) f = f.filter(w => w.district === district);
    if (taluk)    f = f.filter(w => w.taluk === taluk);
    if (category !== 'All') {
      const catEN = CATEGORIES_EN[CATEGORIES_KN.indexOf(category)] || category;
      f = f.filter(w => (w.skills || []).some(s =>
        s.toLowerCase().includes(catEN.toLowerCase()) ||
        s.toLowerCase().includes(category.toLowerCase())
      ));
    }
    if (search) {
      const q = search.toLowerCase();
      f = f.filter(w =>
        (w.name || '').toLowerCase().includes(q) ||
        (w.skills || []).some(s => s.toLowerCase().includes(q)) ||
        (w.district || '').toLowerCase().includes(q)
      );
    }
    // Sort
    if (sortBy === 'rating')  f.sort((a, b) => (b.rating || 0) - (a.rating || 0));
    if (sortBy === 'price_up') f.sort((a, b) => (a.dailyRate || 0) - (b.dailyRate || 0));
    if (sortBy === 'price_dn') f.sort((a, b) => (b.dailyRate || 0) - (a.dailyRate || 0));
    if (sortBy === 'exp') f.sort((a, b) => parseExp(b.experience) - parseExp(a.experience));

    setFiltered(f);
    setPage(1);
  }

  function parseExp(e = '') {
    if (!e) return 0;
    const m = e.match(/(\d+)/);
    return m ? parseInt(m[1]) : 0;
  }

  // Near Me button - completely rebuilt to be highly robust and user-friendly
  async function nearMe() {
    if (!navigator.geolocation) {
      toast(lang === 'kn' ? 'ನಿಮ್ಮ ಬ್ರೌಸರ್‌ನಲ್ಲಿ ಜಿಪಿಎಸ್ ಬೆಂಬಲವಿಲ್ಲ' : 'GPS not supported by your browser', 'error');
      return;
    }
    
    toast(lang === 'kn' ? 'ನಿಮ್ಮ ಸ್ಥಳವನ್ನು ಪತ್ತೆ ಮಾಡಲಾಗುತ್ತಿದೆ...' : 'Detecting your location...', 'info');
    
    navigator.geolocation.getCurrentPosition(async pos => {
      const { latitude, longitude } = pos.coords;
      try {
        const res = await fetch(
          `https://nominatim.openstreetmap.org/reverse?format=json&lat=${latitude}&lon=${longitude}&zoom=10`,
          { headers: { 'Accept-Language': 'en' } }
        );
        const data = await res.json();
        const addr = data.address || {};
        
        // Compile all possible location strings retrieved from geocoding
        const searchTerms = [
          addr.county,
          addr.state_district,
          addr.city,
          addr.town,
          addr.suburb,
          addr.municipality,
          addr.district,
          addr.village,
          addr.neighbourhood
        ].filter(Boolean).map(s => s.toLowerCase());

        // Alias mapping for common name variations / spelling differences in Karnataka
        const aliasMap = {
          'bangalore': 'Bengaluru Urban',
          'bengaluru': 'Bengaluru Urban',
          'bangalore urban': 'Bengaluru Urban',
          'bengaluru urban': 'Bengaluru Urban',
          'bangalore rural': 'Bengaluru Rural',
          'bengaluru rural': 'Bengaluru Rural',
          'bellary': 'Ballari',
          'belgaum': 'Belagavi',
          'gulbarga': 'Kalaburagi',
          'mysore': 'Mysuru',
          'mangalore': 'Dakshina Kannada',
          'mangaluru': 'Dakshina Kannada',
          'south canara': 'Dakshina Kannada',
          'dakshina kannada': 'Dakshina Kannada',
          'chikmagalur': 'Chikkamagaluru',
          'chickmagalur': 'Chikkamagaluru',
          'shimoga': 'Shivamogga',
          'bijapur': 'Vijayapura',
          'chikballapur': 'Chikkaballapura',
          'chickballapur': 'Chikkaballapura',
          'tumkur': 'Tumakuru',
          'karwar': 'Uttara Kannada',
          'north canara': 'Uttara Kannada'
        };

        let matchedDistrict = '';
        
        // Match terms against aliases first
        for (const term of searchTerms) {
          for (const [alias, standardName] of Object.entries(aliasMap)) {
            if (term.includes(alias)) {
              matchedDistrict = standardName;
              break;
            }
          }
          if (matchedDistrict) break;

          // Match direct names
          const directMatch = DISTRICTS.find(d => term.includes(d.toLowerCase()) || d.toLowerCase().includes(term));
          if (directMatch) {
            matchedDistrict = directMatch;
            break;
          }
        }

        if (matchedDistrict) {
          setDistrict(matchedDistrict);
          toast(
            lang === 'kn' 
              ? `ಪತ್ತೆಯಾದ ಜಿಲ್ಲೆ: ${matchedDistrict} 📍` 
              : `Found District: ${matchedDistrict} 📍`, 
            'success'
          );
        } else {
          toast(
            lang === 'kn' 
              ? 'ಕರ್ನಾಟಕದ ಜಿಲ್ಲೆಯನ್ನು ಪತ್ತೆಹಚ್ಚಲು ಸಾಧ್ಯವಾಗಲಿಲ್ಲ' 
              : 'Could not match location to a Karnataka district', 
            'warning'
          );
        }
      } catch (e) {
        console.error(e);
        toast(lang === 'kn' ? 'ಸ್ಥಳ ಪತ್ತೆ ಮಾಡಲು ವಿಫಲವಾಗಿದೆ' : 'Failed to reverse geocode location', 'error');
      }
    }, (err) => {
      console.warn("Geolocation error:", err);
      toast(lang === 'kn' ? 'ಸ್ಥಳದ ಅನುಮತಿಯನ್ನು ನಿರಾಕರಿಸಲಾಗಿದೆ' : 'Location permission denied by user', 'error');
    }, { enableHighAccuracy: true, timeout: 8000 });
  }

  function bookWorker(w) {
    if (!user) { navigate('/login'); return; }
    if (role !== 'hirer') { navigate('/login'); return; }
    navigate(`/book?worker=${encodeURIComponent(w.uid || w.id)}`);
  }

  const totalPages  = Math.ceil(filtered.length / PAGE_SIZE);
  const pageWorkers = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);
  // Taluks for the selected district — from karnataka.js (all 31 districts)
  const taluks = district ? (KARNATAKA_TALUKS[district] || []) : [];

  const CATEGORIES = lang === 'kn' ? CATEGORIES_KN : CATEGORIES_EN;
  const activeCategory = lang === 'kn'
    ? category
    : (CATEGORIES_KN.includes(category) ? CATEGORIES_EN[CATEGORIES_KN.indexOf(category)] : category);

  return (
    <div style={{ minHeight: '100vh', background: 'var(--paper)' }}>
      <Navbar lang={lang} onLangChange={setLang} />

      {/* ── Ticker ── */}
      <div className="ticker-bar">
        <div className="ticker-track">
          {[...TICKER_ITEMS, ...TICKER_ITEMS].map((item, i) => (
            <span key={i} className="ticker-item">{item}</span>
          ))}
        </div>
      </div>

      {/* ── Hero ── */}
      <section className="hero">
        <div className="hero-inner">
          <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.5 }}>
            <div className="hero-pills">
              <span className="hero-pill green">
                <span className="pulse-dot" style={{ background: '#22C55E' }} />
                {workers.length}+ {lang === 'kn' ? 'ಕರ್ನಾಟಕ ಉದ್ಯೋಗಿಗಳು' : 'Workers across Karnataka'}
              </span>
              <span className="hero-pill orange">
                <span className="pulse-dot" style={{ background: '#fb923c' }} />
                {onlineCount} {lang === 'kn' ? 'ಆನ್‌ಲೈನ್‌ನಲ್ಲಿ' : 'online now'}
              </span>
            </div>

            <h1>
              {lang === 'kn' ? 'ನುರಿತ ' : 'Find Skilled '}
              <span className="accent">{lang === 'kn' ? 'ಕೆಲಸಗಾರರನ್ನು' : 'Workers'}</span>
              {lang === 'kn' ? ' ಹುಡುಕಿ' : ''}
            </h1>
            <p className="hero-sub">
              {lang === 'kn'
                ? 'ನಿಮ್ಮ ಹತ್ತಿರ ನುರಿತ ಕೆಲಸಗಾರರನ್ನು ಹುಡುಕಿ'
                : 'Find Skilled Workers Near You'}
              <br />
              {lang === 'kn'
                ? 'ಚಿತ್ರಕಾರರು, ಪ್ಲಂಬರ್‌ಗಳು, ವಿದ್ಯುತ್ ತಜ್ಞರು & 40+ ವೃತ್ತಿಗಳು'
                : 'Painters, Plumbers, Electricians, Masons & 40+ trades'}
              <br />
              {lang === 'kn' ? 'ಕರ್ನಾಟಕದ 31 ಜಿಲ್ಲೆಗಳಲ್ಲಿ — 0% ಕಮಿಷನ್.' : 'across all 31 Karnataka districts — 0% commission.'}
            </p>
          </motion.div>

          {/* Stats */}
          <div className="stats-bar">
            {[
              { num: workers.length, label: lang === 'kn' ? 'ಕೆಲಸಗಾರರು' : 'Workers' },
              { num: 31, label: lang === 'kn' ? 'ಜಿಲ್ಲೆಗಳು' : 'Districts' },
              { num: jobsCount, label: lang === 'kn' ? 'ಕೆಲಸ ಪೋಸ್ಟ್' : 'Jobs Posted' },
              { num: '0%', label: lang === 'kn' ? 'ಕಮಿಷನ್' : 'Commission' },
            ].map(s => (
              <div key={s.label} className="stat-item">
                <div className="stat-num">{s.num}</div>
                <div className="stat-label">{s.label}</div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ── Search ── */}
      <section className="search-section">
        <div className="search-inner">
          <div className="search-row">
            {/* District */}
            <select className="search-select" value={district} onChange={e => { setDistrict(e.target.value); setTaluk(''); }}>
              <option value="">{lang === 'kn' ? 'ಎಲ್ಲ ಜಿಲ್ಲೆಗಳು' : 'All Districts'}</option>
              {DISTRICTS.map(d => <option key={d}>{d}</option>)}
            </select>

            {/* Taluk — disabled until district is chosen; shows all taluks for selected district */}
            <select
              className="search-select"
              value={taluk}
              onChange={e => setTaluk(e.target.value)}
              disabled={!district}  /* 🎨 remove 'disabled' if you want taluk always active */
              style={{ opacity: district ? 1 : 0.55, cursor: district ? 'pointer' : 'not-allowed' }}
            >
              <option value="">
                {district
                  ? (lang === 'kn' ? 'ಎಲ್ಲ ತಾಲ್ಲೂಕುಗಳು' : 'All Taluks')
                  : (lang === 'kn' ? '— ಮೊದಲು ಜಿಲ್ಲೆ ಆಯ್ಕೆ —' : '— Select District First —')}
              </option>
              {/* .en value must match worker.taluk stored in Firestore */}
              {taluks.map(t => (
                <option key={t.en} value={t.en}>{t.en}</option>
              ))}
            </select>

            {/* Search */}
            <input className="search-input" value={search} onChange={e => setSearch(e.target.value)}
              placeholder={lang === 'kn' ? 'ಹೆಸರು, ಕೌಶಲ್ಯ ಹುಡುಕಿ...' : 'Search name, trade...'} />

            {/* Near Me */}
            <button className="near-me-btn" onClick={nearMe}>
              🌍 {lang === 'kn' ? 'ಹತ್ತಿರ' : 'Near Me'}
            </button>
          </div>

          {/* Category pills */}
          <div className="category-pills">
            {CATEGORIES.map((c, i) => (
              <button
                key={c}
                className={`pill ${(category === c || (lang === 'en' && category === CATEGORIES_KN[i])) ? 'active' : ''}`}
                onClick={() => setCategory(c)}
              >
                {CAT_ICONS[i]} {c}
              </button>
            ))}
          </div>
        </div>
      </section>

      {/* ── Results bar + Sort ── */}
      <div className="results-bar">
        <span style={{ fontSize: '0.88rem', color: 'var(--muted)' }}>
          <strong style={{ color: 'var(--ink)' }}>{filtered.length}</strong>{' '}
          {lang === 'kn' ? 'ಕೆಲಸಗಾರರು ಕಂಡುಬಂದರು' : 'workers found'}
        </span>
        <div className="sort-btns">
          <span style={{ fontSize: '0.78rem', color: 'var(--muted)', alignSelf: 'center' }}>
            {lang === 'kn' ? 'ವಿಂಗಡಿಸಿ:' : 'Sort:'}
          </span>
          {[
            { id: 'rating',   label: lang === 'kn' ? '⭐ ರೇಟಿಂಗ್' : '⭐ Rating' },
            { id: 'price_up', label: lang === 'kn' ? '💰 ಬೆಲೆ ↑' : '💰 Price ↑' },
            { id: 'price_dn', label: lang === 'kn' ? '💰 ಬೆಲೆ ↓' : '💰 Price ↓' },
            { id: 'exp',      label: lang === 'kn' ? '🏆 ಅನುಭವ' : '🏆 Experience' },
          ].map(s => (
            <button key={s.id} className={`sort-btn ${sortBy === s.id ? 'active' : ''}`}
              onClick={() => setSortBy(sortBy === s.id ? '' : s.id)}>
              {s.label}
            </button>
          ))}
        </div>
      </div>

      {/* ── Workers Grid ── */}
      <section className="workers-section">
        {loading ? (
          <div className="workers-grid">
            {Array(8).fill(0).map((_, i) => (
              <div key={i} className="worker-card">
                <div className="skeleton" style={{ height: 52, width: 52, borderRadius: '50%', marginBottom: 12 }} />
                <div className="skeleton" style={{ height: 16, width: '60%', marginBottom: 8 }} />
                <div className="skeleton" style={{ height: 12, width: '40%', marginBottom: 16 }} />
                <div className="skeleton" style={{ height: 10, width: '80%' }} />
              </div>
            ))}
          </div>
        ) : pageWorkers.length === 0 ? (
          <div className="state-box" style={{ padding: '40px 24px', textAlign: 'center' }}>
            <div style={{ fontSize: '3rem', marginBottom: 12 }}>
              {taluk ? '📍' : '👷'}
            </div>

            {/* Smart message depending on what filter is active */}
            {taluk ? (
              <>
                <p style={{ fontWeight: 600, color: 'var(--ink)', marginBottom: 6 }}>
                  {lang === 'kn'
                    ? `${taluk} ತಾಲ್ಲೂಕಿನಲ್ಲಿ ಯಾವುದೇ ಕೆಲಸಗಾರರಿಲ್ಲ`
                    : `No workers registered in ${taluk} taluk yet`}
                </p>
                <p style={{ fontSize: '0.85rem', color: 'var(--muted)', marginBottom: 16 }}>
                  {lang === 'kn'
                    ? `${district} ಜಿಲ್ಲೆಯಲ್ಲಿ ನೋಡಲು ಫಿಲ್ಟರ್ ತೆಗೆಯಿರಿ`
                    : `Try clearing the taluk filter to see all workers in ${district} district`}
                </p>
                {/* 🎨 Clear button colours — change bg and color */}
                <div style={{ display: 'flex', gap: 10, justifyContent: 'center', flexWrap: 'wrap' }}>
                  <button
                    onClick={() => setTaluk('')}
                    style={{
                      padding: '9px 20px', borderRadius: 10,
                      background: 'var(--saffron)', color: '#fff',
                      border: 'none', cursor: 'pointer',
                      fontFamily: "'DM Sans',sans-serif",
                      fontWeight: 600, fontSize: '0.88rem',
                    }}
                  >
                    {lang === 'kn' ? '✕ ತಾಲ್ಲೂಕು ಫಿಲ್ಟರ್ ತೆಗೆಯಿರಿ' : '✕ Clear Taluk Filter'}
                  </button>
                  <button
                    onClick={() => { setDistrict(''); setTaluk(''); }}
                    style={{
                      padding: '9px 20px', borderRadius: 10,
                      background: 'transparent', color: 'var(--saffron)',
                      border: '1.5px solid var(--saffron)', cursor: 'pointer',
                      fontFamily: "'DM Sans',sans-serif",
                      fontWeight: 600, fontSize: '0.88rem',
                    }}
                  >
                    {lang === 'kn' ? 'ಎಲ್ಲ ಕೆಲಸಗಾರರು ತೋರಿಸಿ' : 'Show All Workers'}
                  </button>
                </div>
              </>
            ) : (
              <>
                <p>{lang === 'kn' ? 'ಕೆಲಸಗಾರರು ಕಂಡುಬಂದಿಲ್ಲ.' : 'No workers found matching your filters.'}</p>
                {(district || search || category !== 'All') && (
                  <button
                    onClick={() => { setDistrict(''); setTaluk(''); setSearch(''); }}
                    style={{
                      marginTop: 12, padding: '8px 18px', borderRadius: 10,
                      background: 'var(--saffron)', color: '#fff',
                      border: 'none', cursor: 'pointer',
                      fontFamily: "'DM Sans',sans-serif", fontWeight: 600, fontSize: '0.85rem',
                    }}
                  >
                    {lang === 'kn' ? 'ಎಲ್ಲ ಫಿಲ್ಟರ್ ತೆಗೆಯಿರಿ' : 'Clear All Filters'}
                  </button>
                )}
                <Link to="/login" style={{ color: 'var(--saffron)', display: 'block', marginTop: 12 }}>
                  {lang === 'kn' ? 'ಕೆಲಸಗಾರನಾಗಿ ನೋಂದಾಯಿಸಿ →' : 'Register as a Worker →'}
                </Link>
              </>
            )}
          </div>
        ) : (
          <div className="workers-grid">
            <AnimatePresence>
              {pageWorkers.map((w, i) => {
                const initials = (w.name || 'U').split(' ').map(n => n[0]).join('').slice(0, 2).toUpperCase();
                const trade    = (w.skills || [])[0] || (lang === 'kn' ? 'ದಿನ ಕೆಲಸಗಾರ' : 'Daily Worker');
                const rate     = w.dailyRate ? `₹${w.dailyRate}/day` : (w.hourlyRate ? `₹${w.hourlyRate}/hr` : '—');
                const location = [w.taluk, w.district].filter(Boolean).join(', ') || 'Karnataka';
                const isOnline = false; // would come from presence RTDB

                return (
                  <motion.div key={w.id} className="worker-card"
                    initial={{ opacity: 0, y: 18 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ duration: 0.28, delay: i * 0.04, ease: [0.4, 0, 0.2, 1] }}
                    layout
                  >
                    {w.profileComplete && (
                      <div className="wc-verified">✔ {lang === 'kn' ? 'ಪರಿಶೀಲಿಸಲಾಗಿದೆ' : 'VERIFIED'}</div>
                    )}

                    {/* Avatar + heart */}
                    <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 10, marginTop: 24 }}>
                      <div style={{ position: 'relative', flexShrink: 0 }}>
                        {w.photo
                          ? <img className="wc-avatar" src={w.photo} alt="" loading="lazy" />
                          : <div className="wc-avatar-ph">{initials}</div>
                        }
                        {isOnline && <div className="wc-online-dot" />}
                      </div>
                      <div style={{ minWidth: 0 }}>
                        <div style={{ fontWeight: 700, fontSize: '0.95rem', color: 'var(--ink)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                          {w.name || 'Worker'}
                        </div>
                        <div style={{ fontSize: '0.78rem', color: 'var(--muted)' }}>{trade}</div>
                      </div>
                    </div>

                    <div style={{ fontSize: '0.78rem', color: 'var(--muted)', marginBottom: 8 }}>
                      📍 {location}
                    </div>

                    {/* Skills */}
                    <div style={{ display: 'flex', gap: 5, flexWrap: 'wrap', marginBottom: 10 }}>
                      {(w.skills || []).slice(0, 2).map(s => (
                        <span key={s} style={{
                          padding: '2px 9px', background: 'var(--saffron-light)', color: 'var(--saffron)',
                          borderRadius: 20, fontSize: '0.7rem', fontWeight: 600,
                        }}>{s}</span>
                      ))}
                      {w.experience && (
                        <span style={{
                          padding: '2px 9px', background: 'var(--jade-light)', color: 'var(--jade)',
                          borderRadius: 20, fontSize: '0.7rem', fontWeight: 600,
                        }}>{w.experience}</span>
                      )}
                    </div>

                    {/* Rate + Rating */}
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12, fontSize: '0.78rem' }}>
                      <span style={{ fontWeight: 700, color: 'var(--jade)', fontSize: '0.9rem' }}>{rate}</span>
                      <span style={{ color: 'var(--muted)' }}>
                        {w.rating ? `⭐ ${w.rating.toFixed(1)}` : (lang === 'kn' ? 'ಹೊಸಬ' : 'New')}
                      </span>
                    </div>

                    {/* Action buttons */}
                    <div style={{ display: 'flex', gap: 7, marginTop: 'auto' }}>
                      <button onClick={() => navigate(`/chat?worker=${w.uid || w.id}`)}
                        className="btn btn-outline btn-sm" style={{ flex: 1 }}>
                        💬 {lang === 'kn' ? 'ಸಂದೇಶ' : 'Message'}
                      </button>
                      <button onClick={() => bookWorker(w)}
                        className="btn btn-primary btn-sm" style={{ flex: 1 }}>
                        📅 {lang === 'kn' ? 'ಬುಕ್' : 'Book'}
                      </button>
                    </div>
                  </motion.div>
                );
              })}
            </AnimatePresence>
          </div>
        )}

        {/* Pagination */}
        {totalPages > 1 && (
          <div style={{ display: 'flex', gap: 8, justifyContent: 'center', marginTop: 28 }}>
            {Array.from({ length: totalPages }, (_, i) => i + 1).map(n => (
              <button key={n} onClick={() => { setPage(n); window.scrollTo({ top: 380, behavior: 'smooth' }); }}
                style={{
                  padding: '8px 14px', borderRadius: 8, border: '1.5px solid var(--border)',
                  background: n === page ? 'var(--saffron)' : 'var(--white)',
                  color: n === page ? '#fff' : 'var(--ink)', fontWeight: 600, cursor: 'pointer', transition: 'all 0.2s',
                }}>
                {n}
              </button>
            ))}
          </div>
        )}
      </section>

      {/* FAB — only for hirers */}
      {role === 'hirer' && (
        <motion.button className="fab" onClick={() => navigate('/post-job')}
          whileHover={{ scale: 1.1 }} whileTap={{ scale: 0.95 }}
          title={lang === 'kn' ? 'ಕೆಲಸ ಪೋಸ್ಟ್ ಮಾಡಿ' : 'Post a Job'}
        >
          +
        </motion.button>
      )}

      <footer>
        <p>© 2026 KelasaGaara — {lang === 'kn' ? 'ಕರ್ನಾಟಕದ ಕೌಶಲ್ಯಪೂರ್ಣ ಕೆಲಸಗಾರರನ್ನು ನೇಮಕಗಾರರೊಂದಿಗೆ ಸಂಪರ್ಕಿಸುತ್ತದೆ.' : 'Connecting Karnataka\'s skilled workers with hirers.'} Built with ❤️</p>
      </footer>
    </div>
  );
}
