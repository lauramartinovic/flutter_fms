import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfileModel {
  final String uid;
  final String email;
  final String displayName;
  final DateTime createdAt;

  /// NOVO
  final int? age; // godine
  final String? sex; // 'male' | 'female' | 'other' (može i localized)
  final double? heightCm; // visina u cm
  final double? weightKg; // težina u kg

  const UserProfileModel({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.createdAt,
    this.age,
    this.sex,
    this.heightCm,
    this.weightKg,
  });

  factory UserProfileModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return UserProfileModel(
      uid: doc.id,
      email: (data['email'] ?? '') as String,
      displayName: (data['displayName'] ?? '') as String,
      createdAt:
          (data['createdAt'] is Timestamp)
              ? (data['createdAt'] as Timestamp).toDate()
              : DateTime.fromMillisecondsSinceEpoch(0),

      age:
          (data['age'] is int)
              ? data['age'] as int
              : (data['age'] is num ? (data['age'] as num).toInt() : null),
      sex: data['sex'] as String?,
      heightCm:
          (data['heightCm'] is num)
              ? (data['heightCm'] as num).toDouble()
              : null,
      weightKg:
          (data['weightKg'] is num)
              ? (data['weightKg'] as num).toDouble()
              : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'displayName': displayName,
      'createdAt': Timestamp.fromDate(createdAt),
      if (age != null) 'age': age,
      if (sex != null) 'sex': sex,
      if (heightCm != null) 'heightCm': heightCm,
      if (weightKg != null) 'weightKg': weightKg,
    };
  }
}
