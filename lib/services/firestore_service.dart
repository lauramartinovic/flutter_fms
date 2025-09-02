// lib/services/firestore_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_fms/models/fms_session_model.dart';
import 'package:flutter_fms/models/user_profile_model.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // -----------------------------
  // User Profile Operations
  // -----------------------------
  Future<void> createUserProfile({
    required String uid,
    required String email,
    String? displayName,
  }) async {
    try {
      final userRef = _firestore.collection('users').doc(uid);
      await userRef.set({
        'email': email,
        'displayName': displayName ?? email.split('@').first,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      // print('User profile created/updated for $uid');
    } catch (e) {
      // print('Error creating/updating user profile: $e');
      throw Exception('Failed to create/update user profile: $e');
    }
  }

  Stream<UserProfileModel?> getUserProfile(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (doc.exists) {
        return UserProfileModel.fromFirestore(doc);
      }
      return null;
    });
  }

  // -----------------------------
  // FMS Session Operations
  // -----------------------------

  /// Save a new FMS session. Uses server timestamp for consistent ordering.
  Future<String> saveFMSession(FMSSessionModel session) async {
    try {
      final data =
          session.toMap()
            ..['timestamp'] =
                FieldValue.serverTimestamp(); // override to ensure server time

      final docRef = await _firestore.collection('fms_sessions').add(data);
      // print('FMS Session saved with ID: ${docRef.id}');
      return docRef.id;
    } on FirebaseException catch (e) {
      // print('Firestore Error saving FMS session: ${e.code} - ${e.message}');
      throw Exception('Failed to save FMS session: ${e.message}');
    } catch (e) {
      // print('Error saving FMS session: $e');
      throw Exception(
        'An unexpected error occurred while saving FMS session: $e',
      );
    }
  }

  /// Stream sessions for the *current* authenticated user, newest first.
  Stream<List<FMSSessionModel>> getFMSSessionsForCurrentUser() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return Stream.value([]);
    }

    return _firestore
        .collection('fms_sessions')
        .where('userId', isEqualTo: currentUser.uid)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs
                  .map((doc) => FMSSessionModel.fromFirestore(doc))
                  .toList(),
        );
  }

  /// Stream sessions for an arbitrary user (useful for coach/admin views).
  Stream<List<FMSSessionModel>> getFMSSessionsForUser(String uid) {
    return _firestore
        .collection('fms_sessions')
        .where('userId', isEqualTo: uid)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs
                  .map((doc) => FMSSessionModel.fromFirestore(doc))
                  .toList(),
        );
  }

  /// Update specific fields on a session (e.g., notes or corrected rating).
  Future<void> updateFMSSession({
    required String sessionId,
    required Map<String, dynamic> updates,
  }) async {
    try {
      await _firestore
          .collection('fms_sessions')
          .doc(sessionId)
          .update(updates);
    } on FirebaseException catch (e) {
      throw Exception('Failed to update session: ${e.message}');
    }
  }

  /// Delete a session document.
  Future<void> deleteFMSSession(String sessionId) async {
    try {
      await _firestore.collection('fms_sessions').doc(sessionId).delete();
    } on FirebaseException catch (e) {
      throw Exception('Failed to delete session: ${e.message}');
    }
  }
}
