import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_model.dart';

class HomeScreen extends StatefulWidget {
  final UserModel user;

  const HomeScreen({
    super.key,
    required this.user,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _baseUrl = 'https://hashledger-backend.vercel.app';

  int _selectedIndex = 0;

  late int _points;

  bool _miningLoading = false;
  int _cooldownLeft = 0;
  Timer? _cooldownTimer;

  int _todayMines = 0;
  int _loginStreak = 1;
  bool _historySeenToday = false;

  bool _historyLoading = false;
  String? _historyError;
  List<_HistoryEntry> _history = [];

  String? _message;

  @override
  void initState() {
    super.initState();
    _points = widget.user.points;
    _loadLocalProgress();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  String get _emailKey {
    return widget.user.email.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
  }

  String get _todayKey {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }

  String get _yesterdayKey {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return '${yesterday.year}-${yesterday.month}-${yesterday.day}';
  }

  Future<void> _loadLocalProgress() async {
    final prefs = await SharedPreferences.getInstance();

    final lastOpenKey = 'hl_${_emailKey}_last_open';
    final streakKey = 'hl_${_emailKey}_login_streak';
    final minesKey = 'hl_${_emailKey}_mines_$_todayKey';
    final historyKey = 'hl_${_emailKey}_history_seen_$_todayKey';

    final lastOpen = prefs.getString(lastOpenKey);
    int streak = prefs.getInt(streakKey) ?? 0;

    if (lastOpen != _todayKey) {
      if (lastOpen == _yesterdayKey) {
        streak += 1;
      } else {
        streak = 1;
      }

      await prefs.setString(lastOpenKey, _todayKey);
      await prefs.setInt(streakKey, streak);
    }

    if (!mounted) return;

    setState(() {
      _loginStreak = streak <= 0 ? 1 : streak;
      _todayMines = prefs.getInt(minesKey) ?? 0;
      _historySeenToday = prefs.getBool(historyKey) ?? false;
    });
  }

  Future<void> _saveTodayMines() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('hl_${_emailKey}_mines_$_todayKey', _todayMines);
  }

  Future<void> _markHistorySeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hl_${_emailKey}_history_seen_$_todayKey', true);

    if (!mounted) return;

    setState(() {
      _historySeenToday = true;
    });
  }

  _LevelData _calculateLevel(int totalPoints) {
    int level = 1;
    int remainingXp = max(totalPoints, 0);
    int neededXp = 300;

    while (remainingXp >= neededXp) {
      remainingXp -= neededXp;
      level += 1;
      neededXp = 300 + ((level - 1) * 150);
    }

    return _LevelData(
      level: level,
      currentXp: remainingXp,
      neededXp: neededXp,
    );
  }

  Future<void> _mine() async {
    if (_miningLoading || _cooldownLeft > 0) return;

    setState(() {
      _miningLoading = true;
      _message = null;
    });

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/mine'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.user.token}',
        },
      );

      final dynamic decoded = response.body.isNotEmpty
          ? jsonDecode(response.body)
          : <String, dynamic>{};

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final reward = _asInt(decoded['reward']) ?? 0;
        final newTotal = _asInt(decoded['new_total']) ??
            _asInt(decoded['newTotal']) ??
            _asInt(decoded['points']) ??
            (_points + reward);

        final cooldown = _asInt(decoded['cooldown_seconds']) ??
            _asInt(decoded['cooldownSeconds']) ??
            30;

        _todayMines += 1;
        await _saveTodayMines();

        if (!mounted) return;

        setState(() {
          _points = newTotal;
          _message = reward > 0
              ? '+$reward points ajoutés'
              : 'Session validée';
        });

        _startCooldown(cooldown);
      } else {
        final backendMessage = decoded is Map<String, dynamic>
            ? decoded['message'] ?? decoded['error']
            : null;

        final cooldown = decoded is Map<String, dynamic>
            ? _asInt(decoded['cooldown_seconds']) ??
                _asInt(decoded['cooldownSeconds']) ??
                _asInt(decoded['remaining_seconds'])
            : null;

        if (cooldown != null && cooldown > 0) {
          _startCooldown(cooldown);
        }

        if (!mounted) return;

        setState(() {
          _message = backendMessage?.toString() ??
              'Impossible de miner pour le moment.';
        });
      }
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _message = 'Erreur de connexion avec le serveur.';
      });
    } finally {
      if (!mounted) return;

      setState(() {
        _miningLoading = false;
      });
    }
  }

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();

    setState(() {
      _cooldownLeft = max(seconds, 0);
    });

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_cooldownLeft <= 1) {
        timer.cancel();
        setState(() {
          _cooldownLeft = 0;
        });
      } else {
        setState(() {
          _cooldownLeft -= 1;
        });
      }
    });
  }

  Future<void> _loadHistory() async {
    setState(() {
      _historyLoading = true;
      _historyError = null;
    });

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/mining-history'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.user.token}',
        },
      );

      final dynamic decoded = response.body.isNotEmpty
          ? jsonDecode(response.body)
          : <String, dynamic>{};

      if (response.statusCode >= 200 && response.statusCode < 300) {
        dynamic rawList;

        if (decoded is List) {
          rawList = decoded;
        } else if (decoded is Map<String, dynamic>) {
          rawList = decoded['history'] ??
              decoded['logs'] ??
              decoded['mining_history'] ??
              decoded['data'] ??
              [];
        } else {
          rawList = [];
        }

        final entries = <_HistoryEntry>[];

        if (rawList is List) {
          for (final item in rawList) {
            if (item is Map<String, dynamic>) {
              entries.add(_HistoryEntry.fromJson(item));
            }
          }
        }

        if (!mounted) return;

        setState(() {
          _history = entries;
        });
      } else {
        if (!mounted) return;

        setState(() {
          _historyError = 'Impossible de charger l’historique.';
        });
      }
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _historyError = 'Erreur de connexion avec le serveur.';
      });
    } finally {
      if (!mounted) return;

      setState(() {
        _historyLoading = false;
      });
    }
  }

  void _onNavTap(int index) {
    setState(() {
      _selectedIndex = index;
    });

    if (index == 1) {
      _markHistorySeen();
      _loadHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildHomePage(),
      _buildHistoryPage(),
      _buildWithdrawPage(),
      _buildProfilePage(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF05070C),
      body: SafeArea(
        child: pages[_selectedIndex],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHomePage() {
    final levelData = _calculateLevel(_points);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0A1020),
            Color(0xFF05070C),
          ],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          _buildHeader(levelData),
          const SizedBox(height: 16),
          _buildLevelCard(levelData),
          const SizedBox(height: 16),
          _buildMiningCard(),
          const SizedBox(height: 16),
          _buildDailyMissions(levelData),
          const SizedBox(height: 16),
          _buildReturnObjectives(levelData),
        ],
      ),
    );
  }

  Widget _buildHeader(_LevelData levelData) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'HashLedger',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.user.email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFF2DE2A6).withOpacity(0.35),
            ),
          ),
          child: Column(
            children: [
              Text(
                'Niv. ${levelData.level}',
                style: const TextStyle(
                  color: Color(0xFF2DE2A6),
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$_points pts',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.65),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLevelCard(_LevelData levelData) {
    return _SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconBubble(
                icon: Icons.workspace_premium_rounded,
                color: const Color(0xFFFFC857),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Niveau ${levelData.level}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${levelData.xpToNext} XP restants avant le niveau ${levelData.level + 1}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.58),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(50),
            child: LinearProgressIndicator(
              value: levelData.progress,
              minHeight: 12,
              backgroundColor: Colors.white.withOpacity(0.08),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF2DE2A6),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${levelData.currentXp} XP',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.62),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${levelData.neededXp} XP',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.62),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiningCard() {
    final canMine = !_miningLoading && _cooldownLeft <= 0;

    return _SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconBubble(
                icon: Icons.bolt_rounded,
                color: const Color(0xFF7C5CFF),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Session de minage',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _cooldownLeft > 0
                          ? 'Prochaine session dans $_cooldownLeft s'
                          : 'Disponible maintenant',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.58),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_message != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _message!,
                style: const TextStyle(
                  color: Color(0xFF2DE2A6),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: canMine ? _mine : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2DE2A6),
                disabledBackgroundColor: Colors.white.withOpacity(0.08),
                foregroundColor: const Color(0xFF04110D),
                disabledForegroundColor: Colors.white.withOpacity(0.45),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: _miningLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Color(0xFF04110D),
                      ),
                    )
                  : Text(
                      _cooldownLeft > 0
                          ? 'Cooldown $_cooldownLeft s'
                          : 'Miner maintenant',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyMissions(_LevelData levelData) {
    return _SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            title: 'Missions du jour',
            subtitle: 'Affichage visuel uniquement pour le moment',
            icon: Icons.task_alt_rounded,
          ),
          const SizedBox(height: 14),
          _MissionTile(
            icon: Icons.rocket_launch_rounded,
            title: 'Lancer 1 minage',
            subtitle: 'Créer une première action aujourd’hui',
            current: min(_todayMines, 1),
            target: 1,
            tag: '+ bonus bientôt',
          ),
          const SizedBox(height: 10),
          _MissionTile(
            icon: Icons.local_fire_department_rounded,
            title: 'Faire 3 sessions',
            subtitle: 'Objectif simple pour revenir plusieurs fois',
            current: min(_todayMines, 3),
            target: 3,
            tag: '+ XP bientôt',
          ),
          const SizedBox(height: 10),
          _MissionTile(
            icon: Icons.history_rounded,
            title: 'Consulter l’historique',
            subtitle: 'Pousse l’utilisateur à vérifier ses gains',
            current: _historySeenToday ? 1 : 0,
            target: 1,
            tag: 'visuel',
          ),
          const SizedBox(height: 10),
          _MissionTile(
            icon: Icons.trending_up_rounded,
            title: 'Avancer vers le niveau suivant',
            subtitle: '${levelData.currentXp}/${levelData.neededXp} XP',
            current: levelData.currentXp,
            target: levelData.neededXp,
            tag: 'progression',
          ),
        ],
      ),
    );
  }

  Widget _buildReturnObjectives(_LevelData levelData) {
    final streakProgress = min(_loginStreak, 7);

    return _SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            title: 'Objectifs',
            subtitle: 'Des raisons de revenir dans l’app',
            icon: Icons.flag_rounded,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ObjectiveBox(
                  title: 'Prochain niveau',
                  value: '${levelData.xpToNext} XP',
                  subtitle: 'à gagner',
                  icon: Icons.arrow_upward_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ObjectiveBox(
                  title: 'Série',
                  value: '$_loginStreak jour${_loginStreak > 1 ? 's' : ''}',
                  subtitle: 'connexion',
                  icon: Icons.calendar_month_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.045),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withOpacity(0.07),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.emoji_events_rounded,
                      color: Color(0xFFFFC857),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Objectif 7 jours',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '$streakProgress/7',
                      style: const TextStyle(
                        color: Color(0xFFFFC857),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(50),
                  child: LinearProgressIndicator(
                    value: (streakProgress / 7).clamp(0.0, 1.0).toDouble(),
                    minHeight: 10,
                    backgroundColor: Colors.white.withOpacity(0.08),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFFFFC857),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Plus tard, on pourra donner un bonus serveur quand l’utilisateur garde sa série.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryPage() {
    return Container(
      color: const Color(0xFF05070C),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Historique',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                onPressed: _historyLoading ? null : _loadHistory,
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_historyLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(top: 40),
                child: CircularProgressIndicator(
                  color: Color(0xFF2DE2A6),
                ),
              ),
            )
          else if (_historyError != null)
            _SoftCard(
              child: Text(
                _historyError!,
                style: const TextStyle(color: Colors.white),
              ),
            )
          else if (_history.isEmpty)
            _SoftCard(
              child: Text(
                'Aucun historique pour le moment.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.65),
                  fontSize: 14,
                ),
              ),
            )
          else
            ..._history.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _SoftCard(
                  child: Row(
                    children: [
                      _IconBubble(
                        icon: Icons.bolt_rounded,
                        color: const Color(0xFF2DE2A6),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          entry.dateLabel,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Text(
                        '+${entry.reward}',
                        style: const TextStyle(
                          color: Color(0xFF2DE2A6),
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWithdrawPage() {
    return Container(
      color: const Color(0xFF05070C),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          const Text(
            'Retrait',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          _SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle(
                  title: 'Retraits bientôt disponibles',
                  subtitle: 'Pour le moment, les points restent internes.',
                  icon: Icons.account_balance_wallet_rounded,
                ),
                const SizedBox(height: 16),
                Text(
                  'Solde actuel',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$_points points',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.045),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    'Plus tard, on ajoutera le minimum de retrait, le wallet crypto et la validation côté serveur.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.62),
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfilePage() {
    final levelData = _calculateLevel(_points);

    return Container(
      color: const Color(0xFF05070C),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          const Text(
            'Profil',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          _SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle(
                  title: 'Compte utilisateur',
                  subtitle: widget.user.email,
                  icon: Icons.person_rounded,
                ),
                const SizedBox(height: 18),
                _ProfileLine(
                  label: 'Points',
                  value: '$_points',
                ),
                _ProfileLine(
                  label: 'Niveau',
                  value: '${levelData.level}',
                ),
                _ProfileLine(
                  label: 'Série de connexion',
                  value: '$_loginStreak jour${_loginStreak > 1 ? 's' : ''}',
                ),
                _ProfileLine(
                  label: 'Minages aujourd’hui',
                  value: '$_todayMines',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF080B12),
        border: Border(
          top: BorderSide(
            color: Colors.white.withOpacity(0.08),
          ),
        ),
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onNavTap,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: const Color(0xFF2DE2A6),
        unselectedItemColor: Colors.white.withOpacity(0.38),
        selectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded),
            label: 'Accueil',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_rounded),
            label: 'Historique',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_rounded),
            label: 'Retrait',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_rounded),
            label: 'Profil',
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Row(
      children: [
        _IconBubble(
          icon: icon,
          color: const Color(0xFF2DE2A6),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 12.5,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SoftCard extends StatelessWidget {
  final Widget child;

  const _SoftCard({
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827).withOpacity(0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _IconBubble extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _IconBubble({
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: color.withOpacity(0.28),
        ),
      ),
      child: Icon(
        icon,
        color: color,
        size: 22,
      ),
    );
  }
}

class _MissionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final int current;
  final int target;
  final String tag;

  const _MissionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.current,
    required this.target,
    required this.tag,
  });

  @override
  Widget build(BuildContext context) {
    final progress = target <= 0
        ? 0.0
        : (current / target).clamp(0.0, 1.0).toDouble();

    final completed = current >= target;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: completed
              ? const Color(0xFF2DE2A6).withOpacity(0.35)
              : Colors.white.withOpacity(0.07),
        ),
      ),
      child: Row(
        children: [
          Icon(
            completed ? Icons.check_circle_rounded : icon,
            color: completed
                ? const Color(0xFF2DE2A6)
                : Colors.white.withOpacity(0.75),
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.62),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.52),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 9),
                ClipRRect(
                  borderRadius: BorderRadius.circular(50),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 7,
                    backgroundColor: Colors.white.withOpacity(0.08),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      completed
                          ? const Color(0xFF2DE2A6)
                          : const Color(0xFF7C5CFF),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$current/$target',
            style: TextStyle(
              color: completed
                  ? const Color(0xFF2DE2A6)
                  : Colors.white.withOpacity(0.58),
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ObjectiveBox extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;

  const _ObjectiveBox({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(0.07),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: const Color(0xFF2DE2A6),
            size: 22,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.45),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileLine extends StatelessWidget {
  final String label;
  final String value;

  const _ProfileLine({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withOpacity(0.06),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.55),
                fontSize: 14,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelData {
  final int level;
  final int currentXp;
  final int neededXp;

  const _LevelData({
    required this.level,
    required this.currentXp,
    required this.neededXp,
  });

  int get xpToNext => max(neededXp - currentXp, 0);

  double get progress {
    if (neededXp <= 0) return 0;
    return (currentXp / neededXp).clamp(0.0, 1.0).toDouble();
  }
}

class _HistoryEntry {
  final int reward;
  final String rawDate;

  const _HistoryEntry({
    required this.reward,
    required this.rawDate,
  });

  factory _HistoryEntry.fromJson(Map<String, dynamic> json) {
    return _HistoryEntry(
      reward: _asInt(
            json['reward'] ??
                json['points'] ??
                json['amount'] ??
                json['earned_points'],
          ) ??
          0,
      rawDate: (json['created_at'] ??
              json['createdAt'] ??
              json['mined_at'] ??
              json['date'] ??
              json['timestamp'] ??
              '')
          .toString(),
    );
  }

  String get dateLabel {
    if (rawDate.isEmpty) return 'Session de minage';

    try {
      final parsed = DateTime.parse(rawDate).toLocal();
      final day = parsed.day.toString().padLeft(2, '0');
      final month = parsed.month.toString().padLeft(2, '0');
      final hour = parsed.hour.toString().padLeft(2, '0');
      final minute = parsed.minute.toString().padLeft(2, '0');

      return '$day/$month à $hour:$minute';
    } catch (_) {
      return rawDate;
    }
  }
}

int? _asInt(dynamic value) {
  if (value == null) return null;

  if (value is int) return value;

  if (value is double) return value.round();

  if (value is String) {
    return int.tryParse(value);
  }

  return null;
}