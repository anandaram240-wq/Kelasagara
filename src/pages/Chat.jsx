import { useState, useEffect, useRef } from 'react';
import { useSearchParams, Link } from 'react-router-dom';
import { doc, getDoc, collection, query, where, getDocs } from 'firebase/firestore';
import { ref, push, onChildAdded, onValue, update, get, off, onDisconnect } from 'firebase/database';
import { motion, AnimatePresence } from 'framer-motion';
import { db, rtdb } from '../firebase';
import { useAuthStore } from '../store/authStore';
import Navbar from '../components/Navbar';

export default function Chat() {
  const { user, profile, role } = useAuthStore();
  const [params] = useSearchParams();
  const initBookingId = params.get('booking');

  const [convs, setConvs] = useState([]);
  const [activeId, setActiveId] = useState(initBookingId || null);
  const [booking, setBooking] = useState(null);
  const [otherUser, setOtherUser] = useState(null);
  const [messages, setMessages] = useState([]);
  const [input, setInput] = useState('');
  const [isOnline, setIsOnline] = useState(false);
  const [isTyping, setIsTyping] = useState(false);
  const [convLoading, setConvLoading] = useState(true);
  const msgRef = useRef(null);
  const msgEndRef = useRef(null);
  const typingTimer = useRef(null);

  // Set online presence
  useEffect(() => {
    if (!user) return;
    const presRef = ref(rtdb, `presence/${user.uid}`);
    update(presRef, { online: true, lastSeen: Date.now() });
    onDisconnect(presRef).update({ online: false, lastSeen: Date.now() });
    return () => update(presRef, { online: false, lastSeen: Date.now() });
  }, [user]);

  // Load sidebar conversations
  useEffect(() => {
    if (!user) return;
    async function loadConvs() {
      setConvLoading(true);
      try {
        const [h, w] = await Promise.all([
          getDocs(query(collection(db,'bookings'), where('hirerId','==',user.uid))),
          getDocs(query(collection(db,'bookings'), where('workerId','==',user.uid))),
        ]);
        const all = [...h.docs.map(d=>({id:d.id,...d.data(),_role:'hirer'})), ...w.docs.map(d=>({id:d.id,...d.data(),_role:'worker'}))];
        // Enrich with other user name
        const enriched = await Promise.all(all.map(async b => {
          const otherId = b._role === 'hirer' ? b.workerId : b.hirerId;
          try { const s = await getDoc(doc(db,'users',otherId)); b.otherUser = s.data(); } catch { b.otherUser = {}; }
          // Get last message
          try {
            const ms = await get(ref(rtdb, `chats/${b.id}/messages`));
            if (ms.exists()) {
              const arr = Object.values(ms.val());
              b.lastMsg = arr.sort((a,z)=>z.timestamp-a.timestamp)[0]?.messageText || '';
            }
          } catch {}
          return b;
        }));
        enriched.sort((a,z)=>(z.createdAt?.seconds||0)-(a.createdAt?.seconds||0));
        setConvs(enriched);
      } catch(e) { console.error(e); }
      setConvLoading(false);
    }
    loadConvs();
  }, [user]);

  // Open a conversation
  useEffect(() => {
    if (activeId) openConv(activeId);
  }, [activeId]);

  async function openConv(bookingId) {
    // Clear previous listener
    if (msgRef.current) { off(msgRef.current); }
    setMessages([]);
    setOtherUser(null);
    setBooking(null);

    try {
      const bSnap = await getDoc(doc(db,'bookings',bookingId));
      if (!bSnap.exists()) return;
      const b = { id:bSnap.id, ...bSnap.data() };
      setBooking(b);

      const otherId = b.hirerId === user.uid ? b.workerId : b.hirerId;
      const oSnap = await getDoc(doc(db,'users',otherId));
      const oData = oSnap.data() || {};
      setOtherUser({ id: otherId, ...oData });

      // Online status
      const presRef = ref(rtdb, `presence/${otherId}`);
      onValue(presRef, snap => setIsOnline(snap.val()?.online || false));

      // Typing indicator
      const typRef = ref(rtdb, `typing/${bookingId}`);
      onValue(typRef, snap => {
        const data = snap.val() || {};
        const someone = Object.entries(data).some(([uid,v]) => uid !== user.uid && v?.typing);
        setIsTyping(someone);
      });

      // Mark messages as read
      const allMsgs = await get(ref(rtdb, `chats/${bookingId}/messages`));
      if (allMsgs.exists()) {
        const updates = {};
        allMsgs.forEach(c => {
          if (c.val().senderId !== user.uid && !c.val().isRead)
            updates[`chats/${bookingId}/messages/${c.key}/isRead`] = true;
        });
        if (Object.keys(updates).length) update(ref(rtdb), updates);
      }

      // Listen for messages
      const loaded = [];
      if (allMsgs.exists()) {
        allMsgs.forEach(c => loaded.push({ id:c.key, ...c.val() }));
        setMessages(loaded.sort((a,z)=>a.timestamp-z.timestamp));
      }
      // Then listen for new ones
      const chatRef = ref(rtdb, `chats/${bookingId}/messages`);
      msgRef.current = chatRef;
      const lastTs = loaded.at(-1)?.timestamp || 0;
      onChildAdded(chatRef, snap => {
        const m = { id:snap.key, ...snap.val() };
        if (m.timestamp > lastTs) {
          setMessages(ms => ms.some(x=>x.id===m.id) ? ms : [...ms, m]);
        }
      });
    } catch(e) { console.error('openConv error', e); }
  }

  // Scroll to bottom on new messages
  useEffect(() => {
    msgEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages, isTyping]);

  function sendMessage() {
    const text = input.trim();
    if (!text || !activeId || !otherUser) return;
    setInput('');
    update(ref(rtdb, `typing/${activeId}/${user.uid}`), { typing: false, ts: Date.now() });
    push(ref(rtdb, `chats/${activeId}/messages`), {
      senderId:    user.uid,
      senderRole:  role || 'hirer',
      receiverId:  otherUser.id,
      messageText: text,
      timestamp:   Date.now(),
      isRead:      false,
    });
  }

  function onInput(e) {
    setInput(e.target.value);
    if (activeId && user) {
      update(ref(rtdb, `typing/${activeId}/${user.uid}`), { typing: true, ts: Date.now() });
      clearTimeout(typingTimer.current);
      typingTimer.current = setTimeout(() => {
        update(ref(rtdb, `typing/${activeId}/${user.uid}`), { typing: false, ts: Date.now() });
      }, 3000);
    }
  }

  function fmtTime(ts) { return new Date(ts).toLocaleTimeString('en-IN', {hour:'2-digit',minute:'2-digit'}); }
  function fmtDate(ts) {
    const d = new Date(ts), today = new Date(), yest = new Date(today); yest.setDate(today.getDate()-1);
    if (d.toDateString()===today.toDateString()) return 'Today';
    if (d.toDateString()===yest.toDateString()) return 'Yesterday';
    return d.toLocaleDateString('en-IN',{day:'numeric',month:'short'});
  }

  const STATUS_COLORS = { PENDING:'#D97706', CONFIRMED:'#16A34A', DECLINED:'#DC2626', COMPLETED:'#2563EB' };

  // Group messages by date
  const grouped = [];
  let lastDate = '';
  messages.forEach(m => {
    const d = fmtDate(m.timestamp);
    if (d !== lastDate) { grouped.push({ type:'date', date:d, key:`date-${d}` }); lastDate=d; }
    grouped.push({ type:'msg', ...m, key:m.id });
  });

  return (
    <div style={{display:'flex',flexDirection:'column',height:'100vh',overflow:'hidden'}}>
      <Navbar />
      <div className="chat-layout">
        {/* SIDEBAR */}
        <div className="chat-sidebar">
          <div className="chat-sidebar-header">💬 Conversations</div>
          <div className="conv-list">
            {convLoading ? (
              <div style={{padding:20,textAlign:'center'}}><div className="spinner" style={{margin:'0 auto'}}/></div>
            ) : convs.length === 0 ? (
              <div style={{padding:24,textAlign:'center',color:'var(--muted)',fontSize:'0.85rem'}}>No conversations yet.<br/><Link to="/" style={{color:'var(--saffron)'}}>Browse workers →</Link></div>
            ) : convs.map(c => {
              const initials = (c.otherUser?.name||'?')[0].toUpperCase();
              return (
                <div key={c.id} className={`conv-item ${activeId===c.id?'active':''}`} onClick={()=>setActiveId(c.id)}>
                  <div className="conv-avatar" style={{width:42,height:42,fontSize:'0.85rem'}}>
                    {c.otherUser?.photo ? <img src={c.otherUser.photo} style={{width:42,height:42,borderRadius:'50%',objectFit:'cover'}} alt=""/> : initials}
                  </div>
                  <div style={{flex:1,minWidth:0}}>
                    <div style={{fontWeight:600,fontSize:'0.88rem'}}>{c.otherUser?.name||'User'}</div>
                    <div style={{fontSize:'0.72rem',display:'flex',alignItems:'center',gap:4}}>
                      <span style={{color:'var(--muted)'}}>{(c.otherUser?.skills||[])[0]||c.jobTitle||''}</span>
                      <span style={{color:STATUS_COLORS[c.status]||'#9CA3AF',fontWeight:600}}>{c.status}</span>
                    </div>
                    {c.lastMsg && <div style={{fontSize:'0.7rem',color:'var(--muted)',overflow:'hidden',textOverflow:'ellipsis',whiteSpace:'nowrap',maxWidth:170}}>{c.lastMsg}</div>}
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        {/* MAIN */}
        <div className="chat-main">
          {!activeId || !booking ? (
            <div style={{flex:1,display:'flex',flexDirection:'column',alignItems:'center',justifyContent:'center',color:'var(--muted)'}}>
              <div style={{fontSize:'4rem',marginBottom:16}}>💬</div>
              <div style={{fontFamily:"'Baloo Tamma 2',cursive",fontSize:'1.2rem',fontWeight:700,color:'var(--ink)',marginBottom:8}}>Select a Conversation</div>
              <p>Choose a booking from the sidebar</p>
            </div>
          ) : (
            <>
              {/* Chat Header */}
              <div className="chat-header">
                <div className="conv-avatar" style={{width:42,height:42,fontSize:'0.9rem',flexShrink:0}}>
                  {otherUser?.photo ? <img src={otherUser.photo} style={{width:42,height:42,borderRadius:'50%',objectFit:'cover'}} alt=""/> : (otherUser?.name||'?')[0].toUpperCase()}
                </div>
                <div style={{flex:1}}>
                  <div style={{fontWeight:700,fontSize:'0.95rem'}}>{otherUser?.name}</div>
                  <div style={{fontSize:'0.73rem',color:isTyping?'var(--saffron)':isOnline?'#22C55E':'var(--muted)'}}>
                    {isTyping ? `✍️ ${otherUser?.name?.split(' ')[0]} is typing…` : isOnline ? '● Online' : '○ Offline'}
                  </div>
                </div>
                {(booking.status==='CONFIRMED'||booking.status==='COMPLETED') && otherUser?.phone && (
                  <a href={`tel:${otherUser.phone}`} style={{fontSize:'0.78rem',background:'rgba(27,107,69,0.1)',color:'var(--jade)',padding:'5px 12px',borderRadius:20,fontWeight:600,textDecoration:'none'}}>📞 {otherUser.phone}</a>
                )}
              </div>

              {/* Booking Bar */}
              <div style={{background:'rgba(232,89,12,0.05)',borderBottom:'1px solid var(--border)',padding:'8px 18px',fontSize:'0.78rem',color:'var(--muted)',display:'flex',gap:12}}>
                <span>🔧 <strong>{booking.jobTitle||'Booking'}</strong></span>
                <span>📅 {booking.date||'—'}</span>
                <span style={{color:STATUS_COLORS[booking.status],fontWeight:600}}>{booking.status}</span>
              </div>

              {/* Messages */}
              <div className="chat-messages">
                {grouped.map(item => item.type === 'date' ? (
                  <div key={item.key} style={{textAlign:'center',fontSize:'0.72rem',color:'var(--muted)',background:'rgba(255,255,255,0.7)',padding:'4px 12px',borderRadius:20,alignSelf:'center',margin:'4px 0'}}>{item.date}</div>
                ) : (
                  <motion.div key={item.key} className={`msg-bubble ${item.senderId===user.uid?'sent':'recv'}`}
                    initial={{opacity:0,y:12}} animate={{opacity:1,y:0}} transition={{duration:0.22}}>
                    <div className="msg-text">{item.messageText}</div>
                    <div className="msg-meta">
                      {fmtTime(item.timestamp)}
                      {item.senderId===user.uid && <span className={`msg-seen ${item.isRead?'':''}`} style={{marginLeft:4}}>{item.isRead?'✓✓ Seen':'✓ Sent'}</span>}
                    </div>
                  </motion.div>
                ))}
                {isTyping && (
                  <div className="typing-bubble">
                    <div className="typing-dot"/><div className="typing-dot"/><div className="typing-dot"/>
                  </div>
                )}
                <div ref={msgEndRef}/>
              </div>

              {/* Input */}
              <div className="chat-input-area">
                <div className="chat-input-row">
                  <input className="chat-text-input" value={input} onChange={onInput}
                    onKeyDown={e=>e.key==='Enter'&&sendMessage()}
                    placeholder="Type a message… (Enter to send)"
                  />
                  <motion.button className="chat-send-btn" onClick={sendMessage} whileTap={{scale:0.95}}>Send ➤</motion.button>
                </div>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
