class UserModel {
  final String id;
  final String email;
  final int points;
  final String token;
  final bool isPremium;

  UserModel({
    required this.id,
    required this.email,
    required this.points,
    required this.token,
    required this.isPremium,
  });

  factory UserModel.fromJson(Map<String, dynamic> json, String token) {
    return UserModel(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      points: _parseInt(json['points']),
      token: token,
      isPremium: _parseBool(json['is_premium']),
    );
  }

  static int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static bool _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is String) {
      return value.toLowerCase() == 'true';
    }
    return false;
  }

  UserModel copyWith({
    String? id,
    String? email,
    int? points,
    String? token,
    bool? isPremium,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      points: points ?? this.points,
      token: token ?? this.token,
      isPremium: isPremium ?? this.isPremium,
    );
  }
}