import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show FlutterError, PlatformDispatcher;

import 'package:flutter_fms/screens/auth/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Globalni error handleri (korisno u releaseu)
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    // tu možeš poslati log u Crashlytics/Sentry ako koristiš
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    // isto — logiranje u crash alat
    return false; // false = pusti dalje default handler
  };

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  List<CameraDescription> cameras = const [];
  try {
    cameras = await availableCameras();
  } catch (e) {
    // Ako enumeracija kamera padne (npr. nema dozvole), app i dalje radi
    debugPrint('availableCameras() failed: $e');
  }

  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5B6CFF)),
      useMaterial3: true,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FMS Trainer',
      theme: base.copyWith(
        appBarTheme: base.appBarTheme.copyWith(
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: base.colorScheme.onSurface,
          ),
        ),
        cardTheme: base.cardTheme.copyWith(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(shape: const StadiumBorder()),
        ),
      ),
      home: AuthGate(cameras: cameras), // sve kao kod tebe
    );
  }
}
