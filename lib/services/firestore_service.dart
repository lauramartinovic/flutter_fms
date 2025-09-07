import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_fms/models/fms_session_model.dart';
import 'package:flutter_fms/models/user_profile_model.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // -----------------------------
  // User Profile
  // -----------------------------

  /// Kreira ili ažurira profil (merge) – sada podržava i demografske podatke.
  Future<void> createUserProfile({
    required String uid,
    required String email,
    String? displayName,
    int? age,
    String? sex,
    double? heightCm,
    double? weightKg,
  }) async {
    try {
      final userRef = _firestore.collection('users').doc(uid);
      await userRef.set({
        'email': email,
        'displayName': displayName ?? email.split('@').first,
        'createdAt': FieldValue.serverTimestamp(),
        if (age != null) 'age': age,
        if (sex != null) 'sex': sex,
        if (heightCm != null) 'heightCm': heightCm,
        if (weightKg != null) 'weightKg': weightKg,
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Failed to create/update user profile: $e');
    }
  }

  /// Dohvat profila (stream)
  Stream<UserProfileModel?> getUserProfile(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (doc.exists) {
        return UserProfileModel.fromFirestore(doc);
      }
      return null;
    });
  }

  /// Ažuriranje samo odabranih polja profila (npr. s Edit Profile ekrana)
  Future<void> updateUserProfile(
    String uid,
    Map<String, dynamic> updates,
  ) async {
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .set(updates, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Failed to update profile: $e');
    }
  }

  // -----------------------------
  // FMS Session
  // -----------------------------
  Future<String> saveFMSession(FMSSessionModel session) async {
    try {
      final data =
          session.toMap()..['timestamp'] = FieldValue.serverTimestamp();
      final docRef = await _firestore.collection('fms_sessions').add(data);
      return docRef.id;
    } on FirebaseException catch (e) {
      throw Exception('Failed to save FMS session: ${e.message}');
    } catch (e) {
      throw Exception(
        'An unexpected error occurred while saving FMS session: $e',
      );
    }
  }

  Stream<List<FMSSessionModel>> getFMSSessionsForCurrentUser() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return Stream.value([]);
    return _firestore
        .collection('fms_sessions')
        .where('userId', isEqualTo: currentUser.uid)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (s) => s.docs.map((d) => FMSSessionModel.fromFirestore(d)).toList(),
        );
  }

  Stream<List<FMSSessionModel>> getFMSSessionsForUser(String uid) {
    return _firestore
        .collection('fms_sessions')
        .where('userId', isEqualTo: uid)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (s) => s.docs.map((d) => FMSSessionModel.fromFirestore(d)).toList(),
        );
  }

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

  Future<void> deleteFMSSession(String sessionId) async {
    try {
      await _firestore.collection('fms_sessions').doc(sessionId).delete();
    } on FirebaseException catch (e) {
      throw Exception('Failed to delete session: ${e.message}');
    }
  }
}
