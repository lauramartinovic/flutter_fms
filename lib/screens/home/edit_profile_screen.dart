import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_fms/models/user_profile_model.dart';
import 'package:flutter_fms/services/firestore_service.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  final _displayNameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  String _sex = 'female';

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _ageCtrl.dispose();
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    int? age;
    double? heightCm;
    double? weightKg;

    if (_ageCtrl.text.trim().isNotEmpty) {
      age = int.tryParse(_ageCtrl.text.trim());
    }
    if (_heightCtrl.text.trim().isNotEmpty) {
      heightCm = double.tryParse(_heightCtrl.text.trim());
    }
    if (_weightCtrl.text.trim().isNotEmpty) {
      weightKg = double.tryParse(_weightCtrl.text.trim());
    }

    try {
      await FirestoreService().updateUserProfile(user.uid, {
        if (_displayNameCtrl.text.trim().isNotEmpty)
          'displayName': _displayNameCtrl.text.trim(),
        'sex': _sex,
        'age': age,
        'heightCm': heightCm,
        'weightKg': weightKg,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile updated')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update profile: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: StreamBuilder<UserProfileModel?>(
        stream: FirestoreService().getUserProfile(user.uid),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final profile = snap.data;

          // Prefill form fields
          _displayNameCtrl.text = profile?.displayName ?? '';
          _sex = profile?.sex ?? _sex;
          _ageCtrl.text = (profile?.age?.toString() ?? '');
          _heightCtrl.text = (profile?.heightCm?.toString() ?? '');
          _weightCtrl.text = (profile?.weightKg?.toString() ?? '');

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  // Email is read-only (iz Firebatea)
                  TextFormField(
                    initialValue: profile?.email ?? user.email ?? '',
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    readOnly: true,
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _displayNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Display name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Sex
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Sex',
                      border: OutlineInputBorder(),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _sex,
                        items: const [
                          DropdownMenuItem(
                            value: 'female',
                            child: Text('Female'),
                          ),
                          DropdownMenuItem(value: 'male', child: Text('Male')),
                          DropdownMenuItem(
                            value: 'other',
                            child: Text('Other'),
                          ),
                        ],
                        onChanged: (v) => setState(() => _sex = v ?? 'female'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _ageCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Age (years)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _heightCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Height (cm)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _weightCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Weight (kg)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 20),

                  FilledButton(onPressed: _save, child: const Text('Save')),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
