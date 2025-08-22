// lib/services/firestore_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // To get the current user's UID
import 'package:flutter_fms/models/fms_session_model.dart';
import 'package:flutter_fms/models/user_profile_model.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- User Profile Operations ---

  /// Creates or updates a user profile document in the 'users' collection.
  /// This should be called after successful user registration or login.
  Future<void> createUserProfile({
    required String uid,
    required String email,
    String? displayName,
  }) async {
    try {
      final userRef = _firestore.collection('users').doc(uid);
      await userRef.set(
        {
          'email': email,
          'displayName':
              displayName ?? email.split('@')[0], // Default display name
          'createdAt':
              FieldValue.serverTimestamp(), // Firestore generates timestamp on server
        },
        SetOptions(merge: true),
      ); // Use merge: true to avoid overwriting existing fields
      print('User profile created/updated for $uid');
    } catch (e) {
      print('Error creating/updating user profile: $e');
      throw Exception('Failed to create/update user profile: $e');
    }
  }

  /// Retrieves a user profile by UID.
  Stream<UserProfileModel?> getUserProfile(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (doc.exists) {
        return UserProfileModel.fromFirestore(doc);
      }
      return null;
    });
  }

  // --- FMS Session Operations ---

  /// Saves a new FMS session document to the 'fms_sessions' collection.
  Future<String> saveFMSession(FMSSessionModel session) async {
    try {
      final docRef = await _firestore
          .collection('fms_sessions')
          .add(session.toMap());
      print('FMS Session saved with ID: ${docRef.id}');
      return docRef.id; // Return the auto-generated document ID
    } on FirebaseException catch (e) {
      print(
        'Firebase Firestore Error saving FMS session: ${e.code} - ${e.message}',
      );
      throw Exception('Failed to save FMS session: ${e.message}');
    } catch (e) {
      print('Error saving FMS session: $e');
      throw Exception(
        'An unexpected error occurred while saving FMS session: $e',
      );
    }
  }

  /// Retrieves all FMS sessions for the current authenticated user.
  /// Returns a stream for real-time updates.
  Stream<List<FMSSessionModel>> getFMSSessionsForCurrentUser() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return Stream.value([]); // Return an empty list if no user is logged in
    }

    return _firestore
        .collection('fms_sessions')
        .where('userId', isEqualTo: currentUser.uid)
        .orderBy('timestamp', descending: true) // Order by most recent first
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs
                  .map((doc) => FMSSessionModel.fromFirestore(doc))
                  .toList(),
        );
  }

  // You can add more methods here, like updateFMSSession, deleteFMSSession, etc.
}
