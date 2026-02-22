import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/user_model.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool loading = false;

  Future<void> handleAuth(bool isLogin) async {
    if (loading) return;

    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Email et mot de passe requis")),
      );
      return;
    }

    setState(() => loading = true);

    Map<String, dynamic> data;

    try {
      if (isLogin) {
        data = await ApiService.login(email, password);
      } else {
        data = await ApiService.register(email, password);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur réseau")),
      );
      return;
    }

    if (!mounted) return;
    setState(() => loading = false);

    if (data.containsKey("error")) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data["error"])),
      );
      return;
    }

    UserModel user =
        UserModel.fromJson(data["user"], data["token"]);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => HomeScreen(user: user),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("HashLedger Login")),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: emailController,
              decoration: InputDecoration(labelText: "Email"),
            ),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: InputDecoration(labelText: "Mot de passe"),
            ),
            SizedBox(height: 20),

            loading
                ? CircularProgressIndicator()
                : Column(
                    children: [
                      ElevatedButton(
                        onPressed: () => handleAuth(true),
                        child: Text("Se connecter"),
                      ),
                      ElevatedButton(
                        onPressed: () => handleAuth(false),
                        child: Text("S’inscrire"),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}