import 'package:flutter/material.dart';
import 'models/user_model.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/api_service.dart';
import 'services/storage_service.dart';

void main() {
  runApp(const HashLedgerApp());
}

class HashLedgerApp extends StatelessWidget {
  const HashLedgerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HashLedger',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const AppStartupScreen(),
    );
  }
}

class AppStartupScreen extends StatefulWidget {
  const AppStartupScreen({super.key});

  @override
  State<AppStartupScreen> createState() => _AppStartupScreenState();
}

class _AppStartupScreenState extends State<AppStartupScreen> {
  bool loading = true;
  UserModel? user;

  @override
  void initState() {
    super.initState();
    checkSession();
  }

  Future<void> checkSession() async {
    final token = await StorageService.getToken();

    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() {
        loading = false;
      });
      return;
    }

    final result = await ApiService.getUser(token);

    if (!mounted) return;

    if (result.containsKey("error")) {
      await StorageService.clearToken();
      setState(() {
        loading = false;
      });
      return;
    }

    setState(() {
      user = UserModel.fromJson(result, token);
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (user != null) {
      return HomeScreen(user: user!);
    }

    return const LoginScreen();
  }
}