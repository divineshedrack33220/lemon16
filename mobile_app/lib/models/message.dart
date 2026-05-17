class Message {
  final String id;
  final String senderId;
  final String content;
  final String type;
  final DateTime createdAt;
  bool isRead;
  final Map<String, String>? reactions;

  Message({
    required this.id,
    required this.senderId,
    required this.content,
    this.type = 'text',
    required this.createdAt,
    this.isRead = false,
    this.reactions,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    // Handle createdAt as int (Unix timestamp) or String
    DateTime parseCreatedAt(dynamic value) {
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value * 1000);
      } else if (value is String) {
        return DateTime.tryParse(value) ?? DateTime.now();
      }
      return DateTime.now();
    }

    // Parse reactions map
    Map<String, String>? parseReactions(dynamic value) {
      if (value is Map<String, dynamic>) {
        return value.map((key, val) => MapEntry(key, val.toString()));
      }
      return null;
    }

    return Message(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      senderId: json['senderId']?.toString() ?? json['sender']?['_id']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      type: json['type']?.toString() ?? 'text',
      createdAt: parseCreatedAt(json['createdAt']),
      isRead: json['isRead'] == true,
      reactions: parseReactions(json['reactions']),
    );
  }
}
