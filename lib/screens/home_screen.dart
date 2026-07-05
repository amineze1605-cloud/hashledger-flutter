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
  int selectedIndex = 0;

  List<Map<String, dynamic>> miningHistory = [];

  Timer? _timer;

  static const Color bg = Color(0xFF070B16);
  static const Color card = Color(0xFF111827);
  static const Color cardSoft = Color(0xFF172033);
  static const Color border = Color(0xFF243047);
  static const Color blue = Color(0xFF3B82F6);
  static const Color cyan = Color(0xFF22D3EE);
  static const Color green = Color(0xFF22C55E);
  static const Color orange = Color(0xFFF97316);
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

  Widget _selectedPage() {
    switch (selectedIndex) {
      case 1:
        return _historyPage();
      case 2:
        return _withdrawPage();
      case 3:
        return _profilePage();
      default:
        return _homePage();
    }
  }

  Widget _homePage() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _pageTitle(),
          const SizedBox(height: 18),
          _balanceCard(),
          const SizedBox(height: 18),
          if (refreshingUser)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Center(
                child: CircularProgressIndicator(color: cyan),
              ),
            ),
          _miningSection(),
          const SizedBox(height: 18),
          _historyCard(),
          const SizedBox(height: 18),
          _rewardsPreview(),
          const SizedBox(height: 18),
          _backendStatus(),
        ],
      ),
    );
  }

  Widget _pageTitle() {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              colors: [blue, cyan],
            ),
          ),
          child: const Icon(
            Icons.auto_graph_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "HashLedger",
                style: TextStyle(
                  color: textMain,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 2),
              Text(
                "Sessions, points et progression",
                style: TextStyle(
                  color: textMuted,
                  fontSize: 12,
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
      borderRadius: BorderRadius.circular(15),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: border),
        ),
        child: Icon(
          icon,
          color: textMain,
          size: 20,
        ),
      ),
    );
  }

  Widget _balanceCard() {
    final double progress = dailyLimit <= 0
        ? 0.0
        : (sessionsToday / dailyLimit).clamp(0.0, 1.0).toDouble();

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
            color: blue.withOpacity(0.20),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_circle_rounded,
                color: Colors.white70,
                size: 19,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  currentUser.email,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            "Solde actuel",
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
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
                padding: EdgeInsets.only(bottom: 5),
                child: Text(
                  "points",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withOpacity(0.10)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  currentUser.isPremium
                      ? Icons.workspace_premium_rounded
                      : Icons.shield_rounded,
                  color: currentUser.isPremium ? const Color(0xFFFACC15) : green,
                  size: 17,
                ),
                const SizedBox(width: 7),
                Text(
                  currentUser.isPremium ? "Compte premium" : "Compte standard",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Progression du jour",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
              Text(
                "$sessionsToday / $dailyLimit",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
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
          padding: EdgeInsets.all(18),
          child: Column(
            children: [
              CircularProgressIndicator(color: cyan),
              SizedBox(height: 12),
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
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              const Text(
                "Session active",
                style: TextStyle(
                  color: textMain,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "La récompense sera ajoutée à la fin du timer.",
                textAlign: TextAlign.center,
                style: TextStyle(color: textMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Container(
                width: 98,
                height: 98,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: cyan, width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: cyan.withOpacity(0.22),
                      blurRadius: 22,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    "$countdown s",
                    style: const TextStyle(
                      color: textMain,
                      fontSize: 24,
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
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
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
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bolt_rounded, color: Colors.white, size: 25),
            SizedBox(width: 8),
            Text(
              "Lancer une session",
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
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
            const SizedBox(height: 12),
            _historyList(maxItems: 5),
            if (miningHistory.isNotEmpty) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () {
                  setState(() {
                    selectedIndex = 1;
                  });
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: blue.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: blue.withOpacity(0.20)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Voir tout l’historique",
                        style: TextStyle(
                          color: cyan,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 6),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: cyan,
                        size: 17,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _historyList({int? maxItems}) {
    if (loadingHistory) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(color: cyan),
        ),
      );
    }

    if (miningHistory.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          "Aucune session enregistrée pour le moment.",
          style: TextStyle(color: textMuted),
        ),
      );
    }

    final items =
        maxItems == null ? miningHistory : miningHistory.take(maxItems).toList();

    return Column(
      children: items.map((item) {
        final reward = _parseInt(item["reward"]);
        final createdAt = _formatDate(item["created_at"]);

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardSoft,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  color: green,
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "+$reward points",
                      style: const TextStyle(
                        color: textMain,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      createdAt,
                      style: const TextStyle(
                        color: textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.check_circle_rounded,
                color: green,
                size: 19,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _rewardsPreview() {
    return _darkCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              icon: Icons.wallet_rounded,
              title: "Récompenses",
              subtitle: "Préparation du futur système de retrait",
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1F2937),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_clock_rounded, color: textMuted, size: 21),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Les demandes de retrait seront ajoutées dans une prochaine étape.",
                      style: TextStyle(
                        color: textMuted,
                        fontSize: 12,
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

  Widget _historyPage() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _simpleHeader(
            icon: Icons.history_rounded,
            title: "Historique",
            subtitle: "Toutes tes dernières sessions validées",
          ),
          const SizedBox(height: 18),
          _darkCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeader(
                    icon: Icons.bolt_rounded,
                    title: "Sessions",
                    subtitle: "Points ajoutés à ton compte",
                  ),
                  const SizedBox(height: 12),
                  _historyList(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          _backendStatus(),
        ],
      ),
    );
  }

  Widget _withdrawPage() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _simpleHeader(
            icon: Icons.account_balance_wallet_rounded,
            title: "Retrait",
            subtitle: "Préparation du système de récompenses",
          ),
          const SizedBox(height: 18),
          _darkCard(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.lock_clock_rounded,
                    color: orange,
                    size: 42,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    "Retraits bientôt disponibles",
                    style: TextStyle(
                      color: textMain,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Cette section servira plus tard à demander un retrait ou une récompense selon les conditions de l’application.",
                    style: TextStyle(
                      color: textMuted,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cardSoft,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: border),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.stars_rounded,
                          color: cyan,
                          size: 26,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "Solde actuel : ${currentUser.points} points",
                            style: const TextStyle(
                              color: textMain,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: green.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: green.withOpacity(0.18)),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: green,
                          size: 24,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "Aucune promesse de gain n’est affichée ici. Le système sera ajouté proprement plus tard.",
                            style: TextStyle(
                              color: textMuted,
                              fontSize: 12,
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
          ),
        ],
      ),
    );
  }

  Widget _profilePage() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _simpleHeader(
            icon: Icons.person_rounded,
            title: "Profil",
            subtitle: "Compte, statut et progression",
          ),
          const SizedBox(height: 18),
          _darkCard(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: blue.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: blue.withOpacity(0.25)),
                        ),
                        child: const Icon(
                          Icons.account_circle_rounded,
                          color: cyan,
                          size: 34,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              currentUser.email,
                              style: const TextStyle(
                                color: textMain,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              currentUser.isPremium
                                  ? "Compte premium"
                                  : "Compte standard",
                              style: const TextStyle(
                                color: textMuted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      _miniStat(
                        title: "Points",
                        value: "${currentUser.points}",
                        icon: Icons.stars_rounded,
                        color: cyan,
                      ),
                      const SizedBox(width: 10),
                      _miniStat(
                        title: "Sessions",
                        value: "$sessionsToday/$dailyLimit",
                        icon: Icons.bolt_rounded,
                        color: green,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: logout,
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A1114),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFF7F1D1D)),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.logout_rounded,
                            color: Color(0xFFFCA5A5),
                          ),
                          SizedBox(width: 12),
                          Text(
                            "Se déconnecter",
                            style: TextStyle(
                              color: Color(0xFFFCA5A5),
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          _backendStatus(),
        ],
      ),
    );
  }

  Widget _miniStat({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardSoft,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                color: textMain,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: const TextStyle(
                color: textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _simpleHeader({
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
            borderRadius: BorderRadius.circular(15),
            gradient: const LinearGradient(
              colors: [blue, cyan],
            ),
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: 23,
          ),
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
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
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

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: blue.withOpacity(0.14),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: blue.withOpacity(0.25)),
          ),
          child: Icon(icon, color: cyan, size: 21),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: textMain,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: const TextStyle(
                  color: textMuted,
                  fontSize: 11,
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
            color: Colors.black.withOpacity(0.18),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _backendStatus() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: green.withOpacity(0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: green.withOpacity(0.20)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_done_rounded, color: green, size: 17),
            SizedBox(width: 7),
            Text(
              "Backend connecté : Vercel + Neon",
              style: TextStyle(
                color: textMain,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomNavigation() {
    return Container(
      decoration: const BoxDecoration(
        color: card,
        border: Border(
          top: BorderSide(color: border, width: 1),
        ),
      ),
      child: BottomNavigationBar(
        currentIndex: selectedIndex,
        onTap: (index) {
          setState(() {
            selectedIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: card,
        selectedItemColor: cyan,
        unselectedItemColor: textMuted,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_rounded),
            label: "Accueil",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_rounded),
            label: "Historique",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_rounded),
            label: "Retrait",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_rounded),
            label: "Profil",
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      bottomNavigationBar: _bottomNavigation(),
      body: SafeArea(
        child: RefreshIndicator(
          color: cyan,
          backgroundColor: card,
          onRefresh: () async {
            await refreshUser();
            await loadMiningHistory();
          },
          child: _selectedPage(),
        ),
      ),
    );
  }
}