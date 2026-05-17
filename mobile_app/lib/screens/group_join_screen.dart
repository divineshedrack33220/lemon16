import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class GroupJoinScreen extends StatefulWidget {
  final String inviteCode;
  const GroupJoinScreen({super.key, required this.inviteCode});

  @override
  State<GroupJoinScreen> createState() => _GroupJoinScreenState();
}

class _GroupJoinScreenState extends State<GroupJoinScreen> {
  bool _isLoading = true;
  bool _isJoining = false;
  Map<String, dynamic>? _groupInfo;
  String? _errorMessage;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkAuthAndLoadGroup();
  }

  Future<void> _checkAuthAndLoadGroup() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Check auth status
      final token = await ApiService.getToken();
      _isLoggedIn = token != null && token.isNotEmpty;

      // Fetch public group info by invite code
      final info = await ApiService.getGroupInfoByInviteCode(widget.inviteCode);
      if (info.containsKey('error')) {
        throw Exception(info['error'] ?? 'Group invitation not found');
      }

      setState(() {
        _groupInfo = info;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _joinGroup() async {
    setState(() {
      _isJoining = true;
    });

    try {
      final res = await ApiService.joinGroupByInviteCode(widget.inviteCode);
      if (res.containsKey('error')) {
        throw Exception(res['error'] ?? 'Failed to join group');
      }

      final chatId = res['chatId'] as String?;
      if (chatId == null || chatId.isEmpty) {
        throw Exception('Failed to retrieve chat session');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Successfully joined group chat!')),
      );

      // Navigate straight to the chat screen
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/feed', // Pop back to base
        (route) => false,
      );
      Navigator.pushNamed(
        context,
        '/chat',
        arguments: {'chatId': chatId},
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
      setState(() {
        _isJoining = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Group Invitation'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorWidget()
              : _buildGroupDetailsWidget(theme),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Invalid Invite Link',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'This invite code is expired or invalid. Please check the URL and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pushReplacementNamed(context, '/feed'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00AEEF),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
              child: const Text('Back to Home'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupDetailsWidget(ThemeData theme) {
    final name = _groupInfo?['groupName']?.toString() ?? 'Group Chat';
    final avatar = _groupInfo?['groupAvatar']?.toString();
    final description = _groupInfo?['groupDescription']?.toString() ?? 'No description provided.';
    final memberCount = _groupInfo?['memberCount'] as int? ?? 0;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 450),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Premium Badge indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF00AEEF).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.stars, color: Color(0xFF00AEEF), size: 16),
                    const SizedBox(width: 6),
                    const Text(
                      'You are Invited!',
                      style: TextStyle(color: Color(0xFF00AEEF), fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Group avatar
              CircleAvatar(
                radius: 54,
                backgroundImage: avatar != null ? CachedNetworkImageProvider(avatar) : null,
                backgroundColor: Colors.grey[200],
                child: avatar == null
                    ? Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'G',
                        style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Color(0xFF00AEEF)),
                      )
                    : null,
              ),
              const SizedBox(height: 20),

              // Group Name
              Text(
                name,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: -0.5),
              ),
              const SizedBox(height: 8),

              // Member count badge
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_alt_rounded, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 6),
                  Text(
                    '$memberCount members',
                    style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Divider
              Container(
                width: 60,
                height: 3,
                decoration: BoxDecoration(
                  color: const Color(0xFF00AEEF).withOpacity(0.3),
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
              const SizedBox(height: 20),

              // Description
              Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 15, height: 1.4),
              ),
              const SizedBox(height: 32),

              // Join Actions depending on authentication
              if (_isLoggedIn)
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isJoining ? null : _joinGroup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00AEEF),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: _isJoining
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'Accept Invitation',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                )
              else
                Column(
                  children: [
                    // Suggest Sign Up to auto-join
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pushNamed(
                            context,
                            '/signup',
                            arguments: {'inviteCode': widget.inviteCode},
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00AEEF),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Sign Up & Join Group',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Suggest Log In
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pushNamed(
                            context,
                            '/login',
                            arguments: {'inviteCode': widget.inviteCode},
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF00AEEF),
                          side: const BorderSide(color: Color(0xFF00AEEF)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text(
                          'Log In & Join',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
