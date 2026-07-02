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
  int sessionsToday = 0;
  int dailyLimit = 200;

  List<Map<String, dynamic>> miningHistory = [];

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    currentUser = widget.user;
    refreshUser();
    loadMiningHistory();
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
      return;
    }

    setState(() {
      currentUser = UserModel.fromJson(result, currentUser.token);
      sessionsToday = _parseInt(result["sessions_today"]);
    });
  }

  Future<void> loadMiningHistory() async {
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

    if (rawHistory is List) {
      setState(() {
        miningHistory = rawHistory
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      });
    }
  }

  void startMiningCountdown() {
    if (miningActive || loadingMine) return;

    setState(() {
      miningActive = true;
      countdown = 30;
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result["error"].toString())),
      );
      return;
    }

    final int newTotal = _parseInt(result["new_total"]);
    final int reward = _parseInt(result["reward"]);
    final int dailyUsed = _parseInt(result["daily_used"]);
    final int limit = _parseInt(result["daily_limit"]);

    setState(() {
      currentUser = currentUser.copyWith(points: newTotal);
      sessionsToday = dailyUsed;
      dailyLimit = limit == 0 ? 200 : limit;
    });

    await loadMiningHistory();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Mining réussi : +$reward points")),
    );
  }

  int _parseInt(dynamic value) {
    if (value is int) return value;
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

  Widget _buildUserCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Email : ${currentUser.email}",
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Text(
              "Points : ${currentUser.points}",
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              currentUser.isPremium ? "Compte premium" : "Compte standard",
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Text(
              "Sessions aujourd’hui : $sessionsToday / $dailyLimit",
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiningButton() {
    if (loadingMine) {
      return const Center(child: CircularProgressIndicator());
    }

    if (miningActive) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Text(
                "Mining en cours...",
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 14),
              Text(
                "$countdown s",
                style: const TextStyle(
                  fontSize: 34,
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

    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: startMiningCountdown,
        child: const Text("Lancer le mining"),
      ),
    );
  }

  Widget _buildHistoryCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Historique récent",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (loadingHistory)
              const Center(child: CircularProgressIndicator())
            else if (miningHistory.isEmpty)
              const Text("Aucune session enregistrée pour le moment.")
            else
              Column(
                children: miningHistory.take(5).map((item) {
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
            onPressed: () async {
              await refreshUser();
              await loadMiningHistory();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: logout,
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await refreshUser();
            await loadMiningHistory();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildUserCard(),
                const SizedBox(height: 24),
                if (refreshingUser)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 20),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                _buildMiningButton(),
                const SizedBox(height: 24),
                _buildHistoryCard(),
                const SizedBox(height: 24),
                const Center(
                  child: Text("Backend connecté : Vercel + Neon"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}