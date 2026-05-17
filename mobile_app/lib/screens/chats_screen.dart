import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../models/chat.dart';
import 'chat_screen.dart';
import '../widgets/app_logo.dart';
import '../services/notification_service.dart';
import '../services/sound_service.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> with WidgetsBindingObserver {
  List<Chat> _allChats = [];
  List<Chat> _filteredChats = [];
  bool _isLoading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();
  Timer? _refreshTimer;
  String? _currentUserId;
  Map<String, bool> _typingUsers = {};
  Map<String, Timer> _typingTimeouts = {};
  StreamSubscription<Map<String, dynamic>>? _wsSubscription;

  // Status management
  int _currentStatusIndex = 0;
  final List<Map<String, String>> _statuses = [
    {'text': 'Available', 'class': 'available', 'value': 'available'},
    {'text': 'Busy', 'class': 'busy', 'value': 'busy'},
    {'text': 'Ghost', 'class': 'ghost', 'value': 'ghost'},
    {'text': 'Super', 'class': 'super', 'value': 'super'},
    {'text': 'Offline', 'class': 'offline', 'value': 'offline'},
  ];

  bool get _isGhostMode => _statuses[_currentStatusIndex]['value'] == 'ghost';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchController.addListener(_filterChats);
    _initializeChats();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _refreshTimer?.cancel();
    _wsSubscription?.cancel();
    _typingTimeouts.forEach((key, timer) => timer.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadChats();
    }
  }

  Future<void> _initializeChats() async {
    final token = await ApiService.getToken();
    if (token == null) {
      _navigateToLogin();
      return;
    }

    try {
      final parts = token.split('.');
      if (parts.length == 3) {
        final payload = json.decode(
          utf8.decode(base64.decode(base64.normalize(parts[1])))
        );
        _currentUserId = payload['userId'] ?? payload['sub'] ?? payload['id'];
      }
    } catch (e) {
      print('Error decoding token: $e');
    }

    await Future.wait([
      _loadChats(),
      _loadUserStatus(),
    ]);

    _setupWebSocket();
  }

  Future<void> _loadUserStatus() async {
    try {
      final profile = await ApiService.getProfile();
      if (mounted) {
        final status = profile['status'] ?? 'available';
        final index = _statuses.indexWhere((s) => s['value'] == status);
        if (index != -1) {
          setState(() => _currentStatusIndex = index);
        }
      }
    } catch (e) {
      print('Error loading status: $e');
    }
  }

  Future<void> _updateStatus() async {
    final newIndex = (_currentStatusIndex + 1) % _statuses.length;
    final newStatus = _statuses[newIndex]['value']!;
    
    setState(() => _currentStatusIndex = newIndex);
    
    try {
      await ApiService.updateProfile({'status': newStatus});
      _showToast('Status changed to ${_statuses[newIndex]['text']}');
      
      WebSocketService.send({
        'type': 'status_update',
        'status': newStatus,
        'userId': _currentUserId,
      });
    } catch (e) {
      setState(() {
        _currentStatusIndex = (_currentStatusIndex + 2) % _statuses.length;
      });
      _showToast('Failed to update status');
    }
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) {
        _loadChats();
      },
    );
  }

  void _setupWebSocket() {
    _wsSubscription = WebSocketService.stream.listen((data) {
      final type = data['type'] as String?;
      final payload = data['payload'] as Map<String, dynamic>?;

      if (!mounted) return;

      switch (type) {
        case 'new_message':
          _handleNewMessage(payload);
          break;
        case 'message_read':
          _handleMessageRead(payload);
          break;
        case 'typing_start':
          _handleTypingStart(payload);
          break;
        case 'typing_end':
          _handleTypingEnd(payload);
          break;
        case 'user_status_update':
          _handleUserStatusUpdate(payload);
          break;
        case 'chat_created':
          _handleChatCreated(payload);
          break;
      }
    });
  }

  void _handleNewMessage(Map<String, dynamic>? payload) {
    if (payload == null) return;
    final chatId = payload['chatId'] as String?;
    if (chatId == null) return;

    setState(() {
      final index = _allChats.indexWhere((c) => c.id == chatId);
      if (index != -1) {
        var chat = _allChats.removeAt(index);
        chat = chat.copyWith(
          lastMessage: payload['content'] ?? '',
          lastMessageTime: DateTime.fromMillisecondsSinceEpoch((payload['createdAt'] ?? 0) * 1000),
        );
        _allChats.insert(0, chat);
        _filterChats();
        
        if (payload['senderId'] != _currentUserId) {
          SoundService.playReceived();
          NotificationService.showNotification(
            id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            title: chat.partnerName,
            body: payload['content'] ?? 'New message',
            payload: 'chat_$chatId',
          );
        }
      } else {
        _loadChats();
        if (payload['senderId'] != _currentUserId) {
          NotificationService.showNotification(
            id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            title: 'New Message',
            body: payload['content'] ?? 'You received a new message',
            payload: 'chat_$chatId',
          );
        }
      }
    });
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.fixed,
        backgroundColor: const Color(0xFF00AEEF),
      ),
    );
  }

  void _handleMessageRead(Map<String, dynamic>? payload) {
    if (payload == null) return;
    final chatId = payload['chatId'] as String?;
    if (chatId == null) return;
    _loadChats();
  }

  void _handleTypingStart(Map<String, dynamic>? payload) {
    if (payload == null) return;
    final chatId = payload['chatId'] as String?;
    final userId = payload['userId'] as String?;
    if (chatId == null || userId == null || userId == _currentUserId) return;

    setState(() => _typingUsers[chatId] = true);
    _typingTimeouts[chatId]?.cancel();
    _typingTimeouts[chatId] = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _typingUsers[chatId] = false);
    });
  }

  void _handleTypingEnd(Map<String, dynamic>? payload) {
    if (payload == null) return;
    final chatId = payload['chatId'] as String?;
    if (chatId == null) return;
    setState(() => _typingUsers[chatId] = false);
    _typingTimeouts[chatId]?.cancel();
  }

  void _handleUserStatusUpdate(Map<String, dynamic>? payload) {
    if (payload == null) return;
    final userId = payload['userId'] as String?;
    final status = payload['status'] as String?;
    if (userId == null || status == null) return;

    final bool? isOnline = payload['isOnline'] as bool?;

    setState(() {
      _allChats = _allChats.map((chat) {
        if (chat.partnerId == userId) {
          return chat.copyWith(
            partnerStatus: status,
            isOnline: isOnline ?? false,
          );
        }
        return chat;
      }).toList();
      _filterChats();
    });
  }

  void _handleChatCreated(Map<String, dynamic>? payload) {
    _loadChats();
  }

  Future<void> _loadChats() async {
    try {
      final chatsData = await ApiService.getChats();
      if (mounted) {
        setState(() {
          _allChats = chatsData.map((c) => Chat.fromJson(c)).toList();
          _allChats.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
          _filterChats();
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load chats';
        });
      }
    }
  }

  void _filterChats() {
    setState(() {
      final query = _searchController.text.toLowerCase().trim();
      if (query.isEmpty) {
        _filteredChats = List.from(_allChats);
      } else {
        _filteredChats = _allChats.where((chat) {
          return chat.partnerName.toLowerCase().contains(query) ||
                 chat.lastMessage.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  void _navigateToChat(Chat chat) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(chatId: chat.id),
      ),
    ).then((_) => _loadChats());
  }

  void _navigateToLogin() {
    Navigator.pushReplacementNamed(context, '/login');
  }

  String _formatTimestamp(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${dateTime.day}/${dateTime.month}';
  }

  String _getLastMessagePreview(Chat chat) {
    if (chat.lastMessage.isEmpty) return 'No messages yet';
    if (chat.lastMessageType == 'image') return '📷 Photo';
    return chat.lastMessage.length > 30 ? '${chat.lastMessage.substring(0, 30)}...' : chat.lastMessage;
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'available':
      case 'online': return const Color(0xFF00AEEF);
      case 'busy': return const Color(0xFFFFFF00);
      case 'super': return Colors.deepPurpleAccent;
      case 'ghost': return Colors.grey.withOpacity(0.5);
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        leading: const AppLogo(),
        actions: [_buildStatusIndicator()],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: _isLoading
                ? _buildShimmerLoading()
                : _error != null
                    ? _buildErrorState()
                    : _filteredChats.isEmpty
                        ? _buildEmptyState()
                        : _buildChatList(),
          ),
        ],
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentRoute: '/chats',
        chatsCount: _allChats.fold<int>(0, (sum, chat) => sum + (chat.unreadCount)),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'createGroup',
            onPressed: _showCreateGroupModal,
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF00AEEF),
            elevation: 4,
            child: const Icon(Icons.group_add_rounded),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'searchUsers',
            onPressed: _showGlobalSearchModal,
            backgroundColor: const Color(0xFF00AEEF),
            foregroundColor: Colors.white,
            elevation: 4,
            child: const Icon(Icons.person_add_alt_1_rounded),
          ),
        ],
      ),
    );
  }

  void _showGlobalSearchModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _GlobalUserSearchModal(),
    );
  }

  void _showCreateGroupModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _CreateGroupModal(),
    );
  }

  Widget _buildStatusIndicator() {
    final status = _statuses[_currentStatusIndex];
    Color dotColor;
    switch (status['class']) {
      case 'available': dotColor = const Color(0xFF00AEEF); break;
      case 'busy': dotColor = const Color(0xFFFFFF00); break;
      case 'ghost': dotColor = Colors.grey.withOpacity(0.5); break;
      case 'super': dotColor = Colors.deepPurpleAccent; break;
      default: dotColor = Colors.grey;
    }
    
    return GestureDetector(
      onTap: _updateStatus,
      child: Container(
        margin: const EdgeInsets.only(right: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Opacity(
          opacity: _isGhostMode ? 0.6 : 1.0,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                _isGhostMode ? 'Stealth' : status['text']!,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: '🔍 Search chats by name or message...',
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
          filled: true,
          fillColor: Colors.grey[100],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: 4,
      itemBuilder: (context, index) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(width: 56, height: 56, decoration: const BoxDecoration(color: Color(0xFFF5F5F5), shape: BoxShape.circle)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(width: 120, height: 16, decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(8))),
                    const SizedBox(height: 8),
                    Container(width: 200, height: 14, decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(8))),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 60, color: Colors.grey),
          const SizedBox(height: 16),
          Text(_error ?? 'Unknown error', style: const TextStyle(color: Colors.grey)),
          TextButton(onPressed: _loadChats, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final hasSearch = _searchController.text.isNotEmpty;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('💬', style: TextStyle(fontSize: 60)),
          const SizedBox(height: 16),
          Text(hasSearch ? 'No results found' : 'No chats yet', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          if (hasSearch) TextButton(onPressed: () => _searchController.clear(), child: const Text('Clear search')),
        ],
      ),
    );
  }

  Widget _buildChatList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: _filteredChats.length,
      itemBuilder: (context, index) {
        final chat = _filteredChats[index];
        final isTyping = _typingUsers[chat.id] == true;

        return InkWell(
          onTap: () => _navigateToChat(chat),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: chat.unreadCount > 0 ? const Color(0xFF00AEEF).withOpacity(0.05) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    if (!chat.isGroup && chat.partnerId.isNotEmpty) {
                      HapticFeedback.lightImpact();
                      Navigator.pushNamed(
                        context,
                        '/view-profile',
                        arguments: {'userId': chat.partnerId},
                      );
                    }
                  },
                  child: Stack(
                    children: [
                      Container(
                        width: 60, height: 60,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFF5F5F5)),
                        child: ClipOval(
                          child: chat.isOnline
                              ? _PulseAvatar(imageUrl: chat.partnerAvatar, userPhotos: chat.partnerPhotos, userName: chat.partnerName)
                              : ((chat.partnerAvatar != null && chat.partnerAvatar!.isNotEmpty)
                                  ? CachedNetworkImage(
                                      imageUrl: chat.partnerAvatar!,
                                      fit: BoxFit.cover,
                                      errorWidget: (context, url, error) => _buildPlaceholderAvatar(chat.partnerName),
                                    )
                                  : (chat.partnerPhotos.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: chat.partnerPhotos.first,
                                          fit: BoxFit.cover,
                                          errorWidget: (context, url, error) => _buildPlaceholderAvatar(chat.partnerName),
                                        )
                                      : _buildPlaceholderAvatar(chat.partnerName))),
                        ),
                      ),
                      if (chat.isOnline && !isTyping)
                        Positioned(
                          bottom: 2, right: 2,
                          child: Container(
                            width: 14, height: 14,
                            decoration: BoxDecoration(
                              color: _getStatusColor(chat.partnerStatus ?? 'offline'),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(chat.partnerName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      if (isTyping) _buildTypingIndicator() else Text(_getLastMessagePreview(chat), style: TextStyle(color: Colors.grey[600]), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_formatTimestamp(chat.lastMessageTime), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    if (chat.unreadCount > 0)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFF00AEEF), borderRadius: BorderRadius.circular(10)),
                        child: Text('${chat.unreadCount}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTypingIndicator() {
    return Row(
      children: [
        const Text('Typing', style: TextStyle(color: Color(0xFF00AEEF), fontWeight: FontWeight.bold)),
        const SizedBox(width: 4),
        _TypingDots(),
      ],
    );
  }

  Widget _buildPlaceholderAvatar(String name) {
    return Container(
      color: const Color(0xFF00AEEF).withOpacity(0.1),
      alignment: Alignment.center,
      child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF00AEEF))),
    );
  }
}

class _TypingDots extends StatefulWidget {
  @override State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }
  @override void dispose() { _controller.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          children: List.generate(3, (index) {
            double opacity = 0.3;
            double val = (_controller.value * 3 - index);
            if (val >= 0 && val <= 1) opacity = 0.3 + (0.7 * val);
            else if (val > 1 && val <= 2) opacity = 1.0 - (0.7 * (val - 1));
            return Container(margin: const EdgeInsets.symmetric(horizontal: 1), width: 4, height: 4, decoration: BoxDecoration(color: const Color(0xFF00AEEF).withOpacity(opacity), shape: BoxShape.circle));
          }),
        );
      },
    );
  }
}

class _PulseAvatar extends StatefulWidget {
  final String? imageUrl;
  final List<String> userPhotos;
  final String userName;
  const _PulseAvatar({this.imageUrl, this.userPhotos = const [], required this.userName});
  @override State<_PulseAvatar> createState() => _PulseAvatarState();
}

class _PulseAvatarState extends State<_PulseAvatar> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }
  @override void dispose() { _controller.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    final effectiveImageUrl = (widget.imageUrl != null && widget.imageUrl!.isNotEmpty)
        ? widget.imageUrl
        : (widget.userPhotos.isNotEmpty ? widget.userPhotos.first : null);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: const Color(0xFF00AEEF).withOpacity(1.0 - _controller.value), blurRadius: _controller.value * 10, spreadRadius: _controller.value * 5)]),
          child: effectiveImageUrl != null
              ? CachedNetworkImage(
                  imageUrl: effectiveImageUrl,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => Container(
                    color: const Color(0xFF00AEEF).withOpacity(0.1),
                    alignment: Alignment.center,
                    child: Text(
                      widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF00AEEF)),
                    ),
                  ),
                )
              : Container(
                  color: const Color(0xFF00AEEF).withOpacity(0.1),
                  alignment: Alignment.center,
                  child: Text(
                    widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF00AEEF)),
                  ),
                ),
        );
      },
    );
  }
}

class _GlobalUserSearchModal extends StatefulWidget {
  const _GlobalUserSearchModal();

  @override
  State<_GlobalUserSearchModal> createState() => _GlobalUserSearchModalState();
}

class _GlobalUserSearchModalState extends State<_GlobalUserSearchModal> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _searchResults = [];
  bool _isSearching = false;
  Timer? _debounce;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (query.trim().isNotEmpty) {
        _performSearch(query.trim());
      } else {
        setState(() {
          _searchResults = [];
        });
      }
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() => _isSearching = true);
    try {
      final results = await ApiService.searchUsers(query);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  void _startChat(String targetUserId) async {
    try {
      final response = await ApiService.createChat(targetUserId);
      if (mounted && response != null) {
        Navigator.pop(context); // Close search modal
        Navigator.pushNamed(context, '/chat', arguments: {'chatId': response['chatId']});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start chat')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 48,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2.5),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Find Friends',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search by name...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator())
                : _searchResults.isEmpty
                    ? Center(
                        child: Text(
                          _searchController.text.isEmpty
                              ? 'Type a name to search globally'
                              : 'No users found',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final user = _searchResults[index];
                          final name = user['name'] ?? 'Unknown';
                          final avatar = user['avatar'];
                          final id = user['id'] ?? user['_id'];

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                            leading: CircleAvatar(
                              radius: 26,
                              backgroundColor: const Color(0xFFF5F5F5),
                              backgroundImage: avatar != null ? CachedNetworkImageProvider(avatar) : null,
                              child: avatar == null
                                  ? Text(
                                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                                      style: const TextStyle(
                                        color: Color(0xFF00AEEF),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  : null,
                            ),
                            title: Text(
                              name,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                            ),
                            subtitle: Text(
                              '@${name.toLowerCase().replaceAll(' ', '')}',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                            trailing: ElevatedButton(
                              onPressed: () => _startChat(id),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00AEEF),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                minimumSize: const Size(0, 36),
                              ),
                              child: const Text('Chat'),
                            ),
                            onTap: () {
                              Navigator.pushNamed(context, '/view-profile', arguments: {'userId': id});
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _CreateGroupModal extends StatefulWidget {
  const _CreateGroupModal();

  @override
  State<_CreateGroupModal> createState() => _CreateGroupModalState();
}

class _CreateGroupModalState extends State<_CreateGroupModal> {
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _groupDescController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  
  List<dynamic> _searchResults = [];
  List<dynamic> _selectedUsers = [];
  bool _isSearching = false;
  bool _isCreating = false;
  Timer? _debounce;
  
  Uint8List? _groupAvatarBytes;
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _groupNameController.dispose();
    _groupDescController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (query.trim().isNotEmpty) {
        _performSearch(query.trim());
      } else {
        setState(() {
          _searchResults = [];
        });
      }
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() => _isSearching = true);
    try {
      final results = await ApiService.searchUsers(query);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _toggleUserSelection(dynamic user) {
    setState(() {
      final id = user['id'] ?? user['_id'];
      final exists = _selectedUsers.any((u) => (u['id'] ?? u['_id']) == id);
      if (exists) {
        _selectedUsers.removeWhere((u) => (u['id'] ?? u['_id']) == id);
      } else {
        _selectedUsers.add(user);
      }
    });
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _groupAvatarBytes = bytes;
        });
      }
    } catch (e) {
      // Ignored
    }
  }

  Future<void> _createGroup() async {
    final groupName = _groupNameController.text.trim();
    final groupDesc = _groupDescController.text.trim();
    if (groupName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a group name')));
      return;
    }
    if (_selectedUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select at least one member')));
      return;
    }

    setState(() => _isCreating = true);

    try {
      String? groupAvatarUrl;
      if (_groupAvatarBytes != null) {
        groupAvatarUrl = await ApiService.uploadImage(_groupAvatarBytes!, 'group_avatar.jpg');
      }

      final userIds = _selectedUsers.map<String>((u) => (u['id'] ?? u['_id']).toString()).toList();
      final response = await ApiService.createGroupChat(
        userIds, 
        groupName,
        groupDescription: groupDesc.isNotEmpty ? groupDesc : null,
        groupAvatar: groupAvatarUrl,
      );
      
      if (mounted && response.containsKey('id')) {
        Navigator.pop(context);
        Navigator.pushNamed(context, '/chat', arguments: {'chatId': response['id']});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to create group')));
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 48,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2.5),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'New Group Chat',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          
          // Group Avatar Picker
          GestureDetector(
            onTap: _pickImage,
            child: CircleAvatar(
              radius: 40,
              backgroundColor: Colors.grey[200],
              backgroundImage: _groupAvatarBytes != null ? MemoryImage(_groupAvatarBytes!) : null,
              child: _groupAvatarBytes == null
                  ? const Icon(Icons.add_a_photo, size: 30, color: Colors.grey)
                  : null,
            ),
          ),
          const SizedBox(height: 16),

          // Group Name Input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _groupNameController,
              decoration: InputDecoration(
                hintText: 'Group Name',
                prefixIcon: const Icon(Icons.group, color: Colors.grey),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Group Description Input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _groupDescController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Group Description (Optional)',
                prefixIcon: const Icon(Icons.description, color: Colors.grey),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Selected Users List
          if (_selectedUsers.isNotEmpty) ...[
            SizedBox(
              height: 80,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _selectedUsers.length,
                itemBuilder: (context, index) {
                  final user = _selectedUsers[index];
                  final name = user['name'] ?? 'User';
                  final avatar = user['avatar'];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Stack(
                      children: [
                        Column(
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundImage: avatar != null ? CachedNetworkImageProvider(avatar) : null,
                              backgroundColor: Colors.grey[200],
                              child: avatar == null ? Text(name[0].toUpperCase()) : null,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              name.length > 8 ? '${name.substring(0, 8)}...' : name,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: GestureDetector(
                            onTap: () => _toggleUserSelection(user),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const Divider(),
          ],

          // Search Input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search members to add...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Search Results
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator())
                : _searchResults.isEmpty
                    ? Center(
                        child: Text(
                          _searchController.text.isEmpty
                              ? 'Type to search users'
                              : 'No users found',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final user = _searchResults[index];
                          final name = user['name'] ?? 'Unknown';
                          final avatar = user['avatar'];
                          final id = user['id'] ?? user['_id'];
                          final isSelected = _selectedUsers.any((u) => (u['id'] ?? u['_id']) == id);

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                            leading: CircleAvatar(
                              radius: 26,
                              backgroundColor: const Color(0xFFF5F5F5),
                              backgroundImage: avatar != null ? CachedNetworkImageProvider(avatar) : null,
                              child: avatar == null
                                  ? Text(
                                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                                      style: const TextStyle(
                                        color: Color(0xFF00AEEF),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  : null,
                            ),
                            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('@${name.toLowerCase().replaceAll(' ', '')}', style: TextStyle(color: Colors.grey[600])),
                            trailing: isSelected
                                ? const Icon(Icons.check_circle, color: Color(0xFF00AEEF))
                                : const Icon(Icons.circle_outlined, color: Colors.grey),
                            onTap: () => _toggleUserSelection(user),
                          );
                        },
                      ),
          ),

          // Create Button
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isCreating ? null : _createGroup,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00AEEF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                  elevation: 0,
                ),
                child: _isCreating
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(
                        'Create Group (${_selectedUsers.length})',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}