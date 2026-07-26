import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService extends ChangeNotifier {
  static const _tokenKey = 'auth_token';
  static const _userIdKey = 'auth_user_id';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  String? _token;
  String? _userId;

  String? get token => _token;
  String? get userId => _userId;
  bool get isAuthenticated => _token != null && _userId != null;

  Future<void> init() async {
    _token = await _secureStorage.read(key: _tokenKey);
    _userId = await _secureStorage.read(key: _userIdKey);
    notifyListeners();
  }

  Future<void> saveAuth(String token, String userId) async {
    _token = token;
    _userId = userId;
    await _secureStorage.write(key: _tokenKey, value: token);
    await _secureStorage.write(key: _userIdKey, value: userId);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setString('userId', userId);

    notifyListeners();
  }

  Future<void> clearAuth() async {
    _token = null;
    _userId = null;
    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: _userIdKey);

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('userId');
    await prefs.remove('cached_profile');
    await prefs.remove('cached_feed');
    await prefs.remove('cached_chats');
    await prefs.remove('cached_favorites');
    await prefs.remove('cached_nearby_users');

    notifyListeners();
  }

  String? decodeUserIdFromToken() {
    if (_token == null) return null;
    try {
      final parts = _token!.split('.');
      if (parts.length != 3) return null;
      final payload = json.decode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      return payload['userId'] ?? payload['sub'] ?? payload['id'];
    } catch (_) {
      return null;
    }
  }

  Map<String, String> get authHeaders => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };
}
