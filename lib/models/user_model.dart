class UserModel {
  final String id;
  final String email;
  final int points;
  final String token;

  UserModel({required this.id, required this.email, required this.points, required this.token});

  factory UserModel.fromJson(Map<String, dynamic> json, String token) {
    return UserModel(
      id: json['id'],
      email: json['email'],
      points: json['points'] ?? 0,
      token: token,
    );
  }
}
