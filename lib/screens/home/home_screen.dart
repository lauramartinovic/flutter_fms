// lib/screens/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_fms/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Import for User object

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Get the current user from Firebase Auth, can be null if state hasn't updated yet
    final User? user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('FMS App Home'),
        foregroundColor: Colors.white,
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
                // TODO: Navigate to FMS Capture / History screens
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Implement FMS features here!')),
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
          ],
        ),
      ),
    );
  }
}
