import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'https://hashledger-backend.onrender.com';

  static Future<Map<String, dynamic>> _handleResponse(http.Response res) async {
    try {
      final data = jsonDecode(res.body);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return Map<String, dynamic>.from(data);
      } else {
        return {
          "error": data["error"] ?? "Erreur serveur (${res.statusCode})"
        };
      }
    } catch (e) {
      return {
        "error": "Erreur réseau ou réponse invalide"
      };
    }
  }

  static Future<Map<String, dynamic>> register(
    String email,
    String password,
  ) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/register'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': email.trim(),
          'password': password,
        }),
      );

      return _handleResponse(res);
    } catch (e) {
      return {"error": "Impossible de contacter le serveur"};
    }
  }

  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': email.trim(),
          'password': password,
        }),
      );

      return _handleResponse(res);
    } catch (e) {
      return {"error": "Impossible de contacter le serveur"};
    }
  }

  static Future<Map<String, dynamic>> getUser(String token) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/user'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      return _handleResponse(res);
    } catch (e) {
      return {"error": "Impossible de contacter le serveur"};
    }
  }

  static Future<Map<String, dynamic>> mine(String token) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/mine'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      return _handleResponse(res);
    } catch (e) {
      return {"error": "Impossible de contacter le serveur"};
    }
  }
}