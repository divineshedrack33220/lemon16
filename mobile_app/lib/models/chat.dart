class Chat {
  final String id;
  final String partnerId;
  final String partnerName;
  final String? partnerAvatar;
  final List<String> partnerPhotos;
  final String lastMessage;
  final String lastMessageType;
  final DateTime lastMessageTime;
  final int unreadCount;
  final bool isOnline;
  final String partnerStatus;
  final bool isGroup;
  final String? groupName;
  final String? groupAvatar;
  final String? groupDescription;
  final List<String> adminIds;
  final List<dynamic> participantsProfiles;

  Chat({
    required this.id,
    required this.partnerId,
    required this.partnerName,
    this.partnerAvatar,
    this.partnerPhotos = const [],
    required this.lastMessage,
    this.lastMessageType = 'text',
    required this.lastMessageTime,
    this.unreadCount = 0,
    this.isOnline = false,
    this.partnerStatus = 'offline',
    this.isGroup = false,
    this.groupName,
    this.groupAvatar,
    this.groupDescription,
    this.adminIds = const [],
    this.participantsProfiles = const [],
  });

  Chat copyWith({
    String? id,
    String? partnerId,
    String? partnerName,
    String? partnerAvatar,
    List<String>? partnerPhotos,
    String? lastMessage,
    String? lastMessageType,
    DateTime? lastMessageTime,
    int? unreadCount,
    bool? isOnline,
    String? partnerStatus,
    bool? isGroup,
    String? groupName,
    String? groupAvatar,
    String? groupDescription,
    List<String>? adminIds,
    List<dynamic>? participantsProfiles,
  }) {
    return Chat(
      id: id ?? this.id,
      partnerId: partnerId ?? this.partnerId,
      partnerName: partnerName ?? this.partnerName,
      partnerAvatar: partnerAvatar ?? this.partnerAvatar,
      partnerPhotos: partnerPhotos ?? this.partnerPhotos,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageType: lastMessageType ?? this.lastMessageType,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      isOnline: isOnline ?? this.isOnline,
      partnerStatus: partnerStatus ?? this.partnerStatus,
      isGroup: isGroup ?? this.isGroup,
      groupName: groupName ?? this.groupName,
      groupAvatar: groupAvatar ?? this.groupAvatar,
      groupDescription: groupDescription ?? this.groupDescription,
      adminIds: adminIds ?? this.adminIds,
      participantsProfiles: participantsProfiles ?? this.participantsProfiles,
    );
  }

  factory Chat.fromJson(Map<String, dynamic> json) {
    final partner = json['partner'] as Map<String, dynamic>? ?? {};
    final lastMsg = json['lastMessage'];

    // Parse lastMessage content
    String msgContent = '';
    if (lastMsg is Map) {
      msgContent = lastMsg['content']?.toString() ?? '';
    } else if (lastMsg is String) {
      msgContent = lastMsg;
    }

    // Parse lastMessageAt - int Unix timestamp
    DateTime parseTime(dynamic val) {
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val * 1000);
      if (val is String) {
        final i = int.tryParse(val);
        if (i != null) return DateTime.fromMillisecondsSinceEpoch(i * 1000);
        return DateTime.tryParse(val) ?? DateTime.now();
      }
      return DateTime.now();
    }

    final statusRaw = partner['status'];
    final String status = statusRaw != null ? statusRaw.toString() : 'offline';
    
    final bool isGroup = json['isGroup'] == true;

    return Chat(
      id: json['id']?.toString() ?? '',
      partnerId: partner['id']?.toString() ?? '',
      partnerName: isGroup ? (json['groupName']?.toString() ?? 'Group Chat') : (partner['name']?.toString() ?? 'User'),
      partnerAvatar: isGroup ? json['groupAvatar']?.toString() : partner['avatar']?.toString(),
      partnerPhotos: (partner['photos'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      lastMessage: msgContent,
      lastMessageType: _detectMessageType(lastMsg),
      lastMessageTime: parseTime(json['lastMessageAt']),
      unreadCount: 0,
      partnerStatus: status,
      isOnline: partner['isOnline'] == true,
      isGroup: isGroup,
      groupName: json['groupName']?.toString(),
      groupAvatar: json['groupAvatar']?.toString(),
      groupDescription: json['groupDescription']?.toString(),
      adminIds: (json['adminIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      participantsProfiles: json['participantsProfiles'] as List<dynamic>? ?? [],
    );
  }

  static String _detectMessageType(dynamic lastMsg) {
    try {
      if (lastMsg is Map && lastMsg['type'] != null) {
        return lastMsg['type'].toString();
      }
      
      String content = '';
      if (lastMsg is Map) {
        content = lastMsg['content']?.toString() ?? '';
      } else if (lastMsg is String) {
        content = lastMsg;
      }
      
      content = content.trim();
      if (content.startsWith('[') && content.endsWith(']')) {
        return 'image';
      }
      
      if (content.startsWith('http') && (content.contains('cloudinary') || content.endsWith('.jpg') || content.endsWith('.png'))) {
        return 'image';
      }
    } catch (_) {}
    
    return 'text';
  }
}
