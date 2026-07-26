import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';

import 'auth_service.dart';
import 'api_client.dart';

class ApiService {
  static AuthService? _authService;
  static ApiClient? _client;

  static void init(AuthService authService) {
    _authService = authService;
    _client = ApiClient(authService);
  }

  static ApiClient get client {
    if (_client == null) {
      _authService = AuthService();
      _client = ApiClient(_authService!);
    }
    return _client!;
  }

  static String get baseUrl => client.baseUrl;

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  static Future<Map<String, String>> getHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode != 200) {
        throw Exception(data['message'] ?? 'Login failed');
      }
      return data;
    } catch (e) {
      return {'error': true, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> signup(Map<String, dynamic> userData) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/signup'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(userData),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode != 201) {
        throw Exception(data['message'] ?? 'Signup failed');
      }
      return data;
    } catch (e) {
      return {'error': true, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> googleAuth(String credential) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/google-auth'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'credential': credential}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode != 200) {
        throw Exception(data['error'] ?? data['message'] ?? 'Google auth failed');
      }
      return data;
    } catch (e) {
      return {'error': true, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> getProfile() async {
    try {
      return await client.get('/me', cacheKey: 'cached_profile');
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_profile');
      if (cached != null) return jsonDecode(cached);
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) async {
    final result = await client.put('/me', body: data);
    final prefs = await SharedPreferences.getInstance();
    if (result != null && result['id'] != null) {
      await prefs.setString('cached_profile', jsonEncode(result));
    } else {
      await prefs.remove('cached_profile');
    }
    return result ?? {};
  }

  static Future<List<dynamic>> getFeed() async {
    try {
      final data = await client.get('/feed', cacheKey: 'cached_feed');
      return data is List ? data : (data is Map ? (data['posts'] ?? []) : []);
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_feed');
      if (cached != null) return jsonDecode(cached);
      return [];
    }
  }

  static Future<Map<String, dynamic>> createPost(Map<String, dynamic> postData) async {
    final result = await client.post('/post', body: postData);
    return result ?? {};
  }

  static Future<List<dynamic>> getChats() async {
    try {
      final data = await client.get('/chats', cacheKey: 'cached_chats');
      return data is List ? data : (data is Map ? (data['chats'] ?? []) : []);
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_chats');
      if (cached != null) return jsonDecode(cached);
      return [];
    }
  }

  static Future<Map<String, dynamic>> createChat(String userId) async {
    final result = await client.post('/chats', body: {'participants': [userId]});
    return result ?? {};
  }

  static Future<Map<String, dynamic>> createGroupChat(
    List<String> userIds,
    String groupName, {
    String? groupDescription,
    String? groupAvatar,
  }) async {
    final result = await client.post('/chats', body: {
      'participants': userIds,
      'isGroup': true,
      'groupName': groupName,
      'groupDescription': groupDescription,
      'groupAvatar': groupAvatar,
    });
    return result ?? {};
  }

  static Future<List<dynamic>> getMessages(String chatId) async {
    try {
      final data = await client.get('/messages/$chatId', cacheKey: 'cached_messages_$chatId');
      if (data is List) return data.cast<Map<String, dynamic>>();
      if (data is Map && data['messages'] != null) {
        return (data['messages'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_messages_$chatId');
      if (cached != null) {
        final decoded = jsonDecode(cached);
        return decoded is List ? decoded : [];
      }
      return [];
    }
  }

  static Future<Map<String, dynamic>> sendMessage(String chatId, String content, {String type = 'text'}) async {
    final result = await client.post('/message', body: {
      'chatId': chatId,
      'content': content,
      'type': type,
    });
    return result ?? {};
  }

  static Future<List<dynamic>> getFavorites() async {
    try {
      final data = await client.get('/favorites', cacheKey: 'cached_favorites');
      return data is List ? data : (data is Map ? (data['favorites'] ?? []) : []);
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_favorites');
      if (cached != null) return jsonDecode(cached);
      return [];
    }
  }

  static Future<Map<String, dynamic>> toggleFavorite(String userId) async {
    final result = await client.post('/favorite', body: {'targetUserId': userId});
    return result ?? {};
  }

  static Future<Map<String, dynamic>> getUserById(String userId) async {
    final data = await client.get('/user/$userId');
    return data ?? {};
  }

  static Future<Map<String, dynamic>> getChat(String chatId) async {
    final data = await client.get('/chats/$chatId');
    return data ?? {};
  }

  static Future<List<dynamic>> getNearbyUsers(double lat, double lng) async {
    try {
      final data = await client.get('/users/nearby?lat=$lat&lng=$lng', cacheKey: 'cached_nearby_users');
      if (data is List) return data.cast<Map<String, dynamic>>();
      return [];
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_nearby_users');
      if (cached != null) {
        final decoded = jsonDecode(cached);
        return decoded is List ? decoded : [];
      }
      return [];
    }
  }

  static Future<List<dynamic>> searchUsers(String query) async {
    final data = await client.get('/users/search?q=${Uri.encodeComponent(query)}');
    if (data is List) return data;
    if (data is Map) return data['users'] ?? [];
    return [];
  }

  static Future<String?> uploadImage(Uint8List bytes, String filename) async {
    final token = await getToken();
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/upload-photo'));
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    request.files.add(http.MultipartFile.fromBytes(
      'photo',
      bytes,
      filename: filename,
    ));

    try {
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['url'];
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<Position?> getCurrentPosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }

    if (permission == LocationPermission.deniedForever) return null;

    return await Geolocator.getCurrentPosition();
  }

  static Future<bool> reactToMessage(String messageId, String emoji) async {
    try {
      await client.post('/messages/$messageId/react', body: {'emoji': emoji});
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> blockUser(String userId) async {
    final result = await client.post('/block', body: {'targetUserId': userId});
    return result ?? {};
  }

  static Future<Map<String, dynamic>> updateGroupChat(
    String chatId, {
    String? groupName,
    String? groupDescription,
    String? groupAvatar,
  }) async {
    final body = <String, dynamic>{};
    if (groupName != null) body['groupName'] = groupName;
    if (groupDescription != null) body['groupDescription'] = groupDescription;
    if (groupAvatar != null) body['groupAvatar'] = groupAvatar;
    final result = await client.put('/chats/$chatId', body: body);
    return result ?? {};
  }

  static Future<Map<String, dynamic>> promoteToAdmin(String chatId, String targetUserId) async {
    final result = await client.post('/chats/$chatId/admin', body: {'targetUserId': targetUserId});
    return result ?? {};
  }

  static Future<Map<String, dynamic>> removeGroupMember(String chatId, String userId) async {
    final result = await client.delete('/chats/$chatId/participants/$userId');
    return result ?? {};
  }

  static Future<Map<String, dynamic>> generateGroupInviteCode(String chatId) async {
    final result = await client.post('/chats/$chatId/invite');
    return result ?? {};
  }

  static Future<Map<String, dynamic>> getGroupInfoByInviteCode(String code) async {
    final result = await client.get('/groups/invite/$code');
    return result ?? {};
  }

  static Future<Map<String, dynamic>> joinGroupByInviteCode(String code) async {
    final result = await client.post('/groups/join', body: {'inviteCode': code});
    return result ?? {};
  }

  static Future<Map<String, dynamic>> addGroupMember(String chatId, String userId) async {
    final result = await client.post('/chats/$chatId/participants', body: {'userId': userId});
    return result ?? {};
  }

  static Future<Map<String, dynamic>> deleteAccount() async {
    final result = await client.delete('/me');
    if (result != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token');
      await prefs.remove('cached_profile');
    }
    return result ?? {};
  }
}
