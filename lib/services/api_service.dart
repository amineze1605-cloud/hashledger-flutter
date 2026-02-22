import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const baseUrl = 'https://hashledger-backend.onrender.com';

  static Future<Map<String, dynamic>> _handleResponse(http.Response res) async {
    try {
      final data = jsonDecode(res.body);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return data;
      } else {
        return {
          "error": data["error"] ?? "Erreur serveur (${res.statusCode})"
        };
      }
    } catch (e) {
      return {"error": "Erreur réseau ou réponse invalide"};
    }
  }

  static Future<Map<String, dynamic>> register(
      String email, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    return _handleResponse(res);
  }

  static Future<Map<String, dynamic>> login(
      String email, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    return _handleResponse(res);
  }

  static Future<Map<String, dynamic>> getUser(String token) async {
    final res = await http.get(
      Uri.parse('$baseUrl/user'),
      headers: {'Authorization': 'Bearer $token'},
    );

    return _handleResponse(res);
  }

  static Future<Map<String, dynamic>> addSession(
      String token, int basePoints, int bonusPoints) async {
    final res = await http.post(
      Uri.parse('$baseUrl/session'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json'
      },
      body: jsonEncode({
        'basePoints': basePoints,
        'bonusPoints': bonusPoints
      }),
    );

    return _handleResponse(res);
  }

  static Future<Map<String, dynamic>> withdraw(
      String token, int amountPoints, String solanaAddress) async {
    final res = await http.post(
      Uri.parse('$baseUrl/withdrawal'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json'
      },
      body: jsonEncode({
        'amountPoints': amountPoints,
        'solanaAddress': solanaAddress
      }),
    );

    return _handleResponse(res);
  }
}