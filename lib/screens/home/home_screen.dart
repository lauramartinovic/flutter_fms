// lib/screens/home/home_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_fms/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_fms/screens/fms_capture/fms_capture_screen.dart'; // Import your FMS Capture Screen
import 'package:camera/camera.dart'; // Needed for availableCameras()
import 'package:flutter_fms/screens/history/history_screen.dart'; // <--- ADD THIS IMPORT

class HomeScreen extends StatelessWidget {
  final List<CameraDescription> cameras; // Pass cameras from main.dart

  const HomeScreen({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('FMS App Home'),
        foregroundColor: Colors.white, // Ensure app bar icons/text are visible
        actions: <Widget>[
          TextButton.icon(
            icon: const Icon(Icons.person),
            label: const Text('Logout'),
            onPressed: () async {
              await AuthService().signOut();
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'Welcome, ${user?.email ?? 'Guest'}!',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            const Text(
              'You are now logged in.',
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                // Navigate to FMS Capture Screen
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => FMSCaptureScreen(cameras: cameras),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 30,
                  vertical: 15,
                ),
              ),
              child: const Text(
                'Start FMS Session',
                style: TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(height: 20), // Added spacing
            ElevatedButton( // <--- NEW HISTORY BUTTON
              onPressed: () {
                // Navigate to History Screen
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const HistoryScreen(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 30,
                  vertical: 15,
                ),
              ),
              child: const Text(
                'View Session History',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
