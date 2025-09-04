import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

@immutable
class FMSSessionModel {
  final String? id; // Firestore doc ID (null prije .add)
  final String userId; // Firebase Auth UID
  final DateTime timestamp; // Kada je sesija spremljena
  final String exercise; // Ljudsko čitljivo ime vježbe (npr. "Overhead Squat")
  final int rating; // 0–3
  final String? notes; // opcionalno
  final String?
  videoUrl; // opcionalno (zbog kompatibilnosti; ne koristi se u History)

  const FMSSessionModel({
    this.id,
    required this.userId,
    required this.timestamp,
    required this.exercise,
    required this.rating,
    this.notes,
    this.videoUrl,
  });

  /// Minimalna validacija pri konstrukciji
  FMSSessionModel _validated() {
    final clamped = rating.clamp(0, 3);
    return rating == clamped ? this : copyWith(rating: clamped);
  }

  /// Factory iz Firestore dokumenta
  factory FMSSessionModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? const {};
    return FMSSessionModel(
      id: doc.id,
      userId: data['userId'] as String? ?? '',
      timestamp:
          (data['timestamp'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      exercise: data['exercise'] as String? ?? 'Unknown',
      rating: (data['rating'] as num?)?.toInt() ?? 0,
      notes: data['notes'] as String?,
      videoUrl: data['videoUrl'] as String?,
    )._validated();
  }

  /// Map za Firestore
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'userId': userId,
      'timestamp': Timestamp.fromDate(timestamp),
      'exercise': exercise,
      'rating': rating,
    };
    if (notes != null && notes!.isNotEmpty) map['notes'] = notes;
    if (videoUrl != null && videoUrl!.isNotEmpty) map['videoUrl'] = videoUrl;
    return map;
  }

  /// copyWith za praktično ažuriranje
  FMSSessionModel copyWith({
    String? id,
    String? userId,
    DateTime? timestamp,
    String? exercise,
    int? rating,
    String? notes,
    String? videoUrl,
  }) {
    return FMSSessionModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      timestamp: timestamp ?? this.timestamp,
      exercise: exercise ?? this.exercise,
      rating: rating ?? this.rating,
      notes: notes ?? this.notes,
      videoUrl: videoUrl ?? this.videoUrl,
    )._validated();
  }

  /// Jednostavna jednakost po ID-u (ako postoji), inače po poljima
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FMSSessionModel) return false;
    if (id != null && other.id != null) return id == other.id;
    return userId == other.userId &&
        timestamp == other.timestamp &&
        exercise == other.exercise &&
        rating == other.rating &&
        notes == other.notes &&
        videoUrl == other.videoUrl;
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    timestamp.millisecondsSinceEpoch,
    exercise,
    rating,
    notes,
    videoUrl,
  );

  @override
  String toString() =>
      'FMSSessionModel(id:$id, userId:$userId, ts:$timestamp, exercise:$exercise, rating:$rating)';
}
