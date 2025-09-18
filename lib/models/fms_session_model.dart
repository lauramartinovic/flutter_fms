import 'package:cloud_firestore/cloud_firestore.dart';

class FMSSessionModel {
  final String? id; // Firestore doc ID (null prije spremanja)
  final String userId; // Firebase Auth UID
  final DateTime timestamp; // Vrijeme snimanja/spremanja
  final String exercise; // Čitljivo ime vježbe
  final int rating; // 0–3
  final String notes; // slobodne bilješke (ostavljeno radi kompatibilnosti)
  final String
  feedback; // automatizirani feedback (npr. na temelju ocjene/boli)
  final bool painLowBack; // self-report: donja leđa
  final bool painHamstringOrCalf; // self-report: stražnja loža / list
  final String? videoUrl; // opcionalno
  final Map<String, dynamic>? features; // kutovi, min/max, reps, flagovi...

  const FMSSessionModel({
    this.id,
    required this.userId,
    required this.timestamp,
    required this.exercise,
    required this.rating,
    this.notes = '',
    this.feedback = '',
    this.painLowBack = false,
    this.painHamstringOrCalf = false,
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

      // Zadržavamo notes; feedback čitamo iz 'feedback' ako postoji,
      // u suprotnom fallback na notes radi kompatibilnosti.
      notes: (data['notes'] ?? '') as String,
      feedback: (data['feedback'] ?? data['notes'] ?? '') as String,

      painLowBack: (data['painLowBack'] ?? false) as bool,
      painHamstringOrCalf: (data['painHamstringOrCalf'] ?? false) as bool,

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
      'feedback': feedback,
      'painLowBack': painLowBack,
      'painHamstringOrCalf': painHamstringOrCalf,
    };
    if (videoUrl != null && videoUrl!.isNotEmpty) {
      map['videoUrl'] = videoUrl;
    }
    if (features != null && features!.isNotEmpty) {
      map['features'] = features;
    }
    return map;
  }

  FMSSessionModel copyWith({
    String? id,
    String? userId,
    DateTime? timestamp,
    String? exercise,
    int? rating,
    String? notes,
    String? feedback,
    bool? painLowBack,
    bool? painHamstringOrCalf,
    String? videoUrl,
    Map<String, dynamic>? features,
  }) {
    return FMSSessionModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      timestamp: timestamp ?? this.timestamp,
      exercise: exercise ?? this.exercise,
      rating: rating ?? this.rating,
      notes: notes ?? this.notes,
      feedback: feedback ?? this.feedback,
      painLowBack: painLowBack ?? this.painLowBack,
      painHamstringOrCalf: painHamstringOrCalf ?? this.painHamstringOrCalf,
      videoUrl: videoUrl ?? this.videoUrl,
      features: features ?? this.features,
    );
  }
}
