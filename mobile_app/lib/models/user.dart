class User {
  final String id;
  final String email;
  final String name;
  final String? username;
  final String? bio;
  final String? avatar;
  final List<String> photos;
  final String gender;
  final List<String> interestedIn;
  final String status;

  User({
    required this.id,
    required this.email,
    required this.name,
    this.username,
    this.bio,
    this.avatar,
    this.photos = const [],
    this.gender = 'Other',
    this.interestedIn = const [],
    this.status = 'offline',
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      name: json['name']?.toString() ?? 'User',
      username: json['username']?.toString(),
      bio: json['bio']?.toString(),
      avatar: (json['avatar']?.toString() ?? '').isEmpty ? null : json['avatar']?.toString(),
      photos: (json['photos'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      gender: json['gender']?.toString() ?? 'Other',
      interestedIn: (json['interestedIn'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      status: json['status']?.toString() ?? 'offline',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'bio': bio,
      'gender': gender,
      'interestedIn': interestedIn,
      'status': status,
    };
  }
}
