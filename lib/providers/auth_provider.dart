// lib/providers/auth_provider.dart
import 'package:flutter/material.dart';

class AuthProvider with ChangeNotifier {
  bool _isLoading = false;

  bool get isLoading => _isLoading;

  void setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
