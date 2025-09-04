import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfileModel {
  final String uid;
  final String email;
  final String displayName;
  final DateTime createdAt;

  // NOVO – opcionalni profil podaci
  final int? age; // godina
  final String? gender; // "male", "female", "other" (po dogovoru)
  final double? heightCm; // visina u cm
  final double? weightKg; // težina u kg

  const UserProfileModel({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.createdAt,
    this.age,
    this.gender,
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
          (data['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      age: (data['age'] as num?)?.toInt(),
      gender: data['gender'] as String?,
      heightCm: (data['heightCm'] as num?)?.toDouble(),
      weightKg: (data['weightKg'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'email': email,
      'displayName': displayName,
      'createdAt': Timestamp.fromDate(createdAt),
    };
    if (age != null) map['age'] = age;
    if (gender != null) map['gender'] = gender;
    if (heightCm != null) map['heightCm'] = heightCm;
    if (weightKg != null) map['weightKg'] = weightKg;
    return map;
  }
}
