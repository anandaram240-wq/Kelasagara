// scripts/reseed_workers_correct.js
// Deletes all isSeedData==true workers then seeds 2,314 workers:
// 1 per skill × per taluk × all 31 Karnataka districts
// District and taluk names match karnataka_locations.dart exactly.

const https = require('https');
const auth  = require('/usr/local/lib/node_modules/firebase-tools/lib/auth');
const api   = require('/usr/local/lib/node_modules/firebase-tools/lib/api');

const PROJECT_ID = 'kelasagara-f127a';
const DB_PATH    = `projects/${PROJECT_ID}/databases/(default)/documents`;

// ── Canonical district → taluks (matches karnataka_locations.dart exactly) ──
const DISTRICT_TALUKS = {
  'Bengaluru Urban':  ['Bengaluru North','Bengaluru South','Bengaluru East','Yelahanka','Rajarajeshwari Nagar'],
  'Bengaluru Rural':  ['Devanahalli','Doddaballapur','Hoskote','Nelamangala'],
  'Mysuru':           ['Mysuru','Nanjangud','H.D.Kote','Hunsur','K.R.Nagar','Periyapatna','T.Narasipur'],
  'Hassan':           ['Hassan','Alur','Arkalgud','Arsikere','Belur','Channarayapatna','Holenarasipura','Sakaleshapura'],
  'Shivamogga':       ['Shivamogga','Bhadravati','Sagar','Hosanagara','Shikaripura','Soraba','Tirthahalli'],
  'Dakshina Kannada': ['Mangaluru','Bantval','Belthangady','Sulya','Puttur','Kadaba'],
  'Udupi':            ['Udupi','Kundapura','Karkala','Brahmavar'],
  'Dharwad':          ['Dharwad','Hubli','Kalghatgi','Navalgund','Kundgol'],
  'Belagavi':         ['Belagavi','Athani','Bailhongal','Chikkodi','Gokak','Khanapur','Raibag','Savadatti'],
  'Vijayapura':       ['Vijayapura','Basavana Bagevadi','Muddebihal','Sindagi','Indi'],
  'Kalaburagi':       ['Kalaburagi','Afzalpur','Aland','Chincholi','Chittapur','Jevargi','Sedam','Yadgir'],
  'Raichur':          ['Raichur','Deodurga','Lingsugur','Manvi','Sindhanur'],
  'Ballari':          ['Ballari','Hadagali','Hospet','Kudligi','Sandur','Siraguppa'],
  'Tumakuru':         ['Tumakuru','Chikkanayakanahalli','Gubbi','Madhugiri','Pavagada','Sira','Tiptur','Turuvekere'],
  'Chitradurga':      ['Chitradurga','Challakere','Hiriyur','Holalkere','Hosadurga','Molakalmuru'],
  'Davangere':        ['Davangere','Channagiri','Harihara','Honnali','Jagalur'],
  'Haveri':           ['Haveri','Byadagi','Hanagal','Hirekerur','Ranibennur','Savanur','Shiggaon'],
  'Gadag':            ['Gadag','Mundargi','Nargund','Ron','Shirhatti'],
  'Uttara Kannada':   ['Karwar','Ankola','Bhatkal','Haliyal','Joida','Kumta','Mundgod','Sirsi','Siddapur'],
  'Chikkamagaluru':   ['Chikkamagaluru','Kadur','Koppa','Mudigere','NR Pura','Sringeri','Tarikere'],
  'Kodagu':           ['Madikeri','Somvarpet','Virajpet'],
  'Mandya':           ['Mandya','Krishnarajapete','Maddur','Malavalli','Nagamangala','Pandavapura','Srirangapatna'],
  'Chikkaballapur':   ['Chikkaballapur','Bagepalli','Chintamani','Gauribidanur','Gudibanda','Sidlaghatta'],
  'Kolar':            ['Kolar','Bangarpet','Malur','Mulbagal','Srinivaspura'],
  'Ramanagara':       ['Ramanagara','Channapatna','Kanakapura','Magadi'],
  'Yadgir':           ['Yadgir','Raichur','Shorapur','Gurmitkal'],
  'Bidar':            ['Bidar','Aurad','Basavakalyan','Bhalki','Humnabad'],
  'Koppal':           ['Koppal','Gangavathi','Kustagi','Yelburga'],
  'Chamarajanagar':   ['Chamarajanagar','Gundlupet','Kollegal','Yelandur'],
  'Vijayanagara':     ['Hospet','Hagaribommanahalli','Kottur','Kudligi','Harapanahalli'],
  'Bagalkot':         ['Bagalkot','Badami','Bilagi','Hungund','Jamkhandi','Mudhol'],
};

// ── Taluk HQ coordinates (lat, lng) ──────────────────────────────────────────
const TALUK_COORDS = {
  'Bengaluru North':[13.1000,77.5970],'Bengaluru South':[12.9166,77.6010],
  'Bengaluru East':[12.9800,77.7000],'Yelahanka':[13.1000,77.5930],
  'Rajarajeshwari Nagar':[12.9200,77.5200],
  'Devanahalli':[13.2490,77.7120],'Doddaballapur':[13.2950,77.5370],
  'Hoskote':[13.0700,77.7980],'Nelamangala':[13.1050,77.3960],
  'Mysuru':[12.2958,76.6394],'Nanjangud':[12.1167,76.6833],
  'H.D.Kote':[12.0500,76.3300],'Hunsur':[12.3000,76.2900],
  'K.R.Nagar':[12.4200,76.1200],'Periyapatna':[12.3300,76.0100],
  'T.Narasipur':[12.2100,76.9000],
  'Hassan':[13.0069,76.0996],'Alur':[13.0000,75.9500],
  'Arkalgud':[12.7700,76.0700],'Arsikere':[13.3100,76.2500],
  'Belur':[13.1600,75.8700],'Channarayapatna':[12.9000,76.3900],
  'Holenarasipura':[13.0000,76.2400],'Sakaleshapura':[12.9200,75.7800],
  'Shivamogga':[13.9299,75.5681],'Bhadravati':[13.8500,75.7100],
  'Sagar':[14.1700,75.0300],'Hosanagara':[13.9000,75.0500],
  'Shikaripura':[14.2700,75.3600],'Soraba':[14.0000,75.0800],
  'Tirthahalli':[13.6900,75.2500],
  'Mangaluru':[12.8698,74.8431],'Bantval':[12.9000,75.0400],
  'Belthangady':[13.0200,75.3000],'Sulya':[12.5600,75.3800],
  'Puttur':[12.7600,75.2000],'Kadaba':[12.7700,75.1200],
  'Udupi':[13.3409,74.7421],'Kundapura':[13.6300,74.6900],
  'Karkala':[13.2100,74.9900],'Brahmavar':[13.4300,74.7600],
  'Dharwad':[15.4589,75.0078],'Hubli':[15.3647,75.1240],
  'Kalghatgi':[15.1800,74.9600],'Navalgund':[15.5700,75.3700],
  'Kundgol':[15.2500,75.2500],
  'Belagavi':[15.8497,74.4977],'Athani':[16.7200,75.0600],
  'Bailhongal':[15.8100,74.9900],'Chikkodi':[16.4300,74.5900],
  'Gokak':[16.1700,74.8300],'Khanapur':[15.6400,74.5000],
  'Raibag':[16.4900,74.7700],'Savadatti':[15.7600,75.1200],
  'Vijayapura':[16.8302,75.7100],'Basavana Bagevadi':[16.5800,75.9700],
  'Muddebihal':[16.3300,76.1300],'Sindagi':[16.9200,76.2400],
  'Indi':[17.1800,75.9600],
  'Kalaburagi':[17.3297,76.8200],'Afzalpur':[17.2000,76.3600],
  'Aland':[17.5600,76.5700],'Chincholi':[17.4600,77.4200],
  'Chittapur':[17.1200,77.0800],'Jevargi':[17.0100,76.7800],
  'Sedam':[17.1700,77.2900],
  'Raichur':[16.2120,77.3600],'Deodurga':[16.4900,76.9800],
  'Lingsugur':[16.1700,76.5200],'Manvi':[15.9900,77.0500],
  'Sindhanur':[15.7700,76.7600],
  'Ballari':[15.1394,76.9214],'Hadagali':[15.0100,76.0000],
  'Hospet':[15.2700,76.3900],'Kudligi':[14.9000,76.3800],
  'Sandur':[15.0900,76.5500],'Siraguppa':[15.6300,76.9000],
  'Tumakuru':[13.3400,77.1000],'Chikkanayakanahalli':[13.1300,76.6200],
  'Gubbi':[13.3100,76.9400],'Madhugiri':[13.6600,77.2100],
  'Pavagada':[14.1000,77.2800],'Sira':[13.7400,76.9000],
  'Tiptur':[13.2600,76.4800],'Turuvekere':[13.1600,76.6600],
  'Chitradurga':[14.2300,76.4000],'Challakere':[14.3100,76.6500],
  'Hiriyur':[13.9400,76.6200],'Holalkere':[14.0400,76.1900],
  'Hosadurga':[13.8100,76.2800],'Molakalmuru':[14.7100,76.7600],
  'Davangere':[14.4644,75.9218],'Channagiri':[14.0200,75.9300],
  'Harihara':[14.5200,75.7300],'Honnali':[14.2400,75.6500],
  'Jagalur':[14.5200,76.3400],
  'Haveri':[14.7939,75.4041],'Byadagi':[14.6700,75.4900],
  'Hanagal':[14.4600,75.1000],'Hirekerur':[14.4600,75.4000],
  'Ranibennur':[14.6100,75.6200],'Savanur':[14.9700,75.3400],
  'Shiggaon':[15.0600,75.2700],
  'Gadag':[15.4298,75.6200],'Mundargi':[15.2000,75.8800],
  'Nargund':[15.7200,75.3900],'Ron':[15.7000,75.7600],
  'Shirhatti':[15.2300,75.5800],
  'Karwar':[14.8000,74.1300],'Ankola':[14.6600,74.3000],
  'Bhatkal':[13.9700,74.5600],'Haliyal':[15.3300,74.7600],
  'Joida':[15.3600,74.4300],'Kumta':[14.4300,74.4200],
  'Mundgod':[14.9700,75.0300],'Sirsi':[14.6200,74.8400],
  'Siddapur':[14.3500,74.8900],
  'Chikkamagaluru':[13.3153,75.7754],'Kadur':[13.5500,76.0100],
  'Koppa':[13.5300,75.3600],'Mudigere':[13.1400,75.6400],
  'NR Pura':[13.2500,75.4000],'Sringeri':[13.4200,75.2600],
  'Tarikere':[13.7100,75.8100],
  'Madikeri':[12.4200,75.7400],'Somvarpet':[12.5900,75.8800],
  'Virajpet':[12.1900,75.8100],
  'Mandya':[12.5218,76.8951],'Krishnarajapete':[12.6600,76.4900],
  'Maddur':[12.5800,77.0400],'Malavalli':[12.4700,77.0600],
  'Nagamangala':[12.8200,76.7600],'Pandavapura':[12.7000,76.6800],
  'Srirangapatna':[12.4200,76.9000],
  'Chikkaballapur':[13.4355,77.7315],'Bagepalli':[13.7800,77.7900],
  'Chintamani':[13.4000,78.0500],'Gauribidanur':[13.6100,77.5200],
  'Gudibanda':[13.9000,78.0000],'Sidlaghatta':[13.3900,77.8600],
  'Kolar':[13.1360,78.1290],'Bangarpet':[12.9900,78.1800],
  'Malur':[13.0000,77.9400],'Mulbagal':[13.1600,78.3900],
  'Srinivaspura':[13.3400,78.2100],
  'Ramanagara':[12.7200,77.2800],'Channapatna':[12.6500,77.2100],
  'Kanakapura':[12.5500,77.4200],'Magadi':[12.9600,77.2200],
  'Yadgir':[16.7700,77.1300],'Shorapur':[16.5200,76.7600],
  'Gurmitkal':[16.8700,77.3000],
  'Bidar':[17.9133,77.5199],'Aurad':[17.5900,77.5800],
  'Basavakalyan':[17.8700,76.9500],'Bhalki':[18.0500,76.6800],
  'Humnabad':[17.7600,76.9800],
  'Koppal':[15.3500,76.1600],'Gangavathi':[15.4300,76.5300],
  'Kustagi':[15.7500,76.0100],'Yelburga':[15.6200,76.0000],
  'Chamarajanagar':[11.9200,76.9400],'Gundlupet':[11.8100,76.6900],
  'Kollegal':[12.1600,77.1100],'Yelandur':[12.0600,77.0400],
  'Hagaribommanahalli':[15.0600,76.2300],'Kottur':[15.0600,76.0000],
  'Harapanahalli':[14.8000,75.9900],
  'Bagalkot':[16.1800,75.7000],'Badami':[15.9200,75.6800],
  'Bilagi':[16.3500,75.8700],'Hungund':[16.0500,76.0600],
  'Jamkhandi':[16.9700,75.3100],'Mudhol':[16.3500,75.2800],
};

const SKILLS = ['plumber','electrician','mason','carpenter','painter','driver','cook','cleaner','gardener','security','tailor','welder','helper'];
const DAILY_RATE_BY_SKILL = {
  plumber:700,electrician:800,mason:750,carpenter:800,painter:650,driver:700,
  cook:600,cleaner:550,gardener:550,security:650,tailor:600,welder:850,helper:500
};

const FIRST_NAMES = ['Ravi','Suresh','Mahesh','Ramesh','Ganesh','Umesh','Priya','Suma','Kavya','Anitha','Sunitha','Rekha',
  'Kumar','Prakash','Mohan','Srinivas','Bhaskar','Ashok','Shiva','Kiran','Pushpa','Savitha','Radha','Usha','Meena',
  'Abdul','Mohammed','Imran','Farooq','Saleem','Fatima','Ayesha','Zainab','Nusrath','Shabana',
  'Thomas','Joseph','Francis','Peter','Paul','Mary','Grace','Stella','Regina','Sonia',
  'Chetan','Harish','Naveen','Deepak','Santosh','Vijay','Sunil','Manoj','Manjula','Saritha',
  'Rajkumar','Muniraj','Basavaraj','Laxman','Manjunath','Channappa','Thimmaiah','Siddaraju',
  'Shwetha','Parvathi','Nirmala','Jayamma','Lakshmi','Vimala','Geetha','Latha'];
const LAST_NAMES = ['Gowda','Naik','Shetty','Poojari','Hegde','Nair','Pillai','Patil','Kulkarni','Desai',
  'Gupta','Sharma','Verma','Raju','Reddy','Rao','Iyer','Naidu','Menon','Prabhu',
  "D'Souza",'Fernandes','Pinto','Rodrigues','Sequeira','Lobo','Mascarenhas',
  'Khan','Hussain','Shaikh','Ansari','Mirza','Malik','Siddiqui',
  'Devadiga','Bangera','Kunder','Salian','Kamath','Bhat','Pai','Ganiga','Nayak','Gaonkar',
  'Rajput','Pandey','Tiwari','Mishra','Dubey','Shukla','Singh','Patel','Shah','More',
  'Vishwakarma','Kammara','Lamani','Kuruba','Iyer','Chetty','Mudaliar'];

function randInt(min, max) { return Math.floor(Math.random()*(max-min+1))+min; }
function randFloat(min, max) { return min+Math.random()*(max-min); }
function pick(arr) { return arr[Math.floor(Math.random()*arr.length)]; }
function jitter(val, km) { return val+(Math.random()-0.5)*2*km/111.0; }

const MALE_NAMES = new Set(['Ravi','Suresh','Mahesh','Ramesh','Ganesh','Umesh','Kumar','Prakash','Mohan','Srinivas','Bhaskar','Ashok','Shiva','Kiran',
  'Abdul','Mohammed','Imran','Farooq','Saleem','Thomas','Joseph','Francis','Peter','Paul','Chetan','Harish','Naveen','Deepak','Santosh','Vijay','Sunil','Manoj',
  'Rajkumar','Muniraj','Basavaraj','Laxman','Manjunath','Channappa','Thimmaiah','Siddaraju']);

async function getAccessToken() {
  const acct = auth.getGlobalDefaultAccount();
  const body = new URLSearchParams({
    client_id:api.clientId(), client_secret:api.clientSecret(),
    refresh_token:acct.tokens.refresh_token, grant_type:'refresh_token',
  }).toString();
  return new Promise((resolve,reject) => {
    const req = https.request({
      hostname:'oauth2.googleapis.com',path:'/token',method:'POST',
      headers:{'Content-Type':'application/x-www-form-urlencoded','Content-Length':Buffer.byteLength(body)},
    },(res) => {
      let d=''; res.on('data',c=>d+=c);
      res.on('end',()=>{ const r=JSON.parse(d); r.access_token?resolve(r.access_token):reject(r); });
    });
    req.write(body); req.end();
  });
}

function httpsPost(path, body, token) {
  return new Promise((resolve,reject) => {
    const b = JSON.stringify(body);
    const req = https.request({
      hostname:'firestore.googleapis.com',path,method:'POST',
      headers:{'Authorization':`Bearer ${token}`,'Content-Type':'application/json','Content-Length':Buffer.byteLength(b)},
    },(res) => {
      let d=''; res.on('data',c=>d+=c);
      res.on('end',()=>{ try{resolve(JSON.parse(d));}catch(e){resolve(d);} });
    });
    req.on('error',reject); req.write(b); req.end();
  });
}

function fv(v) {
  if (v===null||v===undefined) return {nullValue:null};
  if (typeof v==='boolean') return {booleanValue:v};
  if (typeof v==='number'&&Number.isInteger(v)) return {integerValue:String(v)};
  if (typeof v==='number') return {doubleValue:v};
  if (typeof v==='string') return {stringValue:v};
  if (Array.isArray(v)) return {arrayValue:{values:v.map(fv)}};
  if (v&&v.__ts) return {timestampValue:new Date().toISOString()};
  return {stringValue:String(v)};
}

function makeFields(obj) {
  return Object.fromEntries(Object.entries(obj).map(([k,v])=>[k,fv(v)]));
}

function makeWorker(district, taluk, skill) {
  const coords = TALUK_COORDS[taluk] || TALUK_COORDS[district] || [13.0,76.0];
  const lat = jitter(coords[0], randFloat(0.5, 5));
  const lng = jitter(coords[1], randFloat(0.5, 5));
  const totalJobs = randInt(0,25);
  const totalRatings = randInt(0,Math.min(totalJobs,6));
  const ratingSum = totalRatings * randFloat(3.0,5.0);
  const firstName = pick(FIRST_NAMES);
  const lastName  = pick(LAST_NAMES);
  return {
    name:`${firstName} ${lastName}`, displayName:`${firstName} ${lastName}`,
    gender: MALE_NAMES.has(firstName)?'male':'female',
    role:'worker', accountStatus:'approved', isAvailable:true, isSeedData:true,
    district, taluk,
    skills:[skill], primarySkill:skill,
    dailyRate: DAILY_RATE_BY_SKILL[skill]+randInt(-50,100),
    faceVerified:false, skillVerified:false,
    totalJobs, ratingSum, totalRatings,
    rating: totalRatings>0?ratingSum/totalRatings:0,
    discoveryLat:lat, discoveryLng:lng,
    discoveryUpdatedAt:{__ts:true},
    discoverySessionId:`seed_${district}_${taluk}_${skill}`.replace(/[^a-z0-9]/gi,'_').toLowerCase().substring(0,60),
    discoveryAccuracy:15.0, serviceRadiusKm:15,
    bio:`${skill.charAt(0).toUpperCase()+skill.slice(1)} worker in ${taluk}`,
    phone:`9${randInt(100000000,999999999)}`, email:'', photoUrl:'',
    createdAt:{__ts:true}, updatedAt:{__ts:true},
  };
}

// ── Step 1: Delete ────────────────────────────────────────────────────────────
async function deleteAll(token) {
  console.log('\n=== STEP 1: Deleting old seed workers ===');
  let deleted = 0;
  while (true) {
    const freshToken = await getAccessToken();
    const results = await httpsPost(`/v1/${DB_PATH}:runQuery`, {
      structuredQuery:{
        from:[{collectionId:'users'}],
        where:{fieldFilter:{field:{fieldPath:'isSeedData'},op:'EQUAL',value:{booleanValue:true}}},
        limit:500
      }
    }, freshToken);
    const docs = Array.isArray(results)?results.filter(r=>r.document):[];
    if (docs.length===0) break;
    const writes = docs.map(d=>({delete:d.document.name}));
    await httpsPost(`/v1/${DB_PATH}:batchWrite`, {writes}, freshToken);
    deleted += docs.length;
    process.stdout.write(`\r  Deleted: ${deleted}...`);
  }
  console.log(`\n  ✅ Deleted ${deleted} old seed workers.`);
}

// ── Step 2: Seed ──────────────────────────────────────────────────────────────
async function seedAll() {
  console.log('\n=== STEP 2: Seeding workers ===');
  const all = [];
  for (const [district, taluks] of Object.entries(DISTRICT_TALUKS)) {
    for (const taluk of taluks) {
      for (const skill of SKILLS) {
        all.push({district, taluk, skill});
      }
    }
  }
  console.log(`  Total to seed: ${all.length}`);

  const BATCH = 200;
  let seeded = 0;
  for (let i=0; i<all.length; i+=BATCH) {
    const batch = all.slice(i, i+BATCH);
    const freshToken = await getAccessToken();
    const writes = batch.map(({district, taluk, skill}) => {
      const docId = `seed_${district}_${taluk}_${skill}`.replace(/[^a-z0-9]/gi,'_').toLowerCase().substring(0,80);
      return {
        update: { name:`${DB_PATH}/users/${docId}`, fields:makeFields(makeWorker(district,taluk,skill)) }
      };
    });
    const res = await httpsPost(`/v1/${DB_PATH}:batchWrite`, {writes}, freshToken);
    const ok = res.writeResults ? res.writeResults.length : batch.length;
    seeded += ok;
    process.stdout.write(`\r  Seeded: ${seeded}/${all.length}`);
  }
  console.log(`\n  ✅ Seeded ${seeded} workers.`);
}

async function main() {
  const totalTaluks = Object.values(DISTRICT_TALUKS).reduce((a,b)=>a+b.length,0);
  console.log('=== Kelasagara Reseed ===');
  console.log(`Districts: ${Object.keys(DISTRICT_TALUKS).length}, Taluks: ${totalTaluks}, Skills: ${SKILLS.length}`);
  console.log(`Total workers to create: ${totalTaluks} × ${SKILLS.length} = ${totalTaluks*SKILLS.length}`);

  await deleteAll(await getAccessToken());
  await new Promise(r=>setTimeout(r,2000));
  await seedAll();
  console.log('\n=== DONE — All districts × taluks × skills covered ===');
}

main().catch(console.error);
