import 'dart:async';
import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  final UserModel user;

  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late UserModel currentUser;

  bool miningActive = false;
  bool loadingMine = false;
  bool refreshingUser = false;
  bool loadingHistory = false;

  int countdown = 30;
  int cooldownSeconds = 30;
  int dailyUsed = 0;
  int dailyLimit = 200;
  int todayHistoryCount = 0;
  int todayHistoryPoints = 0;

  List<Map<String, dynamic>> miningHistory = [];

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    currentUser = widget.user;
    refreshAll();
  }

  Future<void> refreshAll() async {
    await refreshUser();
    await refreshMiningHistory();
  }

  Future<void> refreshUser() async {
    if (refreshingUser) return;

    setState(() {
      refreshingUser = true;
    });

    final result = await ApiService.getUser(currentUser.token);

    if (!mounted) return;

    setState(() {
      refreshingUser = false;
    });

    if (result.containsKey("error")) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result["error"].toString())),
      );
      return;
    }

    setState(() {
      currentUser = UserModel.fromJson(result, currentUser.token);
      dailyUsed = _parseInt(result["sessions_today"]);
    });
  }

  Future<void> refreshMiningHistory() async {
    if (loadingHistory) return;

    setState(() {
      loadingHistory = true;
    });

    final result = await ApiService.getMiningHistory(currentUser.token);

    if (!mounted) return;

    setState(() {
      loadingHistory = false;
    });

    if (result.containsKey("error")) {
      return;
    }

    final rawHistory = result["history"];

    setState(() {
      todayHistoryCount = _parseInt(result["today_count"]);
      todayHistoryPoints = _parseInt(result["today_points"]);

      if (rawHistory is List) {
        miningHistory = rawHistory
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      } else {
        miningHistory = [];
      }
    });
  }

  void startMiningCountdown() {
    if (miningActive || loadingMine) return;

    setState(() {
      miningActive = true;
      countdown = cooldownSeconds;
    });

    _timer?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      setState(() {
        countdown--;
      });

      if (countdown <= 0) {
        timer.cancel();
        sendMineRequest();
      }
    });
  }

  Future<void> sendMineRequest() async {
    if (loadingMine) return;

    setState(() {
      loadingMine = true;
      miningActive = false;
    });

    final result = await ApiService.mine(currentUser.token);

    if (!mounted) return;

    setState(() {
      loadingMine = false;
    });

    if (result.containsKey("error")) {
      final secondsRemaining = _parseInt(result["seconds_remaining"]);

      if (secondsRemaining > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Cooldown actif : attends encore $secondsRemaining secondes",
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result["error"].toString())),
        );
      }

      return;
    }

    final int newTotal = _parseInt(result["new_total"]);
    final int reward = _parseInt(result["reward"]);

    setState(() {
      currentUser = currentUser.copyWith(points: newTotal);
      dailyUsed = _parseInt(result["daily_used"]);
      dailyLimit = _parseInt(result["daily_limit"]);
      cooldownSeconds = _parseInt(result["cooldown_seconds"]);
    });

    await refreshMiningHistory();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Mining réussi : +$reward points")),
    );
  }

  int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  String _formatDate(dynamic value) {
    if (value == null) return "";

    try {
      final date = DateTime.parse(value.toString()).toLocal();

      final day = date.day.toString().padLeft(2, "0");
      final month = date.month.toString().padLeft(2, "0");
      final hour = date.hour.toString().padLeft(2, "0");
      final minute = date.minute.toString().padLeft(2, "0");

      return "$day/$month à $hour:$minute";
    } catch (e) {
      return value.toString();
    }
  }

  Future<void> logout() async {
    _timer?.cancel();

    await StorageService.clearToken();

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Widget _buildInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "Email : ${currentUser.email}",
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            Text(
              "Points : ${currentUser.points}",
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              currentUser.isPremium ? "Compte premium" : "Compte standard",
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            Text(
              "Sessions aujourd’hui : $dailyUsed / $dailyLimit",
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              "Historique aujourd’hui : $todayHistoryCount sessions / +$todayHistoryPoints points",
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiningSection() {
    if (refreshingUser || loadingMine) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (miningActive) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Text(
                "Mining en cours...",
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 12),
              Text(
                "$countdown s",
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "La récompense sera envoyée à la fin du timer.",
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ElevatedButton(
      onPressed: startMiningCountdown,
      child: const Text("Lancer le mining"),
    );
  }

  Widget _buildHistorySection() {
    final lastItems = miningHistory.take(5).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    "Dernières sessions",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (loadingHistory)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: refreshMiningHistory,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (lastItems.isEmpty)
              const Text(
                "Aucune session de minage pour le moment.",
                textAlign: TextAlign.center,
              )
            else
              Column(
                children: lastItems.map((item) {
                  final reward = _parseInt(item["reward"]);
                  final createdAt = _formatDate(item["created_at"]);

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.bolt),
                    title: Text("+$reward points"),
                    subtitle: Text(createdAt),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("HashLedger"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: refreshingUser ? null : refreshAll,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: logout,
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: refreshAll,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildInfoCard(),
                const SizedBox(height: 24),
                _buildMiningSection(),
                const SizedBox(height: 24),
                _buildHistorySection(),
                const SizedBox(height: 24),
                const Text(
                  "Backend connecté : Vercel + Neon",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}