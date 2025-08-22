// lib/models/user_profile_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfileModel {
  final String uid;
  final String email;
  final String displayName;
  final DateTime createdAt;
  // Add other fields as needed, e.g., String? profileImageUrl;

  UserProfileModel({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.createdAt,
  });

  // Factory constructor to create a UserProfileModel from a Firestore DocumentSnapshot
  factory UserProfileModel.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    return UserProfileModel(
      uid: doc.id, // UID is the document ID
      email: data['email'] ?? '',
      displayName: data['displayName'] ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }

  // Method to convert a UserProfileModel instance into a Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'displayName': displayName,
      'createdAt': Timestamp.fromDate(
        createdAt,
      ), // Convert DateTime to Firestore Timestamp
    };
  }
}
