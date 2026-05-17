import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' as io;
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:shimmer/shimmer.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../services/sound_service.dart';
import '../models/message.dart';

class ChatScreen extends StatefulWidget {
  final String? chatId;
  final String? userId;

  const ChatScreen({super.key, this.chatId, this.userId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final FocusNode _focusNode = FocusNode();

  List<Message> _messages = [];
  List<XFile> _pendingImages = [];
  final Map<String, Uint8List> _pendingImageBytes = {};
  List<XFile>? _stagedImages;
  List<Uint8List>? _stagedBytes;
  Map<String, double> _uploadProgress = {};
  
  bool _isLoading = true;
  bool _isTyping = false;
  bool _showEmojiPicker = false;
  bool _isIcebreakerVisible = true;
  bool? _isUploading;
  int? _uploadingCount;
  int? _uploadedCount;
  String _activeEmojiCategory = 'smileys';

  static const Map<String, List<String>> _emojiCategories = {
    'smileys':   ['😀','😁','😂','🤣','😃','😄','😅','😆','😉','😊','😋','😎','😍','🥰','😘','😗','😙','😚','🤗','🤩','😏','😒','😞','😔','😟','😕','🙁','☹️','😣','😖','😫','😩','🥺','😢','😭','😤','😠','😡','🤬','🤯','😳','🥵','🥶','😱','😨','😰','😥','😓','🤭','🤫','🤔','🤐','🤨','😐','😑','😶','😶‍🌫️','😄','🥱','😴','🤤','😪','😵','😵‍💫','🤠','🥳','😎','🤓','🧐'],
    'people':    ['👋','🤚','🖐️','✋','🖖','👌','🤌','🤏','✌️','🤞','🤟','🤘','🤙','👈','👉','👆','🖕','👇','☝️','👍','👎','✊','👊','🤛','🤜','👏','🙌','👐','🤲','🤝','🙏','✍️','💅','🤳','💪','🦾','🦵','🦶','👂','🦻','👃','🫀','🫁','🧠','🦷','🦴','👀','👁️','👅','👄','💋','💘','❤️','🧡','💛','💚','💙','💜','🖤','🤍','🤎'],
    'animals':   ['🐶','🐱','🐭','🐹','🐰','🦊','🐻','🐼','🐨','🐯','🦁','🐮','🐷','🐸','🐵','🙈','🙉','🙊','🐔','🐧','🐦','🐤','🦆','🦅','🦉','🦇','🐺','🐗','🐴','🦄','🐝','🐛','🦋','🐌','🐞','🐜','🦟','🦗','🕷️','🐢','🐍','🦎','🦖','🦕','🐙','🦑','🦐','🦞','🦀','🐡','🐠','🐟','🐬','🐳','🐋','🦈','🐊','🐅','🐆','🦓','🦍','🦧','🦣','🐘','🦛','🦏','🐪','🐫','🦒','🦘'],
    'nature':    ['🌸','🌺','🌹','🌻','🌼','💐','🌷','🍀','🌿','🌱','🌲','🌳','🌴','🎋','🎍','🍂','🍁','🍃','🍄','🌾','🐚','🌊','🌬️','🌀','🌈','☁️','⛅','🌤️','⛈️','🌧️','❄️','⛄','🔥','💧','🌙','☀️','⭐','🌟','💫','✨','☄️','🌍','🌎','🌏','🪐','🌑','🌕'],
    'food':      ['🍕','🍔','🍟','🌭','🥪','🥙','🧆','🌮','🌯','🫔','🥗','🥘','🫕','🥫','🍝','🍜','🍲','🍛','🍣','🍱','🥟','🦪','🍤','🍙','🍚','🍘','🍥','🥮','🍢','🧁','🍰','🎂','🍮','🍭','🍬','🍫','🍿','🍩','🍪','🌰','🥜','🍯','🧂','🥓','🥚','🍳','🧈','🥞','🧇','🥐','🍞','🥖','🥨','🧀','🥗','🥙','🫙','🍦','🍧','🍨','🍺','🍻','🥂','🍷','🥃','🍸','🍹','🧃','🥤','🧋','☕','🫖','🍵','🧉'],
    'travel':    ['✈️','🚀','🛸','🚁','🛶','⛵','🚤','🛥️','🛳️','⛴️','🚢','🚂','🚃','🚄','🚅','🚆','🚇','🚈','🚉','🚊','🚝','🚞','🚋','🚌','🚍','🚎','🏎️','🚓','🚑','🚒','🚐','🛻','🚚','🚛','🚜','🛵','🏍️','🚲','🛺','🚨','🚔','🚍','🚘','🚖','🛡️','🗺️','🧭','🏔️','⛰️','🌋','🗻','🏕️','🏖️','🏗️','🏘️','🏚️','🏠','🏡','🏢','🏣','🏤','🏥','🏦','🏨','🏩','🏪','🏫','🏬','🏭','🏯','🏰','💒','🗼','🗽','⛪','🕌','🛕','🕍','⛩️','🕋'],
    'objects':   ['💎','💍','👑','🎩','🪄','🔮','🎭','🖼️','🎨','🪅','🎪','🎢','🎠','🎡','🎬','🎥','📷','📸','📹','🎞️','📞','☎️','📟','📺','📻','🧭','⏱️','⏰','⏲️','🕰️','🗓️','📅','📆','📊','📈','📉','📋','📁','📂','🗂️','🗃️','🗄️','🗑️','🔒','🔓','🔏','🔐','🔑','🗝️','🔨','🪓','⛏️','⚒️','🛠️','🗡️','⚔️','🛡️','🔧','🔩','⚙️','🗜️','🔗','⛓️','🧲','🪜','🧰','🪣','💡','🔦','🕯️','🪔'],
    'symbols':   ['❤️','🧡','💛','💚','💙','💜','🖤','🤍','🤎','💕','💞','💓','💗','💖','💘','💝','💟','☮️','✝️','☪️','🕉️','☸️','✡️','🔯','🕎','☯️','☦️','🛐','⛎','♈','♉','♊','♋','♌','♍','♎','♏','♐','♑','♒','♓','🆔','⚛️','🈳','🈹','🈚','🈸','🈺','🈷️','✴️','🆚','💮','🉐','㊙️','㊗️','🈴','🈵','🆓','🆙','🆒','🆕','🆖','🅰️','🅱️','🆎','🆑','🅾️','🆘','❌','⭕','🛑','⛔','📛','🚫','💯','✅'],
  };
  
  String? _currentUserId;
  String? _partnerId;
  String? _partnerName;
  String? _partnerAvatar;
  List<String> _partnerPhotos = [];
  String? _partnerStatus;
  String? _actualChatId;
  bool _isPartnerOnline = false;
  
  // Group info
  String? _groupDescription;
  List<String> _groupAdminIds = [];
  List<dynamic> _groupParticipants = [];
  
  StreamSubscription<Map<String, dynamic>>? _wsSubscription;
  Timer? _typingTimer;

  // Effects
  AnimationController? _effectController;
  String? _activeEffect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _effectController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    _initializeChat();
    _setupWebSocket();
    
    _stagedImages ??= [];
    _stagedBytes ??= [];
    _isUploading ??= false;
    _uploadingCount ??= 0;
    _uploadedCount ??= 0;

    _messageController.addListener(() {
      setState(() {});
      _handleTyping();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wsSubscription?.cancel();
    _typingTimer?.cancel();
    _effectController?.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _initializeChat() async {
    final token = await ApiService.getToken();
    if (token == null) return;

    try {
      final parts = token.split('.');
      if (parts.length == 3) {
        final payload = json.decode(utf8.decode(base64.decode(base64.normalize(parts[1]))));
        _currentUserId = payload['userId'] ?? payload['sub'] ?? payload['id'];
      }
    } catch (e) {}

    await _loadChatHeader();
    await _loadMessages();
  }

  Future<void> _loadChatHeader() async {
    try {
      final chatId = widget.chatId;
      final userId = widget.userId;

      if (chatId != null) {
        final response = await http.get(
          Uri.parse('${ApiService.baseUrl}/chats/$chatId'),
          headers: await ApiService.getHeaders(),
        );

        if (response.statusCode == 200) {
          final chat = json.decode(response.body);
          final isGroup = chat['isGroup'] == true;
          final partner = chat['partner'] ?? chat['participants']?.firstWhere((p) => p['_id'] != _currentUserId, orElse: () => null);
          
          setState(() {
            _actualChatId = chat['id'] ?? chat['_id'] ?? chatId;
            if (isGroup) {
              _partnerName = chat['groupName'] ?? 'Group Chat';
              _partnerAvatar = chat['groupAvatar'];
              _partnerStatus = 'group';
              _isPartnerOnline = false;
              _groupDescription = chat['groupDescription'];
              _groupAdminIds = (chat['adminIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
              _groupParticipants = chat['participantsProfiles'] as List<dynamic>? ?? [];
            } else if (partner != null) {
              _partnerId = partner['id'] ?? partner['_id'];
              _partnerName = partner['name'];
              _partnerAvatar = partner['avatar'];
              _partnerStatus = partner['status'] ?? 'offline';
              _isPartnerOnline = partner['isOnline'] == true;
              _partnerPhotos = (partner['photos'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
            }
          });
        }
      } else if (userId != null) {
        final response = await http.get(
          Uri.parse('${ApiService.baseUrl}/user/$userId'),
          headers: await ApiService.getHeaders(),
        );

        if (response.statusCode == 200) {
          final user = json.decode(response.body);
          setState(() {
            _partnerId = user['_id'] ?? userId;
            _partnerName = user['name'];
            _partnerAvatar = user['avatar'];
            _partnerStatus = user['status'] ?? 'offline';
            _isPartnerOnline = user['isOnline'] == true;
            _partnerPhotos = (user['photos'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
          });

          final createRes = await http.post(
            Uri.parse('${ApiService.baseUrl}/chats'),
            headers: await ApiService.getHeaders(),
            body: json.encode({'participants': [userId]}),
          );

          if (createRes.statusCode == 200 || createRes.statusCode == 201) {
            final chat = json.decode(createRes.body);
            _actualChatId = chat['_id'];
          }
        }
      }
    } catch (e) {
      print('Header error: $e');
    }
  }

  Future<void> _loadMessages() async {
    if (_actualChatId == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final messages = await ApiService.getMessages(_actualChatId!);
      if (mounted) {
        setState(() {
          _messages = messages.map((m) => Message.fromJson(m)).toList().reversed.toList();
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setupWebSocket() {
    _wsSubscription = WebSocketService.stream.listen((data) {
      _handleWebSocketMessage(data);
    });
    if (_actualChatId != null) {
      WebSocketService.send({
        'type': 'subscribe_chat',
        'payload': {'chatId': _actualChatId},
      });
    }
  }

  void _handleWebSocketMessage(Map<String, dynamic> data) {
    final type = data['type'];
    final payload = data['payload'];
    if (!mounted) return;

    switch (type) {
      case 'new_message':
        if (payload?['chatId'] == _actualChatId) {
          final message = Message.fromJson(payload!);
          setState(() {
            final tempIndex = _messages.indexWhere((m) => 
              (m.id.startsWith('temp-') || m.id.startsWith('opt_')) && 
              m.content == message.content);
              
            if (tempIndex != -1) {
              _messages[tempIndex] = message;
            } else {
              _messages.insert(0, message);
              _checkKeywordEffects(message.content);
            }
          });
          _scrollToBottom();
          if (message.senderId != _currentUserId) {
            SoundService.playReceived();
            _sendReadReceipt([message.id]);
          }
        }
        break;
      case 'message_read':
        if (payload?['chatId'] == _actualChatId) {
          final ids = List<String>.from(payload!['messageIds'] ?? []);
          setState(() {
            for (var m in _messages) if (ids.contains(m.id)) m.isRead = true;
          });
        }
        break;
      case 'typing_start':
        if (payload?['chatId'] == _actualChatId && payload?['userId'] != _currentUserId) {
          setState(() => _isTyping = true);
          _typingTimer?.cancel();
          _typingTimer = Timer(const Duration(seconds: 5), () => setState(() => _isTyping = false));
        }
        break;
      case 'typing_end':
        if (payload?['chatId'] == _actualChatId) setState(() => _isTyping = false);
        break;
      case 'user_status_update':
        if (payload?['userId'] == _partnerId) {
          setState(() {
            _partnerStatus = payload!['status'];
            _isPartnerOnline = payload['isOnline'] == true;
          });
        }
        break;
      case 'message_reaction':
        final msgId = payload?['messageId'];
        final reactions = payload?['reactions'];
        if (msgId != null && reactions != null) {
          setState(() {
            final idx = _messages.indexWhere((m) => m.id == msgId);
            if (idx != -1) {
              final m = _messages[idx];
              _messages[idx] = Message(
                id: m.id, senderId: m.senderId, content: m.content, type: m.type,
                createdAt: m.createdAt, isRead: m.isRead,
                reactions: Map<String, String>.from(reactions),
              );
            }
          });
        }
        break;
    }
  }

  Future<void> _handleBlockUser() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Block Contact?'),
        content: Text('Are you sure you want to block ${_partnerName ?? "this user"}? You will no longer receive messages from them.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('Block', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
          ),
        ],
      ),
    );

    if (confirmed == true) {
      HapticFeedback.heavyImpact();
      try {
        final target = _partnerId ?? widget.userId;
        if (target == null) return;
        final res = await ApiService.blockUser(target);
        _showToast('User blocked');
        if (mounted) Navigator.pop(context);
      } catch (e) {
        _showToast('Error blocking user');
      }
    }
  }

  void _handleTyping() {
    if (_actualChatId == null) return;
    if (_messageController.text.isNotEmpty) {
      WebSocketService.send({'type': 'typing_start', 'payload': {'chatId': _actualChatId}});
    } else {
      WebSocketService.send({'type': 'typing_end', 'payload': {'chatId': _actualChatId}});
    }
  }

  void _sendReadReceipt(List<String> ids) {
    WebSocketService.send({'type': 'message_read', 'payload': {'chatId': _actualChatId, 'messageIds': ids}});
  }

  Future<void> _sendMessage({String? customText}) async {
    final text = customText ?? _messageController.text.trim();
    if (text.isEmpty || _actualChatId == null || _currentUserId == null) return;

    if (customText == null) _messageController.clear();
    _checkKeywordEffects(text);

    final isEmojiOnly = _isOnlyEmoji(text);
    final optimisticMsg = Message(
      id: 'opt_text_${DateTime.now().millisecondsSinceEpoch}',
      senderId: _currentUserId!,
      content: text,
      type: isEmojiOnly ? 'emoji' : 'text',
      createdAt: DateTime.now(),
    );

    setState(() {
      _messages.insert(0, optimisticMsg);
      _isIcebreakerVisible = false;
    });
    _scrollToBottom();
    SoundService.playSent();

    try {
      await ApiService.sendMessage(_actualChatId!, text);
    } catch (e) {
      if (mounted) {
        setState(() => _messages.removeWhere((m) => m.id == optimisticMsg.id));
      }
      _showToast('Failed to send');
    }
  }

  bool _isOnlyEmoji(String text) {
    if (text.isEmpty) return false;
    // Simple check: if length is small and contains emojis
    if (text.length > 10) return false; 
    return RegExp(r'^(\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff]|\s)+$').hasMatch(text);
  }

  // Pick images into staging tray — does NOT send immediately
  Future<void> _pickAndSendImages() async {
    try {
      final List<XFile> picked = await _picker.pickMultiImage(imageQuality: 85);
      if (picked.isEmpty) return;

      final remaining = 10 - (_stagedImages?.length ?? 0);
      if (remaining <= 0) {
        _showToast('Max 10 images already staged');
        return;
      }
      final limited = picked.length > remaining ? picked.sublist(0, remaining) : picked;
      if (picked.length > remaining) {
        _showToast('Only $remaining more image${remaining > 1 ? 's' : ''} allowed (max 10)');
      }

      for (final img in limited) {
        final bytes = await img.readAsBytes();
        setState(() {
          _stagedImages ??= [];
          _stagedBytes ??= [];
          _stagedImages!.add(img);
          _stagedBytes!.add(bytes);
          _isIcebreakerVisible = false;
        });
      }
    } catch (e) {
      _showToast('Could not open image picker');
    }
  }

  Future<void> _takePhoto() async {
    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      if (photo == null) return;

      final remaining = 10 - (_stagedImages?.length ?? 0);
      if (remaining <= 0) {
        _showToast('Max 10 images already staged');
        return;
      }

      final bytes = await photo.readAsBytes();
      setState(() {
        _stagedImages ??= [];
        _stagedBytes ??= [];
        _stagedImages!.add(photo);
        _stagedBytes!.add(bytes);
        _isIcebreakerVisible = false;
      });
    } catch (e) {
      _showToast('Could not open camera');
    }
  }

  // Actually upload & send all staged images (Batched for WhatsApp-style grid)
  Future<void> _sendStagedImages({String? caption}) async {
    if (_stagedImages == null || _stagedImages!.isEmpty) return;
    if (_actualChatId == null || _currentUserId == null) return;

    final images = List<XFile>.from(_stagedImages!);
    final bytes = List<Uint8List>.from(_stagedBytes!);
    
    // 1. Prepare optimistic IDs immediately
    final List<String> localTempIds = [];
    for (int i = 0; i < images.length; i++) {
      final tid = 'local_${DateTime.now().millisecondsSinceEpoch}_$i';
      localTempIds.add(tid);
      _pendingImageBytes[tid] = bytes[i];
    }

    final optimisticMsg = Message(
      id: 'opt_${DateTime.now().millisecondsSinceEpoch}',
      senderId: _currentUserId!,
      content: json.encode(localTempIds),
      type: 'image',
      createdAt: DateTime.now(),
    );

    // 2. TRIGGER UI UPDATE IMMEDIATELY
    setState(() {
      _messages.insert(0, optimisticMsg); 
      _stagedImages?.clear();
      _stagedBytes?.clear();
      _isUploading = true;
      _uploadingCount = images.length;
      _uploadedCount = 0;
    });
    _scrollToBottom();
    SoundService.playSent();

    // 3. Handle caption instantly too
    if (caption != null && caption.isNotEmpty) {
      _sendMessage(customText: caption);
    }

    final List<String> uploadedUrls = [];

    for (int i = 0; i < images.length; i++) {
      try {
        final url = await ApiService.uploadImage(bytes[i], images[i].name);
        if (url != null) {
          uploadedUrls.add(url);
        }
      } catch (e) {
        _showToast('Failed to upload ${images[i].name}');
      } finally {
        if (mounted) {
          setState(() {
            _uploadedCount = (_uploadedCount ?? 0) + 1;
          });
        }
      }
    }

    if (uploadedUrls.isNotEmpty) {
      try {
        await ApiService.sendMessage(_actualChatId!, json.encode(uploadedUrls), type: 'image');
        // Remove optimistic message once real one is sent (WS will bring the real one)
        setState(() {
          _messages.removeWhere((m) => m.id == optimisticMsg.id);
        });
      } catch (e) {
        _showToast('Failed to send images');
      }
    }

    if (mounted) {
      setState(() {
        _isUploading = false;
        _uploadingCount = 0;
        _uploadedCount = 0;
      });
    }
  }

  void _checkKeywordEffects(String text) {
    final t = text.toLowerCase();
    if (t.contains('congratulations') || t.contains('yay') || t.contains('hbd')) {
      _triggerEffect('confetti');
    } else if (t.contains('love') || t.contains('❤️')) {
      _triggerEffect('hearts');
    }
  }

  void _triggerEffect(String effect) {
    setState(() => _activeEffect = effect);
    _effectController?.forward(from: 0).then((_) {
      if (mounted) setState(() => _activeEffect = null);
    });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      // In a reversed list, 0.0 is the bottom (latest messages)
      // Use jumpTo for absolute instant response
      _scrollController.jumpTo(0.0);
    }
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  void _showGroupInfoModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final isCurrentUserAdmin = _groupAdminIds.contains(_currentUserId);
        return StatefulBuilder(
          builder: (context, setModalState) {
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
                  
                  // Group Header Details
                  CircleAvatar(
                    radius: 45,
                    backgroundImage: _partnerAvatar != null ? CachedNetworkImageProvider(_partnerAvatar!) : null,
                    backgroundColor: Colors.grey[200],
                    child: _partnerAvatar == null
                        ? Text(
                            _partnerName != null && _partnerName!.isNotEmpty ? _partnerName![0].toUpperCase() : 'G',
                            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF00AEEF)),
                          )
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _partnerName ?? 'Group Chat',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      _groupDescription != null && _groupDescription!.isNotEmpty
                          ? _groupDescription!
                          : 'No description provided.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Admin Actions Option or restrictions note
                  if (isCurrentUserAdmin)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _showEditGroupModal();
                            },
                            icon: const Icon(Icons.edit, size: 14),
                            label: const Text('Edit Details', style: TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00AEEF),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () {
                              _shareInviteLink();
                            },
                            icon: const Icon(Icons.link, size: 14),
                            label: const Text('Invite Link', style: TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF00AEEF),
                              side: const BorderSide(color: Color(0xFF00AEEF)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () {
                              _showAddGroupMembersModal(setModalState);
                            },
                            icon: const Icon(Icons.person_add_alt_1_rounded, size: 14),
                            label: const Text('Add Member', style: TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF00AEEF),
                              side: const BorderSide(color: Color(0xFF00AEEF)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.lock_outline, size: 16, color: Colors.grey),
                        const SizedBox(width: 6),
                        Text(
                          'Only admins can edit group details.',
                          style: TextStyle(color: Colors.grey[500], fontSize: 12),
                        ),
                      ],
                    ),
                  const Divider(height: 32),

                  // Members List Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Members (${_groupParticipants.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const Icon(Icons.people_outline, color: Colors.grey),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Members List
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _groupParticipants.length,
                      itemBuilder: (context, index) {
                        final member = _groupParticipants[index];
                        final memberId = member['id']?.toString() ?? member['_id']?.toString() ?? '';
                        final memberName = member['name']?.toString() ?? 'User';
                        final memberAvatar = member['avatar']?.toString();
                        final isMemberAdmin = _groupAdminIds.contains(memberId);
                        final isSelf = memberId == _currentUserId;

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundImage: memberAvatar != null ? CachedNetworkImageProvider(memberAvatar) : null,
                            backgroundColor: Colors.grey[100],
                            child: memberAvatar == null ? Text(memberName[0].toUpperCase()) : null,
                          ),
                          title: Row(
                            children: [
                              Text(
                                memberName,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: isSelf ? const Color(0xFF00AEEF) : Colors.black87,
                                ),
                              ),
                              if (isSelf) ...[
                                const SizedBox(width: 6),
                                Text('(You)', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            isMemberAdmin ? 'Admin' : 'Member',
                            style: TextStyle(
                              color: isMemberAdmin ? const Color(0xFF00AEEF) : Colors.grey[500],
                              fontSize: 12,
                            ),
                          ),
                          trailing: isMemberAdmin
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00AEEF).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFF00AEEF).withOpacity(0.3)),
                                  ),
                                  child: const Text(
                                    'Admin',
                                    style: TextStyle(color: Color(0xFF00AEEF), fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                )
                              : (isCurrentUserAdmin && !isSelf)
                                  ? PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_horiz, color: Colors.grey),
                                      onSelected: (val) async {
                                        if (val == 'promote') {
                                          try {
                                            await ApiService.promoteToAdmin(_actualChatId!, memberId);
                                            _showToast('$memberName is now an Admin');
                                            setState(() {
                                              _groupAdminIds.add(memberId);
                                            });
                                            setModalState(() {});
                                          } catch (e) {
                                            _showToast('Failed to promote member');
                                          }
                                        } else if (val == 'remove') {
                                          try {
                                            await ApiService.removeGroupMember(_actualChatId!, memberId);
                                            _showToast('$memberName removed');
                                            setState(() {
                                              _groupParticipants.removeWhere((m) => (m['id']?.toString() ?? m['_id']?.toString()) == memberId);
                                              _groupAdminIds.remove(memberId);
                                            });
                                            setModalState(() {});
                                          } catch (e) {
                                            _showToast('Failed to remove member');
                                          }
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: 'promote',
                                          child: Row(
                                            children: [
                                              Icon(Icons.shield_outlined, size: 20),
                                              SizedBox(width: 8),
                                              Text('Make Admin'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'remove',
                                          child: Row(
                                            children: [
                                              Icon(Icons.person_remove_outlined, color: Colors.red, size: 20),
                                              SizedBox(width: 8),
                                              Text('Remove Member', style: TextStyle(color: Colors.red)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    )
                                  : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showEditGroupModal() {
    final nameController = TextEditingController(text: _partnerName);
    final descController = TextEditingController(text: _groupDescription);
    Uint8List? localAvatarBytes;
    final imagePicker = ImagePicker();
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
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
                      'Edit Group Info',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),

                    // Group Avatar Picker
                    GestureDetector(
                      onTap: () async {
                        final img = await imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 70);
                        if (img != null) {
                          final bytes = await img.readAsBytes();
                          setModalState(() {
                            localAvatarBytes = bytes;
                          });
                        }
                      },
                      child: CircleAvatar(
                        radius: 40,
                        backgroundColor: Colors.grey[200],
                        backgroundImage: localAvatarBytes != null
                            ? MemoryImage(localAvatarBytes!)
                            : (_partnerAvatar != null ? CachedNetworkImageProvider(_partnerAvatar!) : null) as ImageProvider?,
                        child: localAvatarBytes == null && _partnerAvatar == null
                            ? const Icon(Icons.add_a_photo, color: Colors.grey, size: 28)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Name Field
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Group Name',
                        prefixIcon: const Icon(Icons.group),
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Description Field
                    TextField(
                      controller: descController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Description',
                        prefixIcon: const Icon(Icons.description),
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: isSaving
                            ? null
                            : () async {
                                final n = nameController.text.trim();
                                final d = descController.text.trim();
                                if (n.isEmpty) {
                                  _showToast('Group name cannot be empty');
                                  return;
                                }

                                setModalState(() => isSaving = true);

                                try {
                                  String? uploadedUrl;
                                  if (localAvatarBytes != null) {
                                    uploadedUrl = await ApiService.uploadImage(localAvatarBytes!, 'group_avatar.jpg');
                                  }

                                  await ApiService.updateGroupChat(
                                    _actualChatId!,
                                    groupName: n,
                                    groupDescription: d,
                                    groupAvatar: uploadedUrl,
                                  );

                                  _showToast('Group updated!');
                                  setState(() {
                                    _partnerName = n;
                                    _groupDescription = d;
                                    if (uploadedUrl != null) {
                                      _partnerAvatar = uploadedUrl;
                                    }
                                  });
                                  Navigator.pop(context);
                                } catch (e) {
                                  _showToast('Failed to update group');
                                  setModalState(() => isSaving = false);
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00AEEF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                          elevation: 0,
                        ),
                        child: isSaving
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _shareInviteLink() async {
    try {
      final res = await ApiService.generateGroupInviteCode(_actualChatId!);
      final inviteCode = res['inviteCode'] as String?;
      if (inviteCode == null) throw Exception('No invite code generated');
      final inviteUrl = 'https://zukaping.app/join-group?code=$inviteCode';

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(
              children: [
                const Icon(Icons.link_rounded, color: Color(0xFF00AEEF), size: 28),
                const SizedBox(width: 8),
                const Text('Group Invite Link', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Anyone with this link can join this group chat, even if they are not currently a user.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: SelectableText(
                    inviteUrl,
                    style: const TextStyle(fontSize: 13, fontFamily: 'monospace', color: Colors.black87),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: inviteUrl));
                  Navigator.pop(context);
                  _showToast('Invite link copied to clipboard!');
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy Link'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00AEEF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ],
          );
        },
      );
    } catch (e) {
      _showToast('Failed to generate invite code');
    }
  }

  void _showAddGroupMembersModal(StateSetter setParentState) {
    final searchController = TextEditingController();
    List<dynamic> searchResults = [];
    bool isSearching = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
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
                      'Add Members to Group',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),

                    // Search input
                    TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        hintText: 'Search users by name...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  searchController.clear();
                                  setModalState(() {
                                    searchResults = [];
                                  });
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      ),
                      onChanged: (val) async {
                        final query = val.trim();
                        if (query.isEmpty) {
                          setModalState(() {
                            searchResults = [];
                          });
                          return;
                        }

                        setModalState(() => isSearching = true);
                        try {
                          final results = await ApiService.searchUsers(query);
                          setModalState(() {
                            searchResults = results;
                            isSearching = false;
                          });
                        } catch (e) {
                          setModalState(() => isSearching = false);
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // Search results list
                    Expanded(
                      child: isSearching
                          ? const Center(child: CircularProgressIndicator())
                          : searchResults.isEmpty
                              ? Center(
                                  child: Text(
                                    searchController.text.isEmpty
                                        ? 'Type to search registered users'
                                        : 'No users found',
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: searchResults.length,
                                  itemBuilder: (context, index) {
                                    final u = searchResults[index];
                                    final uId = u['id']?.toString() ?? u['_id']?.toString() ?? '';
                                    final uName = u['name']?.toString() ?? 'User';
                                    final uAvatar = u['avatar']?.toString();

                                    final isAlreadyMember = _groupParticipants.any(
                                      (m) => (m['id']?.toString() ?? m['_id']?.toString()) == uId
                                    );

                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: CircleAvatar(
                                        backgroundImage: uAvatar != null ? CachedNetworkImageProvider(uAvatar) : null,
                                        backgroundColor: Colors.grey[100],
                                        child: uAvatar == null ? Text(uName[0].toUpperCase()) : null,
                                      ),
                                      title: Text(uName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                      trailing: isAlreadyMember
                                          ? const Text(
                                              'Member',
                                              style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold),
                                            )
                                          : ElevatedButton(
                                              onPressed: () async {
                                                try {
                                                  await ApiService.addGroupMember(_actualChatId!, uId);
                                                  _showToast('$uName added to group!');
                                                  
                                                  // Update state
                                                  final newMember = {
                                                    'id': uId,
                                                    'name': uName,
                                                    'avatar': uAvatar,
                                                    'status': 'offline',
                                                  };
                                                  setState(() {
                                                    _groupParticipants.add(newMember);
                                                  });
                                                  setParentState(() {});
                                                  setModalState(() {});
                                                } catch (e) {
                                                  _showToast('Failed to add $uName');
                                                }
                                              },
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFF00AEEF),
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                elevation: 0,
                                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                              ),
                                              child: const Text('Add'),
                                            ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          const _LiquidBackground(),
          Column(
            children: [
              _buildAppBar(),
              Expanded(
                child: _isLoading 
                    ? _buildShimmerLoading() 
                    : _messages.isEmpty 
                        ? _buildEmptyState()
                        : ListView.builder(
                            controller: _scrollController,
                            reverse: true, // Standard for chat apps
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                            itemCount: _messages.length + (_isTyping ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _messages.length) return _buildTypingBubble();
                              return _buildMessageBubble(_messages[index]);
                            },
                          ),
              ),
              if (!_isLoading && _isIcebreakerVisible && _messages.isEmpty) _buildIcebreakerHub(),
              _buildInputArea(),
            ],
          ),
          if (_activeEffect != null && _effectController != null) _buildEffectOverlay(),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.only(
            top: math.max(12.0, MediaQuery.of(context).padding.top), 
            bottom: 12,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.7),
            border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.08))),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, size: 20), 
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(context);
                }
              ),
              _isLoading 
                ? Shimmer.fromColors(
                    baseColor: Colors.grey[300]!,
                    highlightColor: Colors.grey[100]!,
                    child: Container(width: 40, height: 40, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                  )
                : Expanded(
                    child: InkWell(
                      onTap: () {
                        if (_partnerStatus == 'group') {
                          _showGroupInfoModal();
                        }
                      },
                      child: Row(
                        children: [
                          _PulseAvatar(
                            imageUrl: _partnerAvatar, userPhotos: _partnerPhotos, userName: _partnerName ?? '?', 
                            isOnline: _isPartnerOnline, status: _partnerStatus ?? 'offline',
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_partnerName ?? '...', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                                Text(
                                  _isTyping 
                                      ? 'typing...' 
                                      : (_partnerStatus == 'group' 
                                          ? '${_groupParticipants.length} members' 
                                          : (_isPartnerOnline ? 'online' : (_partnerStatus ?? 'offline'))),
                                  style: TextStyle(
                                    fontSize: 12, 
                                    color: _isTyping ? const Color(0xFF00AEEF) : Colors.grey[600],
                                    fontWeight: _isTyping ? FontWeight.bold : FontWeight.normal,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Color(0xFF00AEEF)),
                onSelected: (val) {
                  if (val == 'block') {
                    _handleBlockUser();
                  }
                  if (val == 'media') {
                    _openMediaGallery();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'media',
                    child: Text('Shared Media'),
                  ),
                  const PopupMenuItem(
                    value: 'block',
                    child: Row(
                      children: [
                        Icon(Icons.block, color: Colors.red, size: 20),
                        SizedBox(width: 12),
                        Text('Block Contact', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcebreakerHub() {
    final options = [
      {'e': '👋', 't': 'Hey! How are you?'},
      {'e': '✨', 't': 'Love your profile!'},
      {'e': '🍕', 't': 'Best food in town?'},
    ];
    return Container(
      height: 90,
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: options.map((o) => GestureDetector(
          onTap: () { _messageController.text = o['t']!; _sendMessage(); },
          child: Container(
            width: 150, margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey[200]!)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(o['e']!, style: const TextStyle(fontSize: 18)),
              Text(o['t']!, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildMessageBubble(Message m) {
    final isMe = m.senderId == _currentUserId;
    final content = Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () {
          HapticFeedback.lightImpact();
          _showReactionPicker(m);
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 12, top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              decoration: BoxDecoration(
                gradient: isMe ? const LinearGradient(
                  colors: [Color(0xFF00D2FF), Color(0xFF00AEEF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ) : null,
                color: isMe ? null : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20), topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isMe ? 20 : 4), bottomRight: Radius.circular(isMe ? 4 : 20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: isMe ? const Color(0xFF00AEEF).withOpacity(0.2) : Colors.black.withOpacity(0.04),
                    blurRadius: 12, offset: const Offset(0, 6),
                  ),
                  if (isMe) BoxShadow(
                    color: Colors.white.withOpacity(0.2),
                    blurRadius: 0, offset: const Offset(0, -1), spreadRadius: -1,
                  ),
                ],
              ),
              child: _buildMessageContent(m, isMe),
            ),
            if (m.reactions != null && m.reactions!.isNotEmpty) _buildReactionBadge(m),
          ],
        ),
      ),
    );

    if (isMe) return content; // Instant for own messages

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 300),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(-30 * (1 - value), 0),
          child: child,
        ),
      ),
      child: content,
    );
  }


  Widget _buildMessageContent(Message m, bool isMe) {
    if (m.type == 'emoji') {
      final emojiCount = m.content.characters.length;
      double fontSize = 32;
      if (emojiCount == 1) fontSize = 48;
      else if (emojiCount <= 3) fontSize = 38;
      
      return Text(m.content, style: TextStyle(fontSize: fontSize));
    }

    if (m.type == 'image' || _isImageMessage(m)) {
      return Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          ..._buildImageContent(m),
          if (m.content.contains('"') && !m.content.startsWith('[')) // If it's a mix or has a caption
             Padding(
               padding: const EdgeInsets.only(top: 8),
               child: Text(m.content, style: TextStyle(color: isMe ? Colors.white : Colors.black87)),
             ),
        ],
      );
    }
    return Text(m.content, style: TextStyle(color: isMe ? Colors.white : Colors.black87));
  }

  List<Widget> _buildImageContent(Message m) {
    List<String> images = _parseImageUrls(m.content);
    if (images.isEmpty) return [const SizedBox.shrink()];

    const double totalWidth = 240.0;
    const double totalHeight = 240.0;
    final borderRadius = BorderRadius.circular(12);

    if (images.length == 1) {
      return [
        GestureDetector(
          onTap: () => _openImageCarousel(images, 0),
          child: ClipRRect(
            borderRadius: borderRadius,
            child: _buildImageWidget(images[0], width: totalWidth, height: totalHeight),
          ),
        ),
      ];
    } else if (images.length == 2) {
      return [
        ClipRRect(
          borderRadius: borderRadius,
          child: SizedBox(
            width: totalWidth, height: totalHeight / 1.4,
            child: Row(
              children: [
                Expanded(child: GestureDetector(onTap: () => _openImageCarousel(images, 0), child: _buildImageWidget(images[0]))),
                const SizedBox(width: 2),
                Expanded(child: GestureDetector(onTap: () => _openImageCarousel(images, 1), child: _buildImageWidget(images[1]))),
              ],
            ),
          ),
        ),
      ];
    } else if (images.length == 3) {
      return [
        ClipRRect(
          borderRadius: borderRadius,
          child: SizedBox(
            width: totalWidth, height: totalHeight,
            child: Row(
              children: [
                Expanded(child: GestureDetector(onTap: () => _openImageCarousel(images, 0), child: _buildImageWidget(images[0]))),
                const SizedBox(width: 2),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: GestureDetector(onTap: () => _openImageCarousel(images, 1), child: _buildImageWidget(images[1]))),
                      const SizedBox(height: 2),
                      Expanded(child: GestureDetector(onTap: () => _openImageCarousel(images, 2), child: _buildImageWidget(images[2]))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ];
    } else {
      // 4 or more images
      return [
        ClipRRect(
          borderRadius: borderRadius,
          child: SizedBox(
            width: totalWidth, height: totalHeight,
            child: GridView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, mainAxisSpacing: 2, crossAxisSpacing: 2,
              ),
              itemCount: 4,
              itemBuilder: (context, index) {
                final isLast = index == 3 && images.length > 4;
                return GestureDetector(
                  onTap: () => _openImageCarousel(images, index),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildImageWidget(images[index]),
                      if (isLast)
                        Container(
                          color: Colors.black45,
                          child: Center(
                            child: Text('+${images.length - 4}',
                                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ];
    }
  }

  void _openImageCarousel(List<String> images, int startIndex) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => _ImageCarouselOverlay(images: images, initialIndex: startIndex),
      ),
    );
  }

  void _openMediaGallery() {
    final List<String> allImages = [];
    // Collect images from latest to oldest
    for (var m in _messages) {
      if (m.type == 'image' || _isImageMessage(m)) {
        allImages.addAll(_parseImageUrls(m.content));
      }
    }

    if (allImages.isEmpty) {
      _showToast('No media shared yet');
      return;
    }

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            elevation: 0,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Media, Links, and Docs', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text('${allImages.length} items', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
            centerTitle: false,
          ),
          body: GridView.builder(
            padding: const EdgeInsets.all(2),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2,
            ),
            itemCount: allImages.length,
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () => _openImageCarousel(allImages, index),
                child: CachedNetworkImage(
                  imageUrl: allImages[index],
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(color: Colors.grey[100]),
                  errorWidget: (context, url, error) => const Icon(Icons.broken_image),
                ),
              );
            },
          ),
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(animation),
            child: child,
          );
        },
      ),
    );
  }

  Widget _buildImageWidget(String urlOrId, {double? width, double? height}) {
    // Check if this is a pending local image (stored by tempId)
    if (_pendingImageBytes.containsKey(urlOrId)) {
      return Image.memory(
        _pendingImageBytes[urlOrId]!,
        width: width, height: height, fit: BoxFit.cover,
        gaplessPlayback: true, // Prevents flicker during replacement
      );
    }
    // Network URL
    if (urlOrId.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: urlOrId, width: width, height: height, fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: Colors.grey[200],
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorWidget: (context, url, error) => Container(
          color: Colors.grey[200],
          child: const Icon(Icons.broken_image, color: Colors.grey),
        ),
      );
    }
    // Fallback placeholder for unknown
    return Container(
      width: width, height: height,
      color: Colors.grey[200],
      child: const Center(child: Icon(Icons.image, color: Colors.grey)),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF00AEEF).withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.forum_rounded, size: 48, color: Color(0xFF00AEEF)),
          ),
          const SizedBox(height: 20),
          Text(
            'No messages yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[800]),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              _partnerName != null ? 'Start a conversation with $_partnerName' : 'Say hello to start the chat!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[200]!,
      highlightColor: Colors.white,
      child: ListView.builder(
        itemCount: 8,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        itemBuilder: (_, i) {
          final isMe = i % 2 == 0;
          return Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              width: 100 + (math.Random().nextDouble() * 100),
              height: 40 + (math.Random().nextDouble() * 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  bool _isImageMessage(Message m) {
    if (m.type == 'image') return true;
    final content = m.content.trim();
    if (content.startsWith('[') && content.endsWith(']')) {
      try {
        final decoded = json.decode(content);
        return decoded is List && decoded.isNotEmpty && decoded.first.toString().startsWith('http');
      } catch (_) {}
    }
    return content.startsWith('http') && (content.contains('cloudinary') || content.endsWith('.jpg') || content.endsWith('.png'));
  }

  List<String> _parseImageUrls(String content) {
    try {
      final decoded = json.decode(content);
      if (decoded is List) return decoded.cast<String>();
      if (decoded is String) return [decoded];
    } catch (_) {}
    // Fallback if not JSON
    if (content.startsWith('http')) return [content];
    return [];
  }


  Widget _buildReactionBadge(Message m) {
    final emoji = m.reactions!.values.first;
    return Positioned(
      bottom: -4, right: m.senderId == _currentUserId ? 4 : null, left: m.senderId != _currentUserId ? 4 : null,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: Colors.grey[100]!)),
        child: Text(emoji, style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  void _showReactionPicker(Message m) {
    final emojis = ['❤️', '😂', '🔥', '👍', '🙏'];
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      builder: (c) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: emojis.map((e) => GestureDetector(
          onTap: () { ApiService.reactToMessage(m.id, e); Navigator.pop(c); },
          child: Text(e, style: const TextStyle(fontSize: 30)),
        )).toList()),
      ),
    );
  }

  Widget _buildTypingBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          _PulseAvatar(imageUrl: _partnerAvatar, userPhotos: _partnerPhotos, userName: _partnerName ?? '?', isOnline: true, status: 'available', radius: 15),
          const SizedBox(width: 8),
          const _TypingDots(),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    final stagedImgs = _stagedImages ?? [];
    final stagedBts = _stagedBytes ?? [];
    final uploading = _isUploading ?? false;
    final upCount = _uploadingCount ?? 0;
    final upDone = _uploadedCount ?? 0;
    final hasStagedImages = stagedImgs.isNotEmpty;
    final progress = upCount > 0 ? upDone / upCount : 0.0;
    
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.75),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, -5))],
            border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.05))),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Upload progress (Full width blue line) ──
                if (uploading)
                  SizedBox(
                    height: 2,
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.transparent,
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00AEEF)),
                    ),
                  ),
                if (uploading)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Uploading $upDone of $upCount...',
                          style: const TextStyle(fontSize: 10, color: Color(0xFF00AEEF), fontWeight: FontWeight.bold),
                        ),
                        Text('${(progress * 100).toInt()}%',
                            style: const TextStyle(fontSize: 10, color: Color(0xFF00AEEF), fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                // ── Image Staging Tray ──
                if (hasStagedImages)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutBack,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('${stagedImgs.length} image${stagedImgs.length > 1 ? 's' : ''} selected',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF00AEEF))),
                            const Spacer(),
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.mediumImpact();
                                setState(() { _stagedImages?.clear(); _stagedBytes?.clear(); });
                              },
                              child: const Text('Clear all', style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 85,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: stagedImgs.length,
                            itemBuilder: (context, idx) => _buildStagedItem(idx, stagedImgs[idx], stagedBts[idx]),
                          ),
                        ),
                      ],
                    ),
                  ),
                
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
                  child: Row(
                    children: [
                      _InputIconBtn(
                        icon: _showEmojiPicker ? Icons.keyboard_rounded : Icons.emoji_emotions_outlined,
                        active: _showEmojiPicker,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _showEmojiPicker = !_showEmojiPicker);
                        }
                      ),
                      _InputIconBtn(
                        icon: Icons.camera_alt_outlined,
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          _takePhoto();
                        }
                      ),
                      _InputIconBtn(
                        icon: Icons.add_photo_alternate_outlined,
                        active: hasStagedImages,
                        badge: hasStagedImages ? stagedImgs.length.toString() : null,
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          _pickAndSendImages();
                        }
                      ),
                      const SizedBox(width: 4),
                      // ── Message TextField (Optimized 'Fatness') ──
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 46, maxHeight: 150),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F2F5).withOpacity(0.8),
                              borderRadius: BorderRadius.circular(23),
                            ),
                            child: TextField(
                              controller: _messageController,
                              focusNode: _focusNode,
                              maxLines: null,
                              onTap: () => setState(() => _showEmojiPicker = false),
                              textCapitalization: TextCapitalization.sentences,
                              cursorColor: const Color(0xFF00AEEF),
                              style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A2E), height: 1.3),
                              decoration: const InputDecoration(
                                hintText: 'Type a message...',
                                hintStyle: TextStyle(color: Color(0xFF9E9E9E), fontSize: 15),
                                border: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: (uploading) ? null : () {
                          HapticFeedback.heavyImpact();
                          final text = _messageController.text.trim();
                          if (hasStagedImages) {
                            _sendStagedImages(caption: text);
                            _messageController.clear();
                          } else if (text.isNotEmpty) {
                            _sendMessage();
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 42, height: 42,
                          decoration: BoxDecoration(
                            gradient: (hasStagedImages || _messageController.text.isNotEmpty) && !uploading
                                ? const LinearGradient(
                                    colors: [Color(0xFF00D2FF), Color(0xFF0078D4)],
                                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                                  )
                                : null,
                            color: (!hasStagedImages && _messageController.text.isEmpty) || uploading
                                ? Colors.grey[200] : null,
                            shape: BoxShape.circle,
                            boxShadow: (hasStagedImages || _messageController.text.isNotEmpty) && !uploading ? [
                              BoxShadow(
                                color: const Color(0xFF00AEEF).withOpacity(0.35),
                                blurRadius: 10, offset: const Offset(0, 4),
                              )
                            ] : [],
                          ),
                          child: Icon(
                            Icons.send_rounded,
                            color: (hasStagedImages || _messageController.text.isNotEmpty) && !uploading
                                ? Colors.white : Colors.grey[400],
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_showEmojiPicker) _buildEmojiPicker(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEffectOverlay() {
    return AnimatedBuilder(
      animation: _effectController!,
      builder: (context, child) {
        return CustomPaint(
          size: Size.infinite,
          painter: _EffectPainter(_activeEffect!, _effectController!.value),
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'available':
      case 'online':
        return const Color(0xFF00AEEF);
      case 'busy':
        return const Color(0xFFFFFF00);
      case 'super':
        return Colors.deepPurpleAccent;
      case 'ghost':
        return Colors.grey.withOpacity(0.5);
      default:
        return Colors.grey;
    }
  }
  Widget _buildStagedItem(int i, XFile img, Uint8List bytes) {
    return Stack(
      children: [
        Container(
          width: 80, height: 80,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))],
          ),
          clipBehavior: Clip.hardEdge,
          child: Image.memory(bytes, fit: BoxFit.cover),
        ),
        Positioned(
          top: 2, right: 14,
          child: GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() {
                _stagedImages?.removeAt(i);
                _stagedBytes?.removeAt(i);
              });
            },
            child: Container(
              width: 22, height: 22,
              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
              child: const Icon(Icons.close, color: Colors.white, size: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmojiPicker() {
    final List<Map<String, dynamic>> categories = [
      {
        'icon': Icons.sentiment_satisfied_alt,
        'items': ['😀', '😃', '😄', '😁', '😅', '😂', '🤣', '😊', '😇', '🙂', '🙃', '😉', '😌', '😍', '🥰', '😘', '😗', '😙', '😚', '😋', '😛', '😝', '😜', '🤪', '🤨', '🧐', '🤓', '😎', '🤩', '🥳', '😏', '😒', '😞', '😔', '😟', '😕', '🙁', '☹️', '😣', '😖', '😫', '😩', '🥺', '😢', '😭', '😤', '😠', '😡', '🤬', '🤯', '😳', '🥵', '🥶', '😱', '😨', '😰', '😥', '😓', '🤗', '🤔', '🤭', '🤫', '🤥', '😶', '😐', '😑', '😬', '🙄', '😯', '😦', '😧', '😮', '😲', '🥱', '😴', '🤤', '😪', '😵', '🤐', '🥴', '🤢', '🤮', '🤧', '😷', '🤒', '🤕']
      },
      {
        'icon': Icons.favorite_border,
        'items': ['❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔', '❣️', '💕', '💞', '💓', '💗', '💖', '💘', '💝', '💟']
      },
      {
        'icon': Icons.front_hand_outlined,
        'items': ['👋', '🤚', '🖐️', '✋', '🖖', '👌', '🤏', '✌️', '🤞', '🤟', '🤘', '🤙', '👈', '👉', '👆', '🖕', '👇', '☝️', '👍', '👎', '✊', '👊', '🤛', '🤜', '👏', '🙌', '👐', '🤲', '🤝', '🙏', '✍️', '💅', '🤳', '💪', '🦾']
      },
      {
        'icon': Icons.pets_outlined,
        'items': ['🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯', '🦁', '🐮', '🐷', '🐸', '🐵', '🐔', '🐧', '🐦', '🐤', '🦆', '🦅', '🦉', '🦇', '🐺', '🐗', '🐴', '🦄', '🐝', '🐛', '🦋', '🐌', '🐞', '🐜', '🦟', '🐢', '🐍', '🦎', '🦖', '🦕', '🐙', '🦑', '🦐', '🦞', '🦀', '🐡', '🐠', '🐟', '🐬', '🐳', '🐋', '🦈']
      },
      {
        'icon': Icons.fastfood_outlined,
        'items': ['🍏', '🍎', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🍈', '🍒', '🍑', '🥭', '🍍', '🥥', '🥝', '🍅', '🍆', '🥑', '🥦', '🥬', '🥒', '🌽', '🥕', '🥔', '🍠', '🥐', '🍞', '🥖', '🥨', '🥯', '🥞', '🥠', '🥡', '🍔', '🍟', '🍕', '🌭', '🥪', '🌮', '🌯', '🍣', '🍤', '🍜', '🍛', '☕', '🍵', '🥤', '🍺', '🍷', '🍹']
      },
    ];

    return Container(
      height: 320,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: DefaultTabController(
        length: categories.length,
        child: Column(
          children: [
            Expanded(
              child: TabBarView(
                children: categories.map((cat) => GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7, mainAxisSpacing: 12, crossAxisSpacing: 12,
                  ),
                  itemCount: cat['items'].length,
                  itemBuilder: (context, i) {
                    final emoji = cat['items'][i];
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _messageController.text += emoji;
                      },
                      child: Center(child: Text(emoji, style: const TextStyle(fontSize: 26))),
                    );
                  },
                )).toList(),
              ),
            ),
            Container(
              height: 50,
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border(top: BorderSide(color: Colors.grey[200]!)),
              ),
              child: TabBar(
                indicatorColor: const Color(0xFF00AEEF),
                indicatorSize: TabBarIndicatorSize.label,
                labelColor: const Color(0xFF00AEEF),
                unselectedLabelColor: Colors.grey[400],
                tabs: categories.map((cat) => Tab(icon: Icon(cat['icon'], size: 22))).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InputIconBtn extends StatelessWidget {
  final IconData? icon;
  final String? emoji;
  final VoidCallback onTap;
  final bool active;
  final String? badge;
  const _InputIconBtn({super.key, this.icon, this.emoji, required this.onTap, this.active = false, this.badge});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: active ? const Color(0xFF00AEEF).withOpacity(0.12) : Colors.grey[100],
              shape: BoxShape.circle,
            ),
            child: Center(
              child: emoji != null
                  ? Text(emoji!, style: const TextStyle(fontSize: 20))
                  : Icon(icon, color: const Color(0xFF00AEEF), size: 20),
            ),
          ),
          if (badge != null)
            Positioned(
              top: -2, right: -2,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Center(
                  child: Text(
                    badge!,
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LiquidBackground extends StatelessWidget {
  const _LiquidBackground();
  @override
  Widget build(BuildContext context) {
    return Container(color: const Color(0xFFF8F9FA));
  }
}

class _TypingDots extends StatelessWidget {
  const _TypingDots();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: const Text('...', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00AEEF))),
    );
  }
}

class _PulseAvatar extends StatefulWidget {
  final String? imageUrl;
  final List<String> userPhotos;
  final String userName;
  final bool isOnline;
  final String status;
  final double radius;
  const _PulseAvatar({this.imageUrl, this.userPhotos = const [], required this.userName, required this.isOnline, required this.status, this.radius = 20});
  
  @override
  State<_PulseAvatar> createState() => _PulseAvatarState();
}

class _PulseAvatarState extends State<_PulseAvatar> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveImageUrl = (widget.imageUrl != null && widget.imageUrl!.isNotEmpty)
        ? widget.imageUrl
        : (widget.userPhotos.isNotEmpty ? widget.userPhotos.first : null);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: widget.isOnline ? [
              BoxShadow(
                color: const Color(0xFF00AEEF).withOpacity(1.0 - _controller.value),
                blurRadius: _controller.value * 10,
                spreadRadius: _controller.value * 5,
              )
            ] : [],
          ),
          child: CircleAvatar(
            radius: widget.radius,
            backgroundColor: Colors.grey[200],
            backgroundImage: effectiveImageUrl != null ? CachedNetworkImageProvider(effectiveImageUrl) : null,
            child: effectiveImageUrl == null ? Text(widget.userName.isNotEmpty ? widget.userName[0] : '?') : null,
          ),
        );
      },
    );
  }
}

class _EffectPainter extends CustomPainter {
  final String type;
  final double progress;
  _EffectPainter(this.type, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    if (type == 'confetti') {
      final paint = Paint()..style = PaintingStyle.fill;
      final rand = math.Random(42);
      for (int i = 0; i < 50; i++) {
        paint.color = Colors.primaries[rand.nextInt(Colors.primaries.length)];
        final x = rand.nextDouble() * size.width;
        final y = progress * size.height * 1.5 - rand.nextDouble() * 200;
        canvas.drawRect(Rect.fromLTWH(x, y, 8, 8), paint);
      }
    } else if (type == 'hearts') {
      final textPainter = TextPainter(textDirection: TextDirection.ltr);
      final rand = math.Random(42);
      for (int i = 0; i < 20; i++) {
        textPainter.text = const TextSpan(text: '❤️', style: TextStyle(fontSize: 24));
        textPainter.layout();
        final x = rand.nextDouble() * size.width;
        final y = (1.0 - progress) * size.height - rand.nextDouble() * 200;
        textPainter.paint(canvas, Offset(x, y));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _ImageCarouselOverlay extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  const _ImageCarouselOverlay({required this.images, required this.initialIndex});

  @override
  State<_ImageCarouselOverlay> createState() => _ImageCarouselOverlayState();
}

class _ImageCarouselOverlayState extends State<_ImageCarouselOverlay> {
  late PageController _pageController;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Swipeable image pages
          PageView.builder(
            controller: _pageController,
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (context, i) {
              return InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: widget.images[i],
                    fit: BoxFit.contain,
                    placeholder: (context, url) => const Center(child: CircularProgressIndicator(color: Colors.white)),
                    errorWidget: (context, url, error) => const Icon(Icons.broken_image, color: Colors.white, size: 60),
                  ),
                ),
              );
            },
          ),
          // Top bar
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top, left: 8, right: 8, bottom: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text(
                    '${_current + 1} / ${widget.images.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ),
          // Dot indicators
          if (widget.images.length > 1)
            Positioned(
              bottom: 24, left: 0, right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.images.length, (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _current ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _current ? Colors.white : Colors.white.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(3),
                  ),
                )),
              ),
            ),
        ],
      ),
    );
  }
}