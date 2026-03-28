import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppStage {
  onboarding,
  authentication,
  home,
}

class AppFlowViewModel extends ChangeNotifier {
  static const String _keyHasOpenedBefore = 'has_opened_before';
  static const String _keyOnboardingCompleted = 'onboarding_completed';
  static const String _keyAuthenticated = 'authenticated';
  static const String _keyDisplayName = 'display_name';
  static const String _keyEmail = 'email';

  bool _initialized = false;
  bool _onboardingCompleted = false;
  bool _authenticated = false;
  String _displayName = 'Guest User';
  String _email = 'guest@demo.health';

  FirebaseAuth? get _auth {
    try {
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  DatabaseReference? get _usersRef {
    try {
      return FirebaseDatabase.instance.ref('users');
    } catch (_) {
      return null;
    }
  }

  bool get initialized => _initialized;

  AppStage get stage {
    if (!_onboardingCompleted) {
      return AppStage.onboarding;
    }
    if (!_authenticated) {
      return AppStage.authentication;
    }
    return AppStage.home;
  }

  String get displayName => _displayName;
  String get email => _email;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final hasOpenedBefore = prefs.getBool(_keyHasOpenedBefore) ?? false;
      final firebaseUser = _auth?.currentUser;

      if (hasOpenedBefore) {
        _onboardingCompleted = true;
        if (firebaseUser != null) {
          _authenticated = true;
          _email = firebaseUser.email ?? prefs.getString(_keyEmail) ?? _email;
          _displayName =
              firebaseUser.displayName ?? prefs.getString(_keyDisplayName) ?? _displayName;
        } else {
          _authenticated = prefs.getBool(_keyAuthenticated) ?? false;
          _displayName = prefs.getString(_keyDisplayName) ?? _displayName;
          _email = prefs.getString(_keyEmail) ?? _email;
        }
      } else {
        _onboardingCompleted = prefs.getBool(_keyOnboardingCompleted) ?? false;
        _authenticated = firebaseUser != null || (prefs.getBool(_keyAuthenticated) ?? false);
        _displayName =
            firebaseUser?.displayName ?? prefs.getString(_keyDisplayName) ?? _displayName;
        _email = firebaseUser?.email ?? prefs.getString(_keyEmail) ?? _email;
        await prefs.setBool(_keyHasOpenedBefore, true);
      }
    } catch (_) {
      _onboardingCompleted = true;
      _authenticated = true;
    }

    _initialized = true;
    notifyListeners();
  }

  void completeOnboarding() {
    _onboardingCompleted = true;
    _save();
    notifyListeners();
  }

  Future<void> login({required String email, required String password}) async {
    final trimmedEmail = email.trim();
    final trimmedPassword = password.trim();
    if (trimmedEmail.isEmpty || trimmedPassword.isEmpty) {
      throw Exception('Email dan password wajib diisi.');
    }

    try {
      final auth = _auth;
      if (auth == null) {
        throw Exception('Firebase belum siap. Coba lagi sebentar.');
      }

      final credential = await auth.signInWithEmailAndPassword(
        email: trimmedEmail,
        password: trimmedPassword,
      );
      final user = credential.user;
      if (user == null) {
        throw Exception('Gagal login. User tidak ditemukan.');
      }

      _email = user.email ?? trimmedEmail;
      _displayName = user.displayName ?? _email.split('@').first;

      _authenticated = true;
      await _save();
      notifyListeners();

      await _syncUserProfile(user: user, created: false);
    } on FirebaseAuthException catch (error) {
      throw Exception(_mapAuthError(error));
    }
  }

  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final trimmedName = name.trim().isEmpty ? 'Patient User' : name.trim();
    final trimmedEmail = email.trim();
    final trimmedPassword = password.trim();
    if (trimmedEmail.isEmpty || trimmedPassword.isEmpty) {
      throw Exception('Nama, email, dan password wajib diisi.');
    }

    try {
      final auth = _auth;
      if (auth == null) {
        throw Exception('Firebase belum siap. Coba lagi sebentar.');
      }

      final credential = await auth.createUserWithEmailAndPassword(
        email: trimmedEmail,
        password: trimmedPassword,
      );
      final user = credential.user;
      if (user == null) {
        throw Exception('Gagal membuat akun.');
      }

      await user.updateDisplayName(trimmedName);

      _displayName = trimmedName;
      _email = user.email ?? trimmedEmail;

      _authenticated = true;
      await _save();
      notifyListeners();

      await _syncUserProfile(user: user, created: true);
    } on FirebaseAuthException catch (error) {
      throw Exception(_mapAuthError(error));
    }
  }

  Future<void> updateProfile({required String name, required String email}) async {
    _displayName = name.trim().isEmpty ? _displayName : name.trim();
    _email = email.trim().isEmpty ? _email : email.trim();
    final auth = _auth;
    final usersRef = _usersRef;
    final user = auth?.currentUser;
    if (user != null && usersRef != null) {
      await user.updateDisplayName(_displayName);
      await usersRef.child(user.uid).update({
        'email': _email,
        'display_name': _displayName,
        'updated_at': ServerValue.timestamp,
      });
    }
    await _save();
    notifyListeners();
  }

  Future<void> logout() async {
    final auth = _auth;
    if (auth != null) {
      await auth.signOut();
    }
    _authenticated = false;
    await _save();
    notifyListeners();
  }

  String _mapAuthError(FirebaseAuthException error) {
    switch (error.code) {
      case 'wrong-password':
        return 'Password salah.';
      case 'invalid-credential':
      case 'user-not-found':
        return 'Email atau password salah.';
      case 'email-already-in-use':
        return 'Email sudah pernah dipakai, silakan login.';
      case 'weak-password':
        return 'Password terlalu lemah (minimal 6 karakter).';
      case 'invalid-email':
        return 'Format email tidak valid.';
      case 'network-request-failed':
        return 'Koneksi internet bermasalah. Coba lagi.';
      case 'operation-not-allowed':
        return 'Login Email/Password belum diaktifkan di Firebase Authentication.';
      default:
        return error.message ?? 'Terjadi kesalahan autentikasi.';
    }
  }

  Future<void> _syncUserProfile({required User user, required bool created}) async {
    final usersRef = _usersRef;
    if (usersRef == null) {
      return;
    }

    final payload = <String, Object?>{
      'uid': user.uid,
      'email': _email,
      'display_name': _displayName,
      'last_login_at': ServerValue.timestamp,
      'updated_at': ServerValue.timestamp,
    };

    if (created) {
      payload['created_at'] = ServerValue.timestamp;
    }

    try {
      await usersRef.child(user.uid).update(payload);
    } on FirebaseException catch (error) {
      // Keep auth flow successful even if profile sync is blocked by rules/network.
      debugPrint('Profile sync failed: ${error.code} ${error.message}');
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOnboardingCompleted, _onboardingCompleted);
    await prefs.setBool(_keyAuthenticated, _authenticated);
    await prefs.setString(_keyDisplayName, _displayName);
    await prefs.setString(_keyEmail, _email);
  }
}
