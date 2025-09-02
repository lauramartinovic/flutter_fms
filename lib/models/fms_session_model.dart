import 'package:cloud_firestore/cloud_firestore.dart';

class FMSSessionModel {
  final String? id; // Firestore document ID (null before save)
  final String userId; // Firebase Auth UID
  final DateTime timestamp; // When the session was recorded/saved
  final String videoUrl; // Firebase Storage public URL
  final String exercise; // Human readable exercise name
  final int rating; // Numeric score 0–3
  final String notes; // Free text notes

  const FMSSessionModel({
    this.id,
    required this.userId,
    required this.timestamp,
    required this.videoUrl,
    required this.exercise,
    required this.rating,
    required this.notes,
  });

  factory FMSSessionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return FMSSessionModel(
      id: doc.id,
      userId: (data['userId'] ?? '') as String,
      timestamp:
          (data['timestamp'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      videoUrl: (data['videoUrl'] ?? '') as String,
      exercise: (data['exercise'] ?? 'Unknown') as String,
      rating: (data['rating'] ?? 0) as int,
      notes: (data['notes'] ?? '') as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'timestamp': Timestamp.fromDate(timestamp),
      'videoUrl': videoUrl,
      'exercise': exercise,
      'rating': rating,
      'notes': notes,
    };
  }
}
