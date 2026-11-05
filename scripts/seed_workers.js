// scripts/seed_workers.js
// Seed 1000 synthetic Karnataka worker documents into Firestore.
// - accountStatus: 'approved' (no admin approval needed for seed)
// - isSeedData: true (for easy cleanup later)
// - All other fields required by voice search + WorkerDiscoveryService
//
// Usage:
//   GOOGLE_APPLICATION_CREDENTIALS=path/to/serviceAccount.json node seed_workers.js

// firebase-admin v12+ modular API
const { initializeApp, cert, applicationDefault } = require('firebase-admin/app');
const { getFirestore, Timestamp, FieldValue } = require('firebase-admin/firestore');
const crypto = require('crypto');

// ── District → centre coordinates ──────────────────────────────────────────
const DISTRICTS = [
  { name: 'Bengaluru Urban',   lat: 12.9716, lng: 77.5946, weight: 80 },
  { name: 'Mysuru',            lat: 12.2958, lng: 76.6394, weight: 40 },
  { name: 'Mangaluru',         lat: 12.9141, lng: 74.8560, weight: 35 },
  { name: 'Hubballi',          lat: 15.3647, lng: 75.1240, weight: 30 },
  { name: 'Belagavi',          lat: 15.8497, lng: 74.4977, weight: 30 },
  { name: 'Kalaburagi',        lat: 17.3297, lng: 76.8200, weight: 25 },
  { name: 'Shivamogga',        lat: 13.9299, lng: 75.5681, weight: 25 },
  { name: 'Tumakuru',          lat: 13.3379, lng: 77.1173, weight: 25 },
  { name: 'Ballari',           lat: 15.1394, lng: 76.9214, weight: 20 },
  { name: 'Vijayapura',        lat: 16.8302, lng: 75.7100, weight: 20 },
  { name: 'Hassan',            lat: 13.0068, lng: 76.1004, weight: 20 },
  { name: 'Mandya',            lat: 12.5218, lng: 76.8951, weight: 20 },
  { name: 'Davangere',         lat: 14.4644, lng: 75.9218, weight: 20 },
  { name: 'Udupi',             lat: 13.3409, lng: 74.7421, weight: 20 },
  { name: 'Raichur',           lat: 16.2120, lng: 77.3439, weight: 18 },
  { name: 'Chikkamagaluru',    lat: 13.3161, lng: 75.7720, weight: 18 },
  { name: 'Bagalkot',          lat: 16.1826, lng: 75.6965, weight: 15 },
  { name: 'Dakshina Kannada',  lat: 12.8438, lng: 75.2479, weight: 15 },
  { name: 'Bidar',             lat: 17.9104, lng: 77.5199, weight: 15 },
  { name: 'Koppal',            lat: 15.3590, lng: 76.1547, weight: 12 },
  { name: 'Gadag',             lat: 15.4283, lng: 75.6317, weight: 12 },
  { name: 'Uttara Kannada',    lat: 14.7947, lng: 74.4977, weight: 12 },
  { name: 'Kodagu',            lat: 12.4244, lng: 75.7382, weight: 12 },
  { name: 'Chitradurga',       lat: 14.2251, lng: 76.3981, weight: 12 },
  { name: 'Chikkaballapur',    lat: 13.4355, lng: 77.7315, weight: 12 },
  { name: 'Ramanagara',        lat: 12.7157, lng: 77.2810, weight: 12 },
  { name: 'Yadgir',            lat: 16.7689, lng: 77.1380, weight: 10 },
  { name: 'Chamarajanagar',    lat: 11.9216, lng: 76.9428, weight: 10 },
  { name: 'Haveri',            lat: 14.7961, lng: 75.3988, weight: 10 },
  { name: 'Bengaluru Rural',   lat: 13.1596, lng: 77.5791, weight: 10 },
];

// Build weighted district pool (total = ~700 slots)
const DISTRICT_POOL = [];
for (const d of DISTRICTS) {
  for (let i = 0; i < d.weight; i++) DISTRICT_POOL.push(d);
}

// ── Skills + daily rate ranges ──────────────────────────────────────────────
const SKILLS = [
  { id: 'plumber',     minRate: 700,  maxRate: 1400 },
  { id: 'electrician', minRate: 800,  maxRate: 1600 },
  { id: 'mason',       minRate: 700,  maxRate: 1300 },
  { id: 'carpenter',   minRate: 700,  maxRate: 1400 },
  { id: 'painter',     minRate: 600,  maxRate: 1200 },
  { id: 'driver',      minRate: 700,  maxRate: 1500 },
  { id: 'cook',        minRate: 500,  maxRate: 1100 },
  { id: 'cleaner',     minRate: 400,  maxRate:  900 },
  { id: 'gardener',    minRate: 400,  maxRate:  900 },
  { id: 'security',    minRate: 500,  maxRate: 1000 },
  { id: 'tailor',      minRate: 500,  maxRate: 1100 },
  { id: 'welder',      minRate: 800,  maxRate: 1500 },
  { id: 'helper',      minRate: 400,  maxRate:  700 },
];

// ── Name pools ──────────────────────────────────────────────────────────────
const MALE_FIRST = [
  'Rajesh','Suresh','Ramesh','Mahesh','Ganesh','Nagaraj','Shivaraj','Venkatesh',
  'Ravi','Srinivas','Manjunath','Prakash','Basavraj','Mohammed','Abdul','Ibrahim',
  'Salim','Arun','Deepak','Santosh','Anthony','Joseph','Rajkumar','Lokesh',
  'Prashanth','Praveen','Nagesh','Ashok','Kiran','Naveen','Harish','Vijay',
  'Sunil','Mohan','Girish','Umesh','Satish','Dinesh','Anand','Rakesh',
  'Imran','Faizal','Shaikh','Arjun','Bhuvanesh','Chetan','Dhananjay','Eknath',
  'Siddesh','Muniraj','Haneef','Shahid','Yusuf','Thomas','Francis','Benny',
];

const FEMALE_FIRST = [
  'Lakshmi','Savitha','Rekha','Sunitha','Usha','Geetha','Manjula','Shobha',
  'Fatima','Ayesha','Mary','Kavitha','Radha','Vimala','Pushpa','Meena',
  'Suma','Anitha','Jayamma','Roopa','Nandini','Bhavana','Shwetha','Divya',
  'Zainab','Hameeda','Regina','Lissy','Chandrakala','Parvathi',
];

const SURNAMES = [
  'Kumar','Gowda','Reddy','Naidu','Sharma','Khan','Patel','Nair','Rao','Patil',
  'Hegde','Shetty','D\'Souza','Sequeira','Siddiqui','Verma','Iyer','Pillai',
  'Bhat','Kamath','Joshi','Kulkarni','More','Shinde','Gupta','Singh',
  'Swamy','Raju','Babu','Naik','Poojari','Gaonkar','Devadiga','Kunder',
];

const VERIFICATION_LEVELS = [
  'practicalVerified','basicAssessed','experienced','advanced',
];

// ── Helpers ─────────────────────────────────────────────────────────────────
function pick(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

function randInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function randFloat(min, max, dp = 4) {
  return parseFloat((Math.random() * (max - min) + min).toFixed(dp));
}

function jitter(centre, rangeKm) {
  // ~0.009 deg per km
  const deg = (rangeKm / 111.0) * (Math.random() * 2 - 1);
  return centre + deg;
}

function weightedDistrict() {
  return DISTRICT_POOL[Math.floor(Math.random() * DISTRICT_POOL.length)];
}

// ── Build 1000 worker documents ─────────────────────────────────────────────
function buildWorkers(count = 1000) {
  const workers = [];
  const skillCycle = [];
  // Ensure every skill gets at least ~76 workers (1000/13 ≈ 77)
  for (let i = 0; i < count; i++) {
    skillCycle.push(SKILLS[i % SKILLS.length]);
  }
  // Shuffle skill cycle for random distribution
  for (let i = skillCycle.length - 1; i > 0; i--) {
    const j = randInt(0, i);
    [skillCycle[i], skillCycle[j]] = [skillCycle[j], skillCycle[i]];
  }

  for (let i = 0; i < count; i++) {
    const isMale = Math.random() < 0.72; // Karnataka workforce is ~72% male
    const firstName = isMale ? pick(MALE_FIRST) : pick(FEMALE_FIRST);
    const surname = pick(SURNAMES);
    const name = `${firstName} ${surname}`;

    const district = weightedDistrict();
    const skill = skillCycle[i];

    // Jitter lat/lng up to 8km from district centre (realistic spread within district)
    const lat = parseFloat(jitter(district.lat, 8).toFixed(5));
    const lng = parseFloat(jitter(district.lng, 8).toFixed(5));

    const totalJobs = randInt(0, 220);
    const rating = randFloat(3.2, 5.0, 1);
    const totalRatings = totalJobs > 0 ? randInt(0, Math.min(totalJobs, 80)) : 0;
    const ratingSum = parseFloat((rating * totalRatings).toFixed(1));
    const dailyRate = randInt(skill.minRate, skill.maxRate);
    const verificationLevel = pick(VERIFICATION_LEVELS);

    // discoveryUpdatedAt — random time in last 4 hours (fresh enough for voice search)
    const now = Date.now();
    const discoveryUpdatedAt = Timestamp.fromMillis(
      now - randInt(0, 4 * 60 * 60 * 1000)
    );

    workers.push({
      // Identity
      name,
      displayName: name,
      role: 'worker',
      gender: isMale ? 'male' : 'female',
      phone: `+91${randInt(6000000000, 9999999999)}`,
      email: `${firstName.toLowerCase()}${randInt(10,999)}@example.com`,

      // Account status — seed bypass (no approval needed)
      accountStatus: 'approved',
      isAvailable: true,
      faceVerified: false,
      skillVerified: false,
      verificationLevel,

      // Location
      district: district.name,
      taluk: district.name,  // simplified: district name as taluk
      lat,
      lng,

      // Discovery fields (what voice search queries)
      discoveryLat: lat,
      discoveryLng: lng,
      discoveryUpdatedAt,
      discoverySessionId: `seed_${crypto.randomBytes(8).toString('hex')}`,
      discoveryAccuracy: randFloat(5.0, 40.0, 1),
      serviceRadiusKm: pick([10, 15, 20, 25, 30]),

      // Skills
      skills: [skill.id],
      primarySkill: skill.id,

      // Work history
      totalJobs,
      completedJobs: totalJobs,
      rating,
      ratingSum,
      totalRatings,
      dailyRate,

      // Flags
      isSeedData: true,  // for easy cleanup
      profileImageUrl: null,
      bio: '',

      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  return workers;
}

// ── Upload in batches of 400 (safe under Firestore 500/batch limit) ───────────
async function seedFirestore(projectId) {
  const db = getFirestore();
  const workers = buildWorkers(1000);

  console.log(`\n✅ Generated ${workers.length} worker documents.`);
  console.log(`📤 Uploading to Firestore project: ${projectId} ...\n`);

  const BATCH_SIZE = 400;
  let uploaded = 0;

  for (let i = 0; i < workers.length; i += BATCH_SIZE) {
    const chunk = workers.slice(i, i + BATCH_SIZE);
    const batch = db.batch();
    for (const w of chunk) {
      const ref = db.collection('users').doc(); // auto-generated ID
      batch.set(ref, w);
    }
    await batch.commit();
    uploaded += chunk.length;
    console.log(`  ✓ Uploaded ${uploaded}/${workers.length} workers...`);
  }

  console.log(`\n🎉 Done! ${uploaded} seed workers added to Firestore collection 'users'.`);
  console.log(`   All have accountStatus='approved', isAvailable=true, isSeedData=true.`);
  console.log(`   To delete later: query users where isSeedData == true and delete.\n`);
}

// ── Main ─────────────────────────────────────────────────────────────────────
async function main() {
  const PROJECT_ID = 'kelasagara-f127a';

  // The firebase CLI stores OAuth2 user credentials — use applicationDefault()
  const credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (credPath) {
    console.log(`Using ADC from: ${credPath}`);
  } else {
    console.log(`Using system Application Default Credentials...`);
  }

  initializeApp({
    credential: applicationDefault(),
    projectId: PROJECT_ID,
  });

  try {
    await seedFirestore(PROJECT_ID);
    process.exit(0);
  } catch (err) {
    console.error('\n❌ Error uploading to Firestore:', err.message || err);
    if (err.code === 16 || (err.message && err.message.includes('credential'))) {
      console.error('\n🔑 Auth failed. Try: firebase login --reauth');
    }
    process.exit(1);
  }
}

main();
