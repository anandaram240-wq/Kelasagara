class KarnatakaLocation {
  static const Map<String, List<String>> districtTaluks = {
    'Bengaluru Urban': ['Bengaluru North', 'Bengaluru South', 'Bengaluru East', 'Yelahanka', 'Rajarajeshwari Nagar'],
    'Bengaluru Rural': ['Devanahalli', 'Doddaballapur', 'Hoskote', 'Nelamangala'],
    'Mysuru': ['Mysuru', 'Nanjangud', 'H.D.Kote', 'Hunsur', 'K.R.Nagar', 'Periyapatna', 'T.Narasipur'],
    'Hassan': ['Hassan', 'Alur', 'Arkalgud', 'Arsikere', 'Belur', 'Channarayapatna', 'Holenarasipura', 'Sakaleshapura'],
    'Shivamogga': ['Shivamogga', 'Bhadravati', 'Sagar', 'Hosanagara', 'Shikaripura', 'Soraba', 'Tirthahalli'],
    'Dakshina Kannada': ['Mangaluru', 'Bantval', 'Belthangady', 'Sulya', 'Puttur', 'Kadaba'],
    'Udupi': ['Udupi', 'Kundapura', 'Karkala', 'Brahmavar'],
    'Dharwad': ['Dharwad', 'Hubli', 'Kalghatgi', 'Navalgund', 'Kundgol'],
    'Belagavi': ['Belagavi', 'Athani', 'Bailhongal', 'Chikkodi', 'Gokak', 'Khanapur', 'Raibag', 'Savadatti'],
    'Vijayapura': ['Vijayapura', 'Basavana Bagevadi', 'Muddebihal', 'Sindagi', 'Indi'],
    'Kalaburagi': ['Kalaburagi', 'Afzalpur', 'Aland', 'Chincholi', 'Chittapur', 'Jevargi', 'Sedam', 'Yadgir'],
    'Raichur': ['Raichur', 'Deodurga', 'Lingsugur', 'Manvi', 'Sindhanur'],
    'Ballari': ['Ballari', 'Hadagali', 'Hospet', 'Kudligi', 'Sandur', 'Siraguppa'],
    'Tumakuru': ['Tumakuru', 'Chikkanayakanahalli', 'Gubbi', 'Madhugiri', 'Pavagada', 'Sira', 'Tiptur', 'Turuvekere'],
    'Chitradurga': ['Chitradurga', 'Challakere', 'Hiriyur', 'Holalkere', 'Hosadurga', 'Molakalmuru'],
    'Davangere': ['Davangere', 'Channagiri', 'Harihara', 'Honnali', 'Jagalur'],
    'Haveri': ['Haveri', 'Byadagi', 'Hanagal', 'Hirekerur', 'Ranibennur', 'Savanur', 'Shiggaon'],
    'Gadag': ['Gadag', 'Mundargi', 'Nargund', 'Ron', 'Shirhatti'],
    'Uttara Kannada': ['Karwar', 'Ankola', 'Bhatkal', 'Haliyal', 'Joida', 'Kumta', 'Mundgod', 'Sirsi', 'Siddapur'],
    'Chikkamagaluru': ['Chikkamagaluru', 'Kadur', 'Koppa', 'Mudigere', 'NR Pura', 'Sringeri', 'Tarikere'],
    'Kodagu': ['Madikeri', 'Somvarpet', 'Virajpet'],
    'Mandya': ['Mandya', 'Krishnarajapete', 'Maddur', 'Malavalli', 'Nagamangala', 'Pandavapura', 'Srirangapatna'],
    'Chikkaballapur': ['Chikkaballapur', 'Bagepalli', 'Chintamani', 'Gauribidanur', 'Gudibanda', 'Sidlaghatta'],
    'Kolar': ['Kolar', 'Bangarpet', 'Malur', 'Mulbagal', 'Srinivaspura'],
    'Ramanagara': ['Ramanagara', 'Channapatna', 'Kanakapura', 'Magadi'],
    'Yadgir': ['Yadgir', 'Raichur', 'Shorapur', 'Gurmitkal'],
    'Bidar': ['Bidar', 'Aurad', 'Basavakalyan', 'Bhalki', 'Humnabad'],
    'Koppal': ['Koppal', 'Gangavathi', 'Kustagi', 'Yelburga'],
    'Chamarajanagar': ['Chamarajanagar', 'Gundlupet', 'Kollegal', 'Yelandur'],
    'Vijayanagara': ['Hospet', 'Hagaribommanahalli', 'Kottur', 'Kudligi', 'Harapanahalli'],
    'Bagalkot': ['Bagalkot', 'Badami', 'Bilagi', 'Hungund', 'Jamkhandi', 'Mudhol'],
  };

  static List<String> get allDistricts => districtTaluks.keys.toList()..sort();
  static List<String> taluksForDistrict(String district) =>
    districtTaluks[district] ?? [];
}
