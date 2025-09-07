import 'package:cloud_firestore/cloud_firestore.dart';

class FMSSessionModel {
  final String? id; // Firestore document ID (null before save)
  final String userId; // Firebase Auth UID
  final DateTime timestamp; // When the session was recorded/saved
  final String exercise; // Human readable exercise name
  final int rating; // 0–3 (FMS-like)
  final String notes; // free text
  final String? videoUrl; // optional: low-res URL in Storage
  final Map<String, dynamic>? features; // NEW: angles, min/max, reps, etc.

  const FMSSessionModel({
    this.id,
    required this.userId,
    required this.timestamp,
    required this.exercise,
    required this.rating,
    required this.notes,
    this.videoUrl,
    this.features,
  });

  factory FMSSessionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return FMSSessionModel(
      id: doc.id,
      userId: (data['userId'] ?? '') as String,
      timestamp:
          (data['timestamp'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      exercise: (data['exercise'] ?? 'Unknown') as String,
      rating: (data['rating'] ?? 0) as int,
      notes: (data['notes'] ?? '') as String,
      videoUrl: data['videoUrl'] as String?,
      features: (data['features'] as Map?)?.cast<String, dynamic>(),
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'userId': userId,
      'timestamp': Timestamp.fromDate(timestamp),
      'exercise': exercise,
      'rating': rating,
      'notes': notes,
    };
    if (videoUrl != null && videoUrl!.isNotEmpty) {
      map['videoUrl'] = videoUrl;
    }
    if (features != null && features!.isNotEmpty) {
      map['features'] = features;
    }
    return map;
  }
}
