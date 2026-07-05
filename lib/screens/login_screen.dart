import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  final String? startupError;

  const LoginScreen({
    super.key,
    this.startupError,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool loading = false;
  bool startupErrorShown = false;
  bool passwordHidden = true;

  static const Color bg = Color(0xFF070B16);
  static const Color card = Color(0xFF111827);
  static const Color cardSoft = Color(0xFF172033);
  static const Color border = Color(0xFF243047);
  static const Color blue = Color(0xFF3B82F6);
  static const Color cyan = Color(0xFF22D3EE);
  static const Color green = Color(0xFF22C55E);
  static const Color textMain = Color(0xFFF8FAFC);
  static const Color textMuted = Color(0xFF94A3B8);

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      showStartupErrorIfNeeded();
    });
  }

  void showStartupErrorIfNeeded() {
    if (!mounted) return;
    if (startupErrorShown) return;

    final error = widget.startupError;

    if (error == null || error.isEmpty) return;

    startupErrorShown = true;
    _showMessage(error, isError: true);
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor:
            isError ? const Color(0xFF991B1B) : const Color(0xFF166534),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  Future<void> handleAuth(bool isLogin) async {
    if (loading) return;

    FocusScope.of(context).unfocus();

    final email = emailController.text.trim().toLowerCase();
    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showMessage("Email et mot de passe requis", isError: true);
      return;
    }

    if (!email.contains("@")) {
      _showMessage("Email invalide", isError: true);
      return;
    }

    if (password.length < 6) {
      _showMessage(
        "Le mot de passe doit contenir au moins 6 caractères",
        isError: true,
      );
      return;
    }

    setState(() {
      loading = true;
    });

    Map<String, dynamic> data;

    try {
      if (isLogin) {
        data = await ApiService.login(email, password);
      } else {
        data = await ApiService.register(email, password);
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });

      _showMessage("Erreur réseau", isError: true);
      return;
    }

    if (!mounted) return;

    setState(() {
      loading = false;
    });

    if (data.containsKey("error")) {
      _showMessage(data["error"].toString(), isError: true);
      return;
    }

    if (!data.containsKey("token") || !data.containsKey("user")) {
      _showMessage("Réponse serveur invalide", isError: true);
      return;
    }

    final token = data["token"];
    final userData = data["user"];

    if (token == null || userData == null || userData is! Map<String, dynamic>) {
      _showMessage("Token ou utilisateur manquant", isError: true);
      return;
    }

    final user = UserModel.fromJson(userData, token.toString());

    await StorageService.saveToken(user.token);

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => HomeScreen(user: user),
      ),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Widget _logoHeader() {
    return Column(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [blue, cyan],
            ),
            boxShadow: [
              BoxShadow(
                color: blue.withOpacity(0.30),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: const Icon(
            Icons.auto_graph_rounded,
            color: Colors.white,
            size: 38,
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          "HashLedger",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: textMain,
            fontSize: 34,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "Connecte-toi pour lancer tes sessions\net suivre ta progression.",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: textMuted,
            fontSize: 14,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _authCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 20,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "Accès au compte",
            style: TextStyle(
              color: textMain,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            "Utilise ton email et ton mot de passe.",
            style: TextStyle(
              color: textMuted,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),
          _inputField(
            controller: emailController,
            label: "Email",
            icon: Icons.email_rounded,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          _inputField(
            controller: passwordController,
            label: "Mot de passe",
            icon: Icons.lock_rounded,
            obscureText: passwordHidden,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => handleAuth(true),
            suffixIcon: IconButton(
              onPressed: () {
                setState(() {
                  passwordHidden = !passwordHidden;
                });
              },
              icon: Icon(
                passwordHidden
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                color: textMuted,
              ),
            ),
          ),
          const SizedBox(height: 22),
          if (loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircularProgressIndicator(color: cyan),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _primaryButton(
                  label: "Se connecter",
                  icon: Icons.login_rounded,
                  onTap: () => handleAuth(true),
                ),
                const SizedBox(height: 12),
                _secondaryButton(
                  label: "Créer un compte",
                  icon: Icons.person_add_alt_1_rounded,
                  onTap: () => handleAuth(false),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    bool obscureText = false,
    Widget? suffixIcon,
    void Function(String)? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      autocorrect: false,
      enableSuggestions: false,
      onSubmitted: onSubmitted,
      style: const TextStyle(
        color: textMain,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: textMuted),
        prefixIcon: Icon(icon, color: cyan, size: 21),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: cardSoft,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: cyan, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [blue, cyan],
          ),
          boxShadow: [
            BoxShadow(
              color: blue.withOpacity(0.28),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _secondaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: blue.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: blue.withOpacity(0.25)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: cyan, size: 21),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: cyan,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _securityNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: green.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: green.withOpacity(0.18)),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.shield_rounded,
            color: green,
            size: 22,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "Connexion sécurisée avec ton compte HashLedger.",
              style: TextStyle(
                color: textMuted,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              _logoHeader(),
              const SizedBox(height: 30),
              _authCard(),
              const SizedBox(height: 16),
              _securityNote(),
            ],
          ),
        ),
      ),
    );
  }
}