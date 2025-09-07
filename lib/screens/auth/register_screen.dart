import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_fms/services/auth_service.dart';
import 'package:flutter_fms/providers/auth_provider.dart';
import 'package:flutter_fms/services/firestore_service.dart';

class RegisterScreen extends StatefulWidget {
  final Function toggleView;
  const RegisterScreen({super.key, required this.toggleView});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  // Auth fields
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // Profile fields
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  String _sex = 'female'; // default
  final TextEditingController _heightController = TextEditingController(); // cm
  final TextEditingController _weightController = TextEditingController(); // kg

  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    authProvider.setLoading(true);
    setState(() => _errorMessage = null);

    try {
      final user = await AuthService().registerWithEmailAndPassword(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );

      if (user != null) {
        // Parse optional numbers safely
        int? age;
        double? heightCm;
        double? weightKg;

        if (_ageController.text.trim().isNotEmpty) {
          age = int.tryParse(_ageController.text.trim());
        }
        if (_heightController.text.trim().isNotEmpty) {
          heightCm = double.tryParse(_heightController.text.trim());
        }
        if (_weightController.text.trim().isNotEmpty) {
          weightKg = double.tryParse(_weightController.text.trim());
        }

        // Save profile to Firestore
        await FirestoreService().createUserProfile(
          uid: user.uid,
          email: user.email ?? _emailController.text.trim(),
          displayName:
              _displayNameController.text.trim().isEmpty
                  ? null
                  : _displayNameController.text.trim(),
          age: age,
          sex: _sex,
          heightCm: heightCm,
          weightKg: weightKg,
        );
        // Daljnja navigacija ide preko AuthGate-a nakon authStateChanges
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      authProvider.setLoading(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Register'), centerTitle: true),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // EMAIL + PASSWORD
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email*',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator:
                      (v) =>
                          (v == null || v.trim().isEmpty)
                              ? 'Enter an email'
                              : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password*',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  validator:
                      (v) =>
                          (v == null || v.length < 6)
                              ? 'Password must be 6+ chars'
                              : null,
                ),
                const SizedBox(height: 12),

                // DISPLAY NAME (optional)
                TextFormField(
                  controller: _displayNameController,
                  decoration: const InputDecoration(
                    labelText: 'Display name (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                // AGE
                TextFormField(
                  controller: _ageController,
                  decoration: const InputDecoration(
                    labelText: 'Age (years)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),

                // SEX
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
                        DropdownMenuItem(value: 'other', child: Text('Other')),
                      ],
                      onChanged: (v) => setState(() => _sex = v ?? 'female'),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // HEIGHT
                TextFormField(
                  controller: _heightController,
                  decoration: const InputDecoration(
                    labelText: 'Height (cm)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),

                // WEIGHT
                TextFormField(
                  controller: _weightController,
                  decoration: const InputDecoration(
                    labelText: 'Weight (kg)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 20),

                if (_errorMessage != null)
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                const SizedBox(height: 12),

                authProvider.isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                      onPressed: _register,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 14,
                        ),
                      ),
                      child: const Text('Create account'),
                    ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => widget.toggleView(),
                  child: const Text('Already have an account? Sign In'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
