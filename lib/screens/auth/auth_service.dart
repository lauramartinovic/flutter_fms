import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  Future<UserCredential> registerWithEmailAndPassword(
    String email,
    String password,
  ) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    // Kreiraj user profil u Firestore
    final uid = cred.user!.uid;
    final displayName = email.split('@').first;
    await _db.collection('users').doc(uid).set({
      'email': email,
      'displayName': displayName,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // (opcionalno) osvježi displayName u Auth profilu
    await cred.user?.updateDisplayName(displayName);

    return cred;
  }

  Future<UserCredential> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    // Safety net: ako profil ne postoji (npr. legacy korisnik), kreiraj ga
    final uid = cred.user!.uid;
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) {
      final displayName = cred.user?.displayName ?? email.split('@').first;
      await _db.collection('users').doc(uid).set({
        'email': email,
        'displayName': displayName,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    return cred;
  }

  Future<void> signOut() => _auth.signOut();

  Stream<User?> authState() => _auth.authStateChanges();
}
