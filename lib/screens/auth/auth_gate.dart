import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Sakrij AuthProvider iz firebase_auth da ne kolidira s tvojim
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;

import 'package:flutter_fms/screens/app_shell.dart';
import 'package:flutter_fms/screens/auth/auth_screen.dart';

// Uvezi tvoju klasu s aliasom
import 'package:flutter_fms/providers/auth_provider.dart' as app_providers;

class AuthGate extends StatelessWidget {
  final List<CameraDescription> cameras;
  const AuthGate({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snap.data;
        if (user != null) {
          return AppShell(cameras: cameras);
        }

        // Omotaj AuthScreen u ChangeNotifierProvider za tvoj AuthProvider
        return ChangeNotifierProvider<app_providers.AuthProvider>(
          create: (_) => app_providers.AuthProvider(),
          child: const AuthScreen(),
        );
      },
    );
  }
}
