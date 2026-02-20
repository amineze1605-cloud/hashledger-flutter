import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'home_screen.dart';
import '../models/user_model.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLoading = false;

  void handleLogin() async {
    setState(() { isLoading = true; });
    try {
      final data = await ApiService.login(emailController.text, passwordController.text);
      if (data['error'] != null) {
        showError(data['error']);
      } else {
        UserModel user = UserModel.fromJson(data['user'], data['token']);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => HomeScreen(user: user)),
        );
      }
    } catch (e) {
      showError(e.toString());
    }
    setState(() { isLoading = false; });
  }

  void handleRegister() async {
    setState(() { isLoading = true; });
    try {
      final data = await ApiService.register(emailController.text, passwordController.text);
      if (data['error'] != null) {
        showError(data['error']);
      } else {
        UserModel user = UserModel.fromJson(data['user'], data['token']);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => HomeScreen(user: user)),
        );
      }
    } catch (e) {
      showError(e.toString());
    }
    setState(() { isLoading = false; });
  }

  void showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('HashLedger Login')),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(controller: emailController, decoration: InputDecoration(labelText: 'Email')),
            SizedBox(height: 10),
            TextField(controller: passwordController, obscureText: true, decoration: InputDecoration(labelText: 'Mot de passe')),
            SizedBox(height: 20),
            isLoading
                ? CircularProgressIndicator()
                : Column(
                    children: [
                      ElevatedButton(onPressed: handleLogin, child: Text('Se connecter')),
                      ElevatedButton(onPressed: handleRegister, child: Text('S’inscrire')),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}
