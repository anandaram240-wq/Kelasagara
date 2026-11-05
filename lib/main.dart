import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_text_styles.dart';
import 'providers/auth_provider.dart';
import 'providers/jobs_provider.dart';
import 'screens/splash/splash_screen.dart';
import 'services/firebase_service.dart';

import 'package:flutter/foundation.dart' show kIsWeb;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── FlutterForegroundTask — MUST be called before startService ───────────
  // Without this, startService() silently fails on Android 13+ (API 33+).
  // Not supported on web (dart:isolate unavailable).
  if (!kIsWeb) {
    FlutterForegroundTask.initCommunicationPort();
  }

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  // ── Firebase Init ────────────────────────────────────────────────────────
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'AIzaSyB9hVsgU6klVt2LdyQbYD2XJC86g3vlT_g',
        appId: '1:993968093461:android:42f54bccdefdbace47d11c',
        messagingSenderId: '993968093461',
        projectId: 'kelasagara-f127a',
        databaseURL: 'https://kelasagara-f127a-default-rtdb.asia-southeast1.firebasedatabase.app',
        storageBucket: 'kelasagara-f127a.firebasestorage.app',
      ),
    );

    // Enable RTDB offline persistence — survives momentary network drops
    // Not supported on web platform
    if (!kIsWeb) {
      FirebaseDatabase.instance.setPersistenceEnabled(true);
      FirebaseDatabase.instance.ref('liveTracking').keepSynced(false);
    }

    await FirebaseService.init();
    debugPrint('✅ Firebase connected: ${FirebaseService.isAvailable}');
  } catch (e) {
    debugPrint('⚠️ Firebase not available (demo mode): $e');
  }

  // Pre-warm font cache — forces Dart VM to resolve all TextStyle
  // static fields before the first frame (eliminates per-rebuild allocations).
  AppTextStyles.prewarm();

  runApp(const KelasaGaaraApp());
}

class KelasaGaaraApp extends StatelessWidget {
  const KelasaGaaraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..init()),
        ChangeNotifierProvider(create: (_) => JobsProvider()),
        // JourneyProvider is per-screen: created fresh for each tracking session.
        // Use ChangeNotifierProvider at the navigation push site, not globally.
      ],
      child: MaterialApp(
        title: 'ಕೆಲಸಗಾರ',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const SplashScreen(),
      ),
    );
  }
}

