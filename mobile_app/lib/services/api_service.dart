import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';

class ApiService {
  // Use 10.0.2.2 for Android emulator, localhost for iOS/Web
  static String get baseUrl {
    const fromEnv = String.fromEnvironment('API_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    
    // Dynamic Self-Sensing configuration for Web (Render, Heroku, or custom domains)
    if (kIsWeb) {
      final host = Uri.base.host;
      if (host == 'localhost' || host == '127.0.0.1' || host == '0.0.0.0') {
        return 'http://localhost:10000/api';
      }
      // Dynamically resolve to the browser's current hosted origin domain/port
      return '${Uri.base.scheme}://${Uri.base.host}${Uri.base.port != 0 && Uri.base.port != 80 && Uri.base.port != 443 ? ":${Uri.base.port}" : ""}/api';
    }
    
    // For Native Apps (Android / iOS)
    if (kReleaseMode) {
      // Primary hosted production backend API fallback
      return 'https://zukaping.onrender.com/api'; // Swap this for your final production domain if needed
    }
    
    // Android Emulator host loopback fallback in local debug mode
    return 'http://10.0.2.2:10000/api';
  }

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
    final prefs = await SharedPreferences.getInstance();
    try {
      final headers = await getHeaders();
      final response = await http.get(Uri.parse('$baseUrl/me'), headers: headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await prefs.setString('cached_profile', jsonEncode(data));
        return data;
      }
      throw Exception('Server error: ${response.statusCode}');
    } catch (e) {
      print('⚠️ getProfile offline fallback: $e');
      final cached = prefs.getString('cached_profile');
      if (cached != null) {
        return jsonDecode(cached);
      }
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) async {
    final headers = await getHeaders();
    final response = await http.put(
      Uri.parse('$baseUrl/me'),
      headers: headers,
      body: jsonEncode(data),
    );
    final responseData = jsonDecode(response.body);
    if (response.statusCode == 200) {
      // If the backend returned the updated profile, update the cache
      final prefs = await SharedPreferences.getInstance();
      if (responseData['id'] != null) {
        await prefs.setString('cached_profile', jsonEncode(responseData));
      } else {
        // No full profile returned — invalidate the cache so next getProfile always fetches fresh
        await prefs.remove('cached_profile');
      }
    }
    return responseData;
  }

  static Future<List<dynamic>> getFeed() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final headers = await getHeaders();
      final response = await http.get(Uri.parse('$baseUrl/feed'), headers: headers);
      
      if (response.statusCode != 200) {
        throw Exception('Failed to load feed');
      }
      
      final data = jsonDecode(response.body);
      final feedList = data is List ? data : data['posts'] ?? [];
      await prefs.setString('cached_feed', jsonEncode(feedList));
      return feedList;
    } catch (e) {
      print('⚠️ getFeed offline fallback: $e');
      final cached = prefs.getString('cached_feed');
      if (cached != null) {
        return jsonDecode(cached);
      }
      return [];
    }
  }

  static Future<Map<String, dynamic>> createPost(Map<String, dynamic> postData) async {
    final headers = await getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/post'),
      headers: headers,
      body: jsonEncode(postData),
    );
    return jsonDecode(response.body);
  }

  static Future<List<dynamic>> getChats() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final headers = await getHeaders();
      final response = await http.get(Uri.parse('$baseUrl/chats'), headers: headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final chatsList = data is List ? data : data['chats'] ?? [];
        await prefs.setString('cached_chats', jsonEncode(chatsList));
        return chatsList;
      }
      throw Exception('Server error: ${response.statusCode}');
    } catch (e) {
      print('⚠️ getChats offline fallback: $e');
      final cached = prefs.getString('cached_chats');
      if (cached != null) {
        return jsonDecode(cached);
      }
      return [];
    }
  }

  static Future<Map<String, dynamic>> createChat(String userId) async {
    final headers = await getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/chats'),
      headers: headers,
      body: jsonEncode({'participants': [userId]}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> createGroupChat(
    List<String> userIds,
    String groupName, {
    String? groupDescription,
    String? groupAvatar,
  }) async {
    final headers = await getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/chats'),
      headers: headers,
      body: jsonEncode({
        'participants': userIds,
        'isGroup': true,
        'groupName': groupName,
        'groupDescription': groupDescription,
        'groupAvatar': groupAvatar,
      }),
    );
    return jsonDecode(response.body);
  }

  static Future<List<dynamic>> getMessages(String chatId) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final headers = await getHeaders();
      final response = await http.get(Uri.parse('$baseUrl/messages/$chatId'), headers: headers);
      
      if (response.statusCode != 200) {
        throw Exception('Failed to load messages');
      }
      
      final data = jsonDecode(response.body);
      final messagesList = data is List 
          ? data.cast<Map<String, dynamic>>() 
          : (data['messages'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          
      await prefs.setString('cached_messages_$chatId', jsonEncode(messagesList));
      return messagesList;
    } catch (e) {
      print('⚠️ getMessages offline fallback for chat $chatId: $e');
      final cached = prefs.getString('cached_messages_$chatId');
      if (cached != null) {
        final decoded = jsonDecode(cached);
        return decoded is List ? decoded : [];
      }
      return [];
    }
  }

  static Future<Map<String, dynamic>> sendMessage(String chatId, String content, {String type = 'text'}) async {
    final headers = await getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/message'),
      headers: headers,
      body: jsonEncode({
        'chatId': chatId, 
        'content': content,
        'type': type,
      }),
    );
    return jsonDecode(response.body);
  }

  static Future<List<dynamic>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final headers = await getHeaders();
      final response = await http.get(Uri.parse('$baseUrl/favorites'), headers: headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data is List ? data : data['favorites'] ?? [];
        await prefs.setString('cached_favorites', jsonEncode(list));
        return list;
      }
      throw Exception('Server error: ${response.statusCode}');
    } catch (e) {
      print('⚠️ getFavorites offline fallback: $e');
      final cached = prefs.getString('cached_favorites');
      if (cached != null) {
        return jsonDecode(cached);
      }
      return [];
    }
  }

  static Future<Map<String, dynamic>> toggleFavorite(String userId) async {
    final headers = await getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/favorite'),
      headers: headers,
      body: jsonEncode({'targetUserId': userId}),
    );
    return jsonDecode(response.body);
  }

  static Future<List<dynamic>> getNearbyUsers(double lat, double lng) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final headers = await getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/users/nearby?lat=$lat&lng=$lng'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data is List ? data.cast<Map<String, dynamic>>() : (data['users'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        await prefs.setString('cached_nearby_users', jsonEncode(list));
        return list;
      }
      throw Exception('Server error: ${response.statusCode}');
    } catch (e) {
      print('⚠️ getNearbyUsers offline fallback: $e');
      final cached = prefs.getString('cached_nearby_users');
      if (cached != null) {
        final decoded = jsonDecode(cached);
        return decoded is List ? decoded : [];
      }
      return [];
    }
  }

  static Future<List<dynamic>> searchUsers(String query) async {
    final headers = await getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/users/search?q=${Uri.encodeComponent(query)}'),
      headers: headers,
    );
    final data = jsonDecode(response.body);
    return data is List ? data : (data['users'] as List?) ?? [];
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
      } else {
        print('Upload failed with status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error uploading image: $e');
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
    final response = await http.post(
      Uri.parse('$baseUrl/messages/$messageId/react'),
      headers: await getHeaders(),
      body: json.encode({'emoji': emoji}),
    );
    return response.statusCode == 200;
  }

  static Future<Map<String, dynamic>> blockUser(String userId) async {
    final headers = await getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/block'),
      headers: headers,
      body: jsonEncode({'targetUserId': userId}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> updateGroupChat(
    String chatId, {
    String? groupName,
    String? groupDescription,
    String? groupAvatar,
  }) async {
    final headers = await getHeaders();
    final body = <String, dynamic>{};
    if (groupName != null) body['groupName'] = groupName;
    if (groupDescription != null) body['groupDescription'] = groupDescription;
    if (groupAvatar != null) body['groupAvatar'] = groupAvatar;

    final response = await http.put(
      Uri.parse('$baseUrl/chats/$chatId'),
      headers: headers,
      body: jsonEncode(body),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> promoteToAdmin(String chatId, String targetUserId) async {
    final headers = await getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/chats/$chatId/admin'),
      headers: headers,
      body: jsonEncode({'targetUserId': targetUserId}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> removeGroupMember(String chatId, String userId) async {
    final headers = await getHeaders();
    final response = await http.delete(
      Uri.parse('$baseUrl/chats/$chatId/participants/$userId'),
      headers: headers,
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> generateGroupInviteCode(String chatId) async {
    final headers = await getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/chats/$chatId/invite'),
      headers: headers,
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getGroupInfoByInviteCode(String code) async {
    final response = await http.get(
      Uri.parse('$baseUrl/groups/invite/$code'),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> joinGroupByInviteCode(String code) async {
    final headers = await getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/groups/join'),
      headers: headers,
      body: jsonEncode({'inviteCode': code}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> addGroupMember(String chatId, String userId) async {
    final headers = await getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/chats/$chatId/participants'),
      headers: headers,
      body: jsonEncode({'userId': userId}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> deleteAccount() async {
    final headers = await getHeaders();
    final response = await http.delete(
      Uri.parse('$baseUrl/me'),
      headers: headers,
    );

    // If the backend succeeded we clear local data
    if (response.statusCode == 200) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token');
      await prefs.remove('cached_profile');
      // Clear bottom-nav cache as well by removing all cached stuff.
      // Ideally we call CustomBottomNavBar.clearCache() but since it's a static UI method
      // it's cleaner to handle this in the UI layer. The profile cache removal is good enough here.
    }

    return jsonDecode(response.body);
  }
}
