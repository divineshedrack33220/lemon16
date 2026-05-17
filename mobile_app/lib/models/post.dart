class Post {
  final String id;
  final String userId;
  final String userName;
  final String? userAvatar;
  final List<String> userPhotos;
  final String content;
  final List<String> images;
  final String? category;
  final double? distance;
  final bool isFavorited;
  final String? userStatus;
  final DateTime createdAt;

  Post({
    required this.id,
    required this.userId,
    required this.userName,
    this.userAvatar,
    this.userPhotos = const [],
    required this.content,
    this.images = const [],
    this.category,
    this.distance,
    this.isFavorited = false,
    this.userStatus,
    required this.createdAt,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    final user = (json['user'] is Map) ? json['user'] as Map<String, dynamic> : null;
    
    // createdAt is int64 Unix timestamp in seconds
    DateTime parseCreatedAt(dynamic val) {
      if (val is int) {
        return DateTime.fromMillisecondsSinceEpoch(val * 1000);
      }
      if (val is String) {
        final i = int.tryParse(val);
        if (i != null) return DateTime.fromMillisecondsSinceEpoch(i * 1000);
        return DateTime.tryParse(val) ?? DateTime.now();
      }
      return DateTime.now();
    }

    return Post(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      userId: user?['id']?.toString() ?? user?['_id']?.toString() ?? json['userId']?.toString() ?? json['id']?.toString() ?? '',
      userName: user?['name']?.toString() ?? json['name']?.toString() ?? 'User',
      userAvatar: (user?['avatar']?.toString() ?? json['avatar']?.toString() ?? '').isEmpty ? null : (user?['avatar']?.toString() ?? json['avatar']?.toString()),
      userPhotos: (user?['photos'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      content: json['content']?.toString() ?? '',
      images: (json['media'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      category: json['category']?.toString(),
      distance: json['distance'] != null ? (json['distance'] is num ? (json['distance'] as num).toDouble() : double.tryParse(json['distance'].toString())) : null,
      isFavorited: false,
      userStatus: user?['status']?.toString() ?? json['status']?.toString(),
      createdAt: parseCreatedAt(json['createdAt']),
    );
  }
}
