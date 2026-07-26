import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';

class ApiClient {
  final AuthService _auth;
  final int _maxRetries;
  final Duration _baseRetryDelay;

  ApiClient(this._auth, {int maxRetries = 3, Duration? baseRetryDelay})
      : _maxRetries = maxRetries,
        _baseRetryDelay = baseRetryDelay ?? const Duration(seconds: 1);

  String get baseUrl {
    const fromEnv = String.fromEnvironment('API_URL');
    if (fromEnv.isNotEmpty) return fromEnv;

    if (kIsWeb) {
      final host = Uri.base.host;
      if (host == 'localhost' || host == '127.0.0.1' || host == '0.0.0.0') {
        return 'http://localhost:8080/api';
      }
      return '${Uri.base.scheme}://${Uri.base.host}${Uri.base.port != 0 && Uri.base.port != 80 && Uri.base.port != 443 ? ":${Uri.base.port}" : ""}/api';
    }

    if (kReleaseMode) {
      return 'https://zukaping.onrender.com/api';
    }

    return 'http://10.0.2.2:8080/api';
  }

  Future<Map<String, String>> _headers() async => _auth.authHeaders;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<dynamic> get(String path, {String? cacheKey}) async {
    return _requestWithRetry('GET', path, cacheKey: cacheKey);
  }

  Future<dynamic> post(String path, {Map<String, dynamic>? body, String? cacheKey}) async {
    return _requestWithRetry('POST', path, body: body, cacheKey: cacheKey);
  }

  Future<dynamic> put(String path, {Map<String, dynamic>? body}) async {
    return _requestWithRetry('PUT', path, body: body);
  }

  Future<dynamic> delete(String path) async {
    return _requestWithRetry('DELETE', path);
  }

  Future<dynamic> _requestWithRetry(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? cacheKey,
  }) async {
    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        return await _doRequest(method, path, body: body, cacheKey: cacheKey);
      } on SocketException {
        if (attempt < _maxRetries) {
          await Future.delayed(_baseRetryDelay * (attempt + 1));
          continue;
        }
        return _fallbackFromCache(cacheKey);
      } on HttpException {
        if (attempt < _maxRetries) {
          await Future.delayed(_baseRetryDelay * (attempt + 1));
          continue;
        }
        return _fallbackFromCache(cacheKey);
      } on TimeoutException {
        if (attempt < _maxRetries) {
          await Future.delayed(_baseRetryDelay * (attempt + 1));
          continue;
        }
        return _fallbackFromCache(cacheKey);
      }
    }
  }

  Future<dynamic> _doRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? cacheKey,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 30);

    try {
      final uri = _uri(path);
      final request = await client.openUrl(method, uri);

      final headers = await _headers();
      headers.forEach((key, value) {
        request.headers.set(key, value);
      });

      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }

      final response = await request.close().timeout(const Duration(seconds: 15));
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (responseBody.isEmpty) return null;
        final decoded = jsonDecode(responseBody);

        if (cacheKey != null) {
          _saveCache(cacheKey, responseBody);
        }

        return decoded;
      }

      if (response.statusCode == 401) {
        await _auth.clearAuth();
        throw AuthException('Session expired');
      }

      throw ApiException(response.statusCode, responseBody);
    } finally {
      client.close(force: false);
    }
  }

  Future<dynamic> _fallbackFromCache(String? cacheKey) async {
    if (cacheKey == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(cacheKey);
      if (cached != null) return jsonDecode(cached);
    } catch (_) {}
    return null;
  }

  Future<void> _saveCache(String key, String data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, data);
    } catch (_) {}
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String body;
  ApiException(this.statusCode, this.body);

  @override
  String toString() => 'ApiException($statusCode): $body';
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => 'AuthException: $message';
}
