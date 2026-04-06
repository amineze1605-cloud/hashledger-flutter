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
    final dynamic rawPoints = json['points'];

    int parsedPoints = 0;

    if (rawPoints is int) {
      parsedPoints = rawPoints;
    } else if (rawPoints is String) {
      parsedPoints = int.tryParse(rawPoints) ?? 0;
    }

    return UserModel(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      points: parsedPoints,
      token: token,
      isPremium: json['is_premium'] == true,
    );
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