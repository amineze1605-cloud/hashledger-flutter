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
      _showMessage(result["error"].toString(), isError: true);
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

    _showMessage("Session réussie : +$reward points");
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

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError ? const Color(0xFF991B1B) : const Color(0xFF166534),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
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

  Widget _pageTitle() {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              colors: [blue, cyan],
            ),
          ),
          child: const Icon(
            Icons.auto_graph_rounded,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "HashLedger",
                style: TextStyle(
                  color: textMain,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 2),
              Text(
                "Sessions, points et progression",
                style: TextStyle(
                  color: textMuted,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        _roundIconButton(Icons.refresh_rounded, () async {
          await refreshUser();
          await loadMiningHistory();
        }),
        const SizedBox(width: 8),
        _roundIconButton(Icons.logout_rounded, logout),
      ],
    );
  }

  Widget _roundIconButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: Icon(
          icon,
          color: textMain,
          size: 21,
        ),
      ),
    );
  }

  Widget _balanceCard() {
    final progress = dailyLimit <= 0 ? 0.0 : (sessionsToday / dailyLimit).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1E3A8A),
            Color(0xFF111827),
            Color(0xFF052E3A),
          ],
        ),
        border: Border.all(color: const Color(0xFF315477)),
        boxShadow: [
          BoxShadow(
            color: blue.withOpacity(0.22),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_circle_rounded, color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  currentUser.email,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            "Solde actuel",
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "${currentUser.points}",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 7),
                child: Text(
                  "points",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withOpacity(0.10)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  currentUser.isPremium ? Icons.workspace_premium_rounded : Icons.shield_rounded,
                  color: currentUser.isPremium ? const Color(0xFFFACC15) : green,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  currentUser.isPremium ? "Compte premium" : "Compte standard",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Progression du jour",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),
              Text(
                "$sessionsToday / $dailyLimit",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 9,
              backgroundColor: Colors.white.withOpacity(0.14),
              valueColor: const AlwaysStoppedAnimation<Color>(cyan),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miningSection() {
    if (loadingMine) {
      return _darkCard(
        child: const Padding(
          padding: EdgeInsets.all(22),
          child: Column(
            children: [
              CircularProgressIndicator(color: cyan),
              SizedBox(height: 14),
              Text(
                "Validation de la session...",
                style: TextStyle(color: textMuted),
              ),
            ],
          ),
        ),
      );
    }

    if (miningActive) {
      return _darkCard(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Text(
                "Session active",
                style: TextStyle(
                  color: textMain,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "La récompense sera ajoutée à la fin du timer.",
                textAlign: TextAlign.center,
                style: TextStyle(color: textMuted),
              ),
              const SizedBox(height: 22),
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: cyan, width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: cyan.withOpacity(0.25),
                      blurRadius: 24,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    "$countdown s",
                    style: const TextStyle(
                      color: textMain,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return InkWell(
      onTap: startMiningCountdown,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [blue, cyan],
          ),
          boxShadow: [
            BoxShadow(
              color: blue.withOpacity(0.30),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bolt_rounded, color: Colors.white, size: 26),
            SizedBox(width: 8),
            Text(
              "Lancer une session",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyCard() {
    return _darkCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              icon: Icons.history_rounded,
              title: "Historique récent",
              subtitle: "Tes dernières sessions validées",
            ),
            const SizedBox(height: 14),
            if (loadingHistory)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: CircularProgressIndicator(color: cyan),
                ),
              )
            else if (miningHistory.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  "Aucune session enregistrée pour le moment.",
                  style: TextStyle(color: textMuted),
                ),
              )
            else
              Column(
                children: miningHistory.take(5).map((item) {
                  final reward = _parseInt(item["reward"]);
                  final createdAt = _formatDate(item["created_at"]);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cardSoft,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: green.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.bolt_rounded,
                            color: green,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "+$reward points",
                                style: const TextStyle(
                                  color: textMain,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                createdAt,
                                style: const TextStyle(
                                  color: textMuted,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.check_circle_rounded,
                          color: green,
                          size: 20,
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _rewardsPreview() {
    return _darkCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              icon: Icons.wallet_rounded,
              title: "Récompenses",
              subtitle: "Préparation du futur système de retrait",
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1F2937),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: border),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_clock_rounded, color: textMuted),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Les demandes de retrait seront ajoutées dans une prochaine étape.",
                      style: TextStyle(
                        color: textMuted,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: blue.withOpacity(0.14),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: blue.withOpacity(0.25)),
          ),
          child: Icon(icon, color: cyan),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: textMain,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _darkCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.20),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _backendStatus() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: green.withOpacity(0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: green.withOpacity(0.20)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_done_rounded, color: green, size: 18),
            SizedBox(width: 8),
            Text(
              "Backend connecté : Vercel + Neon",
              style: TextStyle(
                color: textMain,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: RefreshIndicator(
          color: cyan,
          backgroundColor: card,
          onRefresh: () async {
            await refreshUser();
            await loadMiningHistory();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _pageTitle(),
                const SizedBox(height: 18),
                _balanceCard(),
                const SizedBox(height: 24),
                if (refreshingUser)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 18),
                    child: Center(
                      child: CircularProgressIndicator(color: cyan),
                    ),
                  ),
                _miningSection(),
                const SizedBox(height: 24),
                _historyCard(),
                const SizedBox(height: 24),
                _rewardsPreview(),
                const SizedBox(height: 24),
                _backendStatus(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}