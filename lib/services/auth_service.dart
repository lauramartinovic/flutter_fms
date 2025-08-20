// lib/services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Stream to listen to authentication state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Register with Email and Password
  Future<User?> registerWithEmailAndPassword(
    String email,
    String password,
  ) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return result.user;
    } on FirebaseAuthException catch (e) {
      // Handle common FirebaseAuth exceptions and re-throw for UI to display
      throw _getAuthErrorMessage(e.code);
    } catch (e) {
      throw 'An unexpected error occurred: ${e.toString()}';
    }
  }

  // Sign In with Email and Password
  Future<User?> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return result.user;
    } on FirebaseAuthException catch (e) {
      throw _getAuthErrorMessage(e.code);
    } catch (e) {
      throw 'An unexpected error occurred: ${e.toString()}';
    }
  }

  // Sign Out
  Future<void> signOut() async {
    try {
      return await _auth.signOut();
    } catch (e) {
      throw 'Error signing out: ${e.toString()}';
    }
  }

  // Helper to map Firebase Auth error codes to user-friendly messages
  String _getAuthErrorMessage(String errorCode) {
    switch (errorCode) {
      case 'weak-password':
        return 'The password provided is too weak.';
      case 'email-already-in-use':
        return 'An account already exists for that email.';
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'user-not-found':
        return 'No user found for that email.';
      case 'wrong-password':
        return 'Wrong password provided for that user.';
      case 'user-disabled':
        return 'This user account has been disabled.';
      default:
        return 'An authentication error occurred. Please try again.';
    }
  }
}
