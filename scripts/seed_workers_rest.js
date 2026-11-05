// scripts/seed_workers_rest.js
// Seed 1000 synthetic Karnataka worker documents to Firestore via REST API.
// Uses the firebase-tools stored access token — no service account needed.
// isSeedData=true on every document for easy cleanup later.

const https = require('https');
const crypto = require('crypto');

const PROJECT_ID = 'kelasagara-f127a';
const FIRESTORE_BASE = `firestore.googleapis.com`;

// ── Get a fresh access token from firebase-tools stored credentials ────────
async function getAccessToken() {
  const auth = require('/usr/local/lib/node_modules/firebase-tools/lib/auth');
  const api = require('/usr/local/lib/node_modules/firebase-tools/lib/api');
  const acct = auth.getGlobalDefaultAccount();
  if (!acct) throw new Error('Not logged in. Run: firebase login');

  const tokens = acct.tokens;
  const now = Date.now();

  // If token is still valid (with 60s buffer), use it
  if (tokens.access_token && tokens.expires_at > now + 60000) {
    console.log(`✅ Using cached token for: ${acct.user.email}`);
    return tokens.access_token;
  }

  // Token expired — refresh it
  console.log(`🔄 Refreshing token for: ${acct.user.email}...`);
  const clientId = api.clientId();
  const clientSecret = api.clientSecret();
  const refreshToken = tokens.refresh_token;

  return new Promise((resolve, reject) => {
    const body = new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      refresh_token: refreshToken,
      grant_type: 'refresh_token',
    }).toString();
    const opts = {
      hostname: 'oauth2.googleapis.com',
      path: '/token',
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Content-Length': Buffer.byteLength(body),
      },
    };
    const req = https.request(opts, (res) => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => {
        const d = JSON.parse(data);
        if (d.access_token) {
          console.log(`✅ Token refreshed. Valid for ${d.expires_in}s.`);
          resolve(d.access_token);
        } else {
          reject(new Error(`Token refresh failed: ${data.substring(0, 200)}`));
        }
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

// ── District → centre coordinates ──────────────────────────────────────────
const DISTRICTS = [
  { name: 'Bengaluru Urban',   lat: 12.9716, lng: 77.5946, w: 80 },
  { name: 'Mysuru',            lat: 12.2958, lng: 76.6394, w: 40 },
  { name: 'Mangaluru',         lat: 12.9141, lng: 74.8560, w: 35 },
  { name: 'Hubballi',          lat: 15.3647, lng: 75.1240, w: 30 },
  { name: 'Belagavi',          lat: 15.8497, lng: 74.4977, w: 30 },
  { name: 'Kalaburagi',        lat: 17.3297, lng: 76.8200, w: 25 },
  { name: 'Shivamogga',        lat: 13.9299, lng: 75.5681, w: 25 },
  { name: 'Tumakuru',          lat: 13.3379, lng: 77.1173, w: 25 },
  { name: 'Ballari',           lat: 15.1394, lng: 76.9214, w: 20 },
  { name: 'Vijayapura',        lat: 16.8302, lng: 75.7100, w: 20 },
  { name: 'Hassan',            lat: 13.0068, lng: 76.1004, w: 20 },
  { name: 'Mandya',            lat: 12.5218, lng: 76.8951, w: 20 },
  { name: 'Davangere',         lat: 14.4644, lng: 75.9218, w: 20 },
  { name: 'Udupi',             lat: 13.3409, lng: 74.7421, w: 20 },
  { name: 'Raichur',           lat: 16.2120, lng: 77.3439, w: 18 },
  { name: 'Chikkamagaluru',    lat: 13.3161, lng: 75.7720, w: 18 },
  { name: 'Bagalkot',          lat: 16.1826, lng: 75.6965, w: 15 },
  { name: 'Dakshina Kannada',  lat: 12.8438, lng: 75.2479, w: 15 },
  { name: 'Bidar',             lat: 17.9104, lng: 77.5199, w: 15 },
  { name: 'Koppal',            lat: 15.3590, lng: 76.1547, w: 12 },
  { name: 'Gadag',             lat: 15.4283, lng: 75.6317, w: 12 },
  { name: 'Uttara Kannada',    lat: 14.7947, lng: 74.4977, w: 12 },
  { name: 'Kodagu',            lat: 12.4244, lng: 75.7382, w: 12 },
  { name: 'Chitradurga',       lat: 14.2251, lng: 76.3981, w: 12 },
  { name: 'Chikkaballapur',    lat: 13.4355, lng: 77.7315, w: 12 },
  { name: 'Ramanagara',        lat: 12.7157, lng: 77.2810, w: 12 },
  { name: 'Yadgir',            lat: 16.7689, lng: 77.1380, w: 10 },
  { name: 'Chamarajanagar',    lat: 11.9216, lng: 76.9428, w: 10 },
  { name: 'Haveri',            lat: 14.7961, lng: 75.3988, w: 10 },
  { name: 'Bengaluru Rural',   lat: 13.1596, lng: 77.5791, w: 10 },
];

const DISTRICT_POOL = [];
for (const d of DISTRICTS) for (let i = 0; i < d.w; i++) DISTRICT_POOL.push(d);

const SKILLS = [
  { id: 'plumber',     minR: 700,  maxR: 1400 },
  { id: 'electrician', minR: 800,  maxR: 1600 },
  { id: 'mason',       minR: 700,  maxR: 1300 },
  { id: 'carpenter',   minR: 700,  maxR: 1400 },
  { id: 'painter',     minR: 600,  maxR: 1200 },
  { id: 'driver',      minR: 700,  maxR: 1500 },
  { id: 'cook',        minR: 500,  maxR: 1100 },
  { id: 'cleaner',     minR: 400,  maxR:  900 },
  { id: 'gardener',    minR: 400,  maxR:  900 },
  { id: 'security',    minR: 500,  maxR: 1000 },
  { id: 'tailor',      minR: 500,  maxR: 1100 },
  { id: 'welder',      minR: 800,  maxR: 1500 },
  { id: 'helper',      minR: 400,  maxR:  700 },
];

const MALE = ['Rajesh','Suresh','Ramesh','Mahesh','Ganesh','Nagaraj','Shivaraj','Venkatesh','Ravi','Srinivas','Manjunath','Prakash','Basavraj','Mohammed','Abdul','Ibrahim','Salim','Arun','Deepak','Santosh','Anthony','Joseph','Rajkumar','Lokesh','Prashanth','Praveen','Nagesh','Ashok','Kiran','Naveen','Harish','Vijay','Sunil','Mohan','Girish','Umesh','Satish','Dinesh','Anand','Rakesh','Imran','Faizal','Arjun','Bhuvanesh','Chetan','Muniraj','Haneef','Shahid','Yusuf','Thomas','Francis','Benny','Siddesh'];
const FEMALE = ['Lakshmi','Savitha','Rekha','Sunitha','Usha','Geetha','Manjula','Shobha','Fatima','Ayesha','Mary','Kavitha','Radha','Vimala','Pushpa','Meena','Suma','Anitha','Jayamma','Roopa','Nandini','Bhavana','Shwetha','Divya','Zainab','Hameeda','Regina','Lissy','Chandrakala','Parvathi'];
const SURNAMES = ['Kumar','Gowda','Reddy','Naidu','Sharma','Khan','Patel','Nair','Rao','Patil','Hegde','Shetty','D\'Souza','Sequeira','Siddiqui','Verma','Iyer','Pillai','Bhat','Kamath','Joshi','Kulkarni','More','Shinde','Gupta','Singh','Swamy','Raju','Babu','Naik','Poojari','Gaonkar','Devadiga','Kunder'];
const VER_LEVELS = ['practicalVerified','basicAssessed','experienced','advanced'];
const RADII = [10,15,20,25,30];

function pick(arr) { return arr[Math.floor(Math.random()*arr.length)]; }
function randInt(a,b) { return Math.floor(Math.random()*(b-a+1))+a; }
function randFloat(a,b,dp=4) { return parseFloat((Math.random()*(b-a)+a).toFixed(dp)); }
function jitter(c,km) { return c + (km/111.0)*(Math.random()*2-1); }
function pickDistrict() { return DISTRICT_POOL[Math.floor(Math.random()*DISTRICT_POOL.length)]; }

// ── Convert a JS value to Firestore REST Value format ─────────────────────
function toValue(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') {
    if (Number.isInteger(v)) return { integerValue: String(v) };
    return { doubleValue: v };
  }
  if (typeof v === 'string') return { stringValue: v };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(toValue) } };
  if (typeof v === 'object') {
    const fields = {};
    for (const [k, val] of Object.entries(v)) fields[k] = toValue(val);
    return { mapValue: { fields } };
  }
  return { stringValue: String(v) };
}

function toFirestoreDoc(obj) {
  const fields = {};
  for (const [k,v] of Object.entries(obj)) fields[k] = toValue(v);
  return { fields };
}

// ── Build 1000 worker objects ─────────────────────────────────────────────
function buildWorkers(count=1000) {
  // Cycle through skills to ensure all are represented
  const skillCycle = [];
  for (let i=0; i<count; i++) skillCycle.push(SKILLS[i%SKILLS.length]);
  // Shuffle
  for (let i=skillCycle.length-1; i>0; i--) {
    const j=randInt(0,i);
    [skillCycle[i],skillCycle[j]]=[skillCycle[j],skillCycle[i]];
  }

  const now = new Date();
  const workers = [];
  for (let i=0; i<count; i++) {
    const isMale = Math.random()<0.72;
    const first = isMale ? pick(MALE) : pick(FEMALE);
    const surname = pick(SURNAMES);
    const name = `${first} ${surname}`;
    const d = pickDistrict();
    const sk = skillCycle[i];
    const lat = parseFloat(jitter(d.lat,8).toFixed(5));
    const lng = parseFloat(jitter(d.lng,8).toFixed(5));
    const totalJobs = randInt(0,220);
    const rating = randFloat(3.2,5.0,1);
    const totalRatings = totalJobs>0 ? randInt(0,Math.min(totalJobs,80)) : 0;
    const ratingSum = parseFloat((rating*totalRatings).toFixed(1));
    // discoveryUpdatedAt: random within last 4 hours
    const disc = new Date(now.getTime() - randInt(0, 4*3600*1000));

    workers.push({
      name, displayName: name,
      role: 'worker',
      gender: isMale ? 'male' : 'female',
      phone: `+91${randInt(6000000000,9999999999)}`,
      email: `${first.toLowerCase().replace("'","")}${randInt(10,999)}@example.com`,
      accountStatus: 'approved',
      isAvailable: true,
      faceVerified: false,
      skillVerified: false,
      verificationLevel: pick(VER_LEVELS),
      district: d.name,
      taluk: d.name,
      lat, lng,
      discoveryLat: lat,
      discoveryLng: lng,
      discoveryUpdatedAt: disc,
      discoverySessionId: `seed_${crypto.randomBytes(8).toString('hex')}`,
      discoveryAccuracy: randFloat(5.0,40.0,1),
      serviceRadiusKm: pick(RADII),
      skills: [sk.id],
      primarySkill: sk.id,
      totalJobs, completedJobs: totalJobs,
      rating, ratingSum, totalRatings,
      dailyRate: randInt(sk.minR,sk.maxR),
      isSeedData: true,
      profileImageUrl: null,
      bio: '',
    });
  }
  return workers;
}

// ── POST a single document to Firestore REST API ──────────────────────────
function postDocument(token, doc) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify(toFirestoreDoc(doc));
    const path = `/v1/projects/${PROJECT_ID}/databases/(default)/documents/users`;
    const opts = {
      hostname: FIRESTORE_BASE,
      path,
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
      },
    };
    const req = https.request(opts, (res) => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve(JSON.parse(data));
        } else {
          reject(new Error(`HTTP ${res.statusCode}: ${data.substring(0,300)}`));
        }
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

// ── Batch commit via REST batchWrite ──────────────────────────────────────
// Firestore REST batchWrite supports up to 500 writes per call
function batchWrite(token, docs) {
  return new Promise((resolve, reject) => {
    const writes = docs.map(doc => ({
      update: {
        name: `projects/${PROJECT_ID}/databases/(default)/documents/users/${crypto.randomBytes(10).toString('hex')}`,
        fields: toFirestoreDoc(doc).fields,
      }
    }));
    const body = JSON.stringify({ writes });
    const path = `/v1/projects/${PROJECT_ID}/databases/(default)/documents:batchWrite`;
    const opts = {
      hostname: FIRESTORE_BASE,
      path,
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
      },
    };
    const req = https.request(opts, (res) => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve(JSON.parse(data));
        } else {
          reject(new Error(`HTTP ${res.statusCode}: ${data.substring(0,500)}`));
        }
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

// ── Main ──────────────────────────────────────────────────────────────────
async function main() {
  const token = await getAccessToken();
  const workers = buildWorkers(1000);
  console.log(`\n✅ Generated ${workers.length} worker documents`);
  console.log(`📤 Uploading to Firestore (kelasagara-f127a) via REST...\n`);

  const BATCH = 200; // conservative batch size
  let uploaded = 0;

  for (let i = 0; i < workers.length; i += BATCH) {
    const chunk = workers.slice(i, i + BATCH);
    try {
      await batchWrite(token, chunk);
      uploaded += chunk.length;
      console.log(`  ✓ ${uploaded}/${workers.length} uploaded`);
    } catch (e) {
      console.error(`  ❌ Batch failed at ${i}: ${e.message}`);
      throw e;
    }
    // Small delay to avoid rate limiting
    if (i + BATCH < workers.length) await new Promise(r => setTimeout(r, 300));
  }

  console.log(`\n🎉 Done! ${uploaded} seed workers in Firestore 'users' collection.`);
  console.log(`   accountStatus='approved', isAvailable=true, isSeedData=true`);
  console.log(`   Skills: all 13 types, Districts: all 30 Karnataka districts\n`);
}

main().catch(err => {
  console.error('\n❌ Fatal:', err.message || err);
  process.exit(1);
});
