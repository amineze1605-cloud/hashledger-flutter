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
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.light,
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
  String? startupError;

  @override
  void initState() {
    super.initState();
    checkSession();
  }

  Future<void> checkSession() async {
    final token = await StorageService.getToken();

    if (!mounted) return;

    if (token == null || token.isEmpty) {
      setState(() {
        loading = false;
        user = null;
      });
      return;
    }

    final result = await ApiService.getUser(token);

    if (!mounted) return;

    if (result.containsKey("error")) {
      await StorageService.clearToken();

      if (!mounted) return;

      setState(() {
        loading = false;
        user = null;
        startupError = result["error"]?.toString();
      });
      return;
    }

    setState(() {
      user = UserModel.fromJson(result, token);
      loading = false;
      startupError = null;
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

    return LoginScreen(
      startupError: startupError,
    );
  }
}