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

  static const int _withdrawTarget = 10000;

  int _selectedIndex = 0;

  late int _points;

  bool _miningLoading = false;
  bool _claimLoading = false;
  bool _dailyStatusLoading = false;

  int _cooldownLeft = 0;
  Timer? _cooldownTimer;

  int _todayMines = 0;
  int _loginStreak = 1;
  bool _historySeenToday = false;

  int _chestTarget = 3;
  int _chestReward = 25;
  bool _chestClaimed = false;
  bool _canClaimChest = false;

  bool _historyLoading = false;
  String? _historyError;
  List<_HistoryEntry> _history = [];

  String? _message;
  String? _chestMessage;

  @override
  void initState() {
    super.initState();
    _points = widget.user.points;
    _loadLocalProgress();
    _loadDailyStatus(silent: true);
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

  String _motivationText(_LevelData levelData) {
    if (_chestClaimed) {
      return 'Coffre du jour réclamé. Reviens demain pour garder ta série active.';
    }

    if (_canClaimChest) {
      return 'Coffre débloqué. Réclame ton bonus de $_chestReward points.';
    }

    if (_todayMines <= 0) {
      return 'Lance une première session pour activer tes missions du jour.';
    }

    if (_todayMines < _chestTarget) {
      final remaining = _chestTarget - _todayMines;
      return 'Encore $remaining session${remaining > 1 ? 's' : ''} pour débloquer le coffre du jour.';
    }

    if (levelData.xpToNext <= 100) {
      return 'Tu es proche du niveau ${levelData.level + 1}. Continue comme ça.';
    }

    return 'Objectif du jour validé. Reviens demain pour garder ta série active.';
  }

  Future<void> _loadDailyStatus({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _dailyStatusLoading = true;
        _chestMessage = null;
      });
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/daily-status'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.user.token}',
        },
      );

      final dynamic decoded = response.body.isNotEmpty
          ? jsonDecode(response.body)
          : <String, dynamic>{};

      final data = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final sessionsToday = _asInt(data['sessions_today']) ?? _todayMines;
        final chestTarget = _asInt(data['chest_target']) ?? _chestTarget;
        final chestReward = _asInt(data['chest_reward']) ?? _chestReward;
        final chestClaimed = data['chest_claimed'] == true;
        final canClaim = data['can_claim'] == true;
        final points = _asInt(data['points']) ?? _points;

        _todayMines = sessionsToday;
        await _saveTodayMines();

        if (!mounted) return;

        setState(() {
          _points = points;
          _todayMines = sessionsToday;
          _chestTarget = chestTarget;
          _chestReward = chestReward;
          _chestClaimed = chestClaimed;
          _canClaimChest = canClaim;
        });
      } else {
        if (!mounted || silent) return;

        setState(() {
          _chestMessage = data['error']?.toString() ??
              'Impossible de charger le coffre.';
        });
      }
    } catch (_) {
      if (!mounted || silent) return;

      setState(() {
        _chestMessage = 'Erreur de connexion au coffre.';
      });
    } finally {
      if (!mounted) return;

      if (!silent) {
        setState(() {
          _dailyStatusLoading = false;
        });
      }
    }
  }

  Future<void> _claimDailyChest() async {
    if (_claimLoading || !_canClaimChest || _chestClaimed) return;

    setState(() {
      _claimLoading = true;
      _chestMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/claim-daily-chest'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.user.token}',
        },
      );

      final dynamic decoded = response.body.isNotEmpty
          ? jsonDecode(response.body)
          : <String, dynamic>{};

      final data = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final reward = _asInt(data['reward']) ?? _chestReward;
        final newTotal = _asInt(data['new_total']) ?? (_points + reward);

        if (!mounted) return;

        setState(() {
          _points = newTotal;
          _chestClaimed = true;
          _canClaimChest = false;
          _chestMessage = '+$reward points ajoutés au coffre';
          _message = '+$reward points coffre ajoutés';
        });

        await _loadDailyStatus(silent: true);
        await _loadHistory();
      } else {
        if (!mounted) return;

        setState(() {
          _chestMessage = data['error']?.toString() ??
              'Impossible de réclamer le coffre.';

          if (response.statusCode == 409) {
            _chestClaimed = true;
            _canClaimChest = false;
          }
        });

        await _loadDailyStatus(silent: true);
      }
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _chestMessage = 'Erreur de connexion avec le serveur.';
      });
    } finally {
      if (!mounted) return;

      setState(() {
        _claimLoading = false;
      });
    }
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

      final data = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final reward = _asInt(data['reward']) ?? 0;
        final newTotal = _asInt(data['new_total']) ??
            _asInt(data['newTotal']) ??
            _asInt(data['points']) ??
            (_points + reward);

        final sessionsToday = _asInt(data['sessions_today']) ??
            _asInt(data['daily_used']) ??
            (_todayMines + 1);

        final cooldown = _asInt(data['cooldown_seconds']) ??
            _asInt(data['cooldownSeconds']) ??
            30;

        _todayMines = sessionsToday;
        await _saveTodayMines();

        if (!mounted) return;

        setState(() {
          _points = newTotal;
          _todayMines = sessionsToday;
          _canClaimChest = _todayMines >= _chestTarget && !_chestClaimed;
          _message = reward > 0 ? '+$reward points ajoutés' : 'Session validée';
        });

        _startCooldown(cooldown);
        await _loadDailyStatus(silent: true);
      } else {
        final backendMessage = data['message'] ?? data['error'];

        final cooldown = _asInt(data['cooldown_seconds']) ??
            _asInt(data['cooldownSeconds']) ??
            _asInt(data['remaining_seconds']);

        if (cooldown != null && cooldown > 0) {
          _startCooldown(cooldown);
        }

        if (!mounted) return;

        setState(() {
          _message = backendMessage?.toString() ??
              'Impossible de miner pour le moment.';
        });

        await _loadDailyStatus(silent: true);
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

    if (index == 0 || index == 2 || index == 3) {
      _loadDailyStatus(silent: true);
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
          _buildMotivationBanner(levelData),
          const SizedBox(height: 16),
          _buildLevelCard(levelData),
          const SizedBox(height: 16),
          _buildMiningCard(),
          const SizedBox(height: 16),
          _buildDailyChest(),
          const SizedBox(height: 16),
          _buildDailyMissions(levelData),
          const SizedBox(height: 16),
          _buildWithdrawGoal(),
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

  Widget _buildMotivationBanner(_LevelData levelData) {
    final chestReady = _canClaimChest || _chestClaimed;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: chestReady
              ? [
                  const Color(0xFF2DE2A6).withOpacity(0.18),
                  const Color(0xFFFFC857).withOpacity(0.12),
                ]
              : [
                  const Color(0xFF7C5CFF).withOpacity(0.18),
                  const Color(0xFF2DE2A6).withOpacity(0.10),
                ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: chestReady
              ? const Color(0xFFFFC857).withOpacity(0.35)
              : const Color(0xFF2DE2A6).withOpacity(0.22),
        ),
      ),
      child: Row(
        children: [
          Icon(
            chestReady
                ? Icons.card_giftcard_rounded
                : Icons.auto_awesome_rounded,
            color: chestReady ? const Color(0xFFFFC857) : const Color(0xFF2DE2A6),
            size: 26,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _motivationText(levelData),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
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

  Widget _buildDailyChest() {
    final current = min(_todayMines, _chestTarget);
    final progress = _chestTarget <= 0
        ? 0.0
        : (current / _chestTarget).clamp(0.0, 1.0).toDouble();

    final unlocked = _todayMines >= _chestTarget;
    final canClaim = _canClaimChest && !_chestClaimed;

    String buttonText;

    if (_claimLoading) {
      buttonText = 'Réclamation...';
    } else if (_chestClaimed) {
      buttonText = 'Déjà réclamé aujourd’hui';
    } else if (canClaim) {
      buttonText = 'Réclamer +$_chestReward points';
    } else {
      final remaining = max(_chestTarget - current, 0);
      buttonText =
          '$remaining session${remaining > 1 ? 's' : ''} restante${remaining > 1 ? 's' : ''}';
    }

    return _SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            title: 'Coffre quotidien',
            subtitle: _chestClaimed
                ? 'Bonus déjà réclamé aujourd’hui.'
                : unlocked
                    ? 'Coffre débloqué. Réclame ton bonus réel.'
                    : 'Débloque le coffre après $_chestTarget sessions aujourd’hui.',
            icon: Icons.card_giftcard_rounded,
            color: const Color(0xFFFFC857),
          ),
          const SizedBox(height: 16),
          if (_chestMessage != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _chestMessage!,
                style: TextStyle(
                  color: _chestMessage!.startsWith('+')
                      ? const Color(0xFF2DE2A6)
                      : const Color(0xFFFFC857),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFFC857).withOpacity(unlocked ? 0.22 : 0.10),
                  const Color(0xFF2DE2A6).withOpacity(unlocked ? 0.14 : 0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: unlocked
                    ? const Color(0xFFFFC857).withOpacity(0.45)
                    : Colors.white.withOpacity(0.08),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      _chestClaimed
                          ? Icons.check_circle_rounded
                          : unlocked
                              ? Icons.lock_open_rounded
                              : Icons.lock_clock_rounded,
                      color: unlocked
                          ? const Color(0xFFFFC857)
                          : Colors.white.withOpacity(0.55),
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _chestClaimed
                            ? 'Coffre réclamé'
                            : unlocked
                                ? 'Coffre prêt à réclamer'
                                : 'Progression du coffre',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Text(
                      '$current/$_chestTarget',
                      style: TextStyle(
                        color: unlocked
                            ? const Color(0xFFFFC857)
                            : Colors.white.withOpacity(0.7),
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(50),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 11,
                    backgroundColor: Colors.white.withOpacity(0.09),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFFFFC857),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: canClaim && !_claimLoading
                        ? _claimDailyChest
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC857),
                      disabledBackgroundColor: _chestClaimed
                          ? const Color(0xFF2DE2A6).withOpacity(0.18)
                          : Colors.white.withOpacity(0.07),
                      foregroundColor: const Color(0xFF181100),
                      disabledForegroundColor: _chestClaimed
                          ? const Color(0xFF2DE2A6)
                          : Colors.white.withOpacity(0.42),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _claimLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.3,
                              color: Color(0xFFFFC857),
                            ),
                          )
                        : Text(
                            buttonText,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
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

  Widget _buildDailyMissions(_LevelData levelData) {
    return _SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            title: 'Missions du jour',
            subtitle: 'Synchronisées avec le serveur',
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
            title: 'Faire $_chestTarget sessions',
            subtitle: 'Débloque le coffre quotidien',
            current: min(_todayMines, _chestTarget),
            target: _chestTarget,
            tag: '+$_chestReward pts',
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

  Widget _buildWithdrawGoal() {
    final progress = (_points / _withdrawTarget).clamp(0.0, 1.0).toDouble();
    final remaining = max(_withdrawTarget - _points, 0);

    return _SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            title: 'Objectif de retrait',
            subtitle: 'Simulation pour donner un but clair à l’utilisateur',
            icon: Icons.account_balance_wallet_rounded,
            color: const Color(0xFF55D6FF),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                'Progression',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Text(
                '$_points / $_withdrawTarget',
                style: const TextStyle(
                  color: Color(0xFF55D6FF),
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(50),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: Colors.white.withOpacity(0.08),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF55D6FF),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            remaining > 0
                ? 'Encore $remaining points avant le premier objectif de retrait.'
                : 'Objectif atteint. Le retrait réel sera activé plus tard côté serveur.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.58),
              fontSize: 13,
              height: 1.35,
            ),
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
                        icon: entry.type == 'daily_chest'
                            ? Icons.card_giftcard_rounded
                            : Icons.bolt_rounded,
                        color: entry.type == 'daily_chest'
                            ? const Color(0xFFFFC857)
                            : const Color(0xFF2DE2A6),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.description.isNotEmpty
                                  ? entry.description
                                  : entry.dateLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              entry.dateLabel,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.55),
                                fontSize: 12,
                              ),
                            ),
                          ],
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
    final progress = (_points / _withdrawTarget).clamp(0.0, 1.0).toDouble();
    final remaining = max(_withdrawTarget - _points, 0);

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
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Text(
                      'Objectif retrait',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${(progress * 100).floor()}%',
                      style: const TextStyle(
                        color: Color(0xFF55D6FF),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(50),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 11,
                    backgroundColor: Colors.white.withOpacity(0.08),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF55D6FF),
                    ),
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
                    'Encore $remaining points avant l’objectif de retrait simulé. Plus tard, on ajoutera le wallet crypto et la validation côté serveur.',
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
                _ProfileLine(
                  label: 'Objectif coffre',
                  value: '${min(_todayMines, _chestTarget)}/$_chestTarget',
                ),
                _ProfileLine(
                  label: 'Coffre réclamé',
                  value: _chestClaimed ? 'Oui' : 'Non',
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
    Color color = const Color(0xFF2DE2A6),
  }) {
    return Row(
      children: [
        _IconBubble(
          icon: icon,
          color: color,
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
        color: completed
            ? const Color(0xFF2DE2A6).withOpacity(0.07)
            : Colors.white.withOpacity(0.045),
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
                        completed ? 'terminé' : tag,
                        style: TextStyle(
                          color: completed
                              ? const Color(0xFF2DE2A6)
                              : Colors.white.withOpacity(0.62),
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
  final String type;
  final String description;

  const _HistoryEntry({
    required this.reward,
    required this.rawDate,
    required this.type,
    required this.description,
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
      type: (json['type'] ?? 'mine').toString(),
      description: (json['description'] ?? '').toString(),
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