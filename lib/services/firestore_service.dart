import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_fms/models/fms_session_model.dart';
import 'package:flutter_fms/models/user_profile_model.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // -----------------------------
  // User Profile
  // -----------------------------
  Future<void> createUserProfile({
    required String uid,
    required String email,
    String? displayName,
    int? age,
    String? gender,
    double? heightCm,
    double? weightKg,
  }) async {
    try {
      final doc = _firestore.collection('users').doc(uid);
      final data = <String, dynamic>{
        'email': email,
        'displayName': displayName ?? email.split('@').first,
        'createdAt': FieldValue.serverTimestamp(),
      };
      if (age != null) data['age'] = age;
      if (gender != null) data['gender'] = gender;
      if (heightCm != null) data['heightCm'] = heightCm;
      if (weightKg != null) data['weightKg'] = weightKg;

      await doc.set(data, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Failed to create/update user profile: $e');
    }
  }

  /// Partial update profila – proslijedi samo polja koja želiš mijenjati
  Future<void> updateUserProfileFields({
    required String uid,
    required Map<String, dynamic> fields,
  }) async {
    try {
      await _firestore.collection('users').doc(uid).update(fields);
    } on FirebaseException catch (e) {
      throw Exception('Failed to update profile: ${e.message}');
    }
  }

  Stream<UserProfileModel?> getUserProfile(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserProfileModel.fromFirestore(doc);
    });
  }

  // -----------------------------
  // FMS Sessions
  // -----------------------------
  Future<String> saveFMSession(FMSSessionModel session) async {
    try {
      final data =
          session.toMap()..['timestamp'] = FieldValue.serverTimestamp();
      final ref = await _firestore.collection('fms_sessions').add(data);
      return ref.id;
    } on FirebaseException catch (e) {
      throw Exception('Failed to save FMS session: ${e.message}');
    } catch (e) {
      throw Exception('Unexpected error saving session: $e');
    }
  }

  Stream<List<FMSSessionModel>> getFMSSessionsForCurrentUser() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value([]);
    return _firestore
        .collection('fms_sessions')
        .where('userId', isEqualTo: user.uid)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => FMSSessionModel.fromFirestore(d)).toList(),
        );
  }

  Stream<List<FMSSessionModel>> getFMSSessionsForUser(String uid) {
    return _firestore
        .collection('fms_sessions')
        .where('userId', isEqualTo: uid)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => FMSSessionModel.fromFirestore(d)).toList(),
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
