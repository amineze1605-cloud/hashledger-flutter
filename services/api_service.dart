import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const baseUrl = 'https://ton-backend.onrender.com';

  static Future<Map<String,dynamic>> register(String email, String password) async {
    var res = await http.post(
      Uri.parse('$baseUrl/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    return jsonDecode(res.body);
  }

  static Future<Map<String,dynamic>> login(String email, String password) async {
    var res = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    return jsonDecode(res.body);
  }

  static Future<Map<String,dynamic>> getUser(String token) async {
    var res = await http.get(
      Uri.parse('$baseUrl/user'),
      headers: {'Authorization': 'Bearer $token'},
    );
    return jsonDecode(res.body);
  }

  static Future<Map<String,dynamic>> addSession(String token, int basePoints, int bonusPoints) async {
    var res = await http.post(
      Uri.parse('$baseUrl/session'),
      headers: {'Authorization': 'Bearer $token','Content-Type':'application/json'},
      body: jsonEncode({'basePoints': basePoints,'bonusPoints':bonusPoints}),
    );
    return jsonDecode(res.body);
  }

  static Future<Map<String,dynamic>> withdraw(String token, int amountPoints, String solanaAddress) async {
    var res = await http.post(
      Uri.parse('$baseUrl/withdrawal'),
      headers: {'Authorization': 'Bearer $token','Content-Type':'application/json'},
      body: jsonEncode({'amountPoints': amountPoints,'solanaAddress':solanaAddress}),
    );
    return jsonDecode(res.body);
  }
}
