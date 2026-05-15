import 'package:flutter/foundation.dart';

import '../models/auth_models.dart';

class SessionController extends ChangeNotifier {
  AppUser? _user;

  AppUser? get user => _user;
  bool get isLoggedIn => _user != null;

  void login({required String username, required UserRole role}) {
    final cleanName = username.trim().isEmpty ? role.label : username.trim();
    _user = AppUser(username: cleanName, role: role);
    notifyListeners();
  }

  void logout() {
    _user = null;
    notifyListeners();
  }
}
