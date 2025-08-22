// lib/models/fms_session_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class FMSSessionModel {
  final String? id; // Document ID, optional for creation
  final String userId;
  final DateTime timestamp;
  final String videoUrl;
  final String rating;
  final String notes;
  // Add other fields like exerciseScores if you decide to include them

  FMSSessionModel({
    this.id,
    required this.userId,
    required this.timestamp,
    required this.videoUrl,
    required this.rating,
    required this.notes,
  });

  // Factory constructor to create an FMSSessionModel from a Firestore DocumentSnapshot
  factory FMSSessionModel.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    return FMSSessionModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      videoUrl: data['videoUrl'] ?? '',
      rating: data['rating'] ?? '',
      notes: data['notes'] ?? '',
    );
  }

  // Method to convert an FMSSessionModel instance into a Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'timestamp': Timestamp.fromDate(
        timestamp,
      ), // Convert DateTime to Firestore Timestamp
      'videoUrl': videoUrl,
      'rating': rating,
      'notes': notes,
    };
  }
}
