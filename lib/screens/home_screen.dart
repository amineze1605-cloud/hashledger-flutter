// ==================== PARTIE 1/8 ====================

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
  static const String _baseUrl =
      'https://hashledger-backend.vercel.app';

  static const int _withdrawTarget = 10000;
  static const int _dailyPointsTarget = 30;

  static const List<int> _wheelRewards = [
    5,
    10,
    15,
    20,
    25,
    50,
  ];

  int _selectedIndex = 0;
  late int _points;

  bool _miningLoading = false;
  bool _claimLoading = false;
  bool _dailyStatusLoading = false;
  bool _wheelLoading = false;

  int _cooldownLeft = 0;
  Timer? _cooldownTimer;

  int _todayMines = 0;
  int _todayPointsEarned = 0;
  int _loginStreak = 1;

  bool _historySeenToday = false;

  int _chestTarget = 3;
  int _chestReward = 25;

  bool _chestClaimed = false;
  bool _canClaimChest = false;

  bool _wheelAvailable = true;
  bool _wheelSpun = false;
  int? _wheelReward;
  DateTime? _nextWheelAt;

  bool _historyLoading = false;
  String? _historyError;

  List<_HistoryEntry> _history = [];

  String? _message;
  String? _chestMessage;
  String? _wheelMessage;

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
    return widget.user.email
        .toLowerCase()
        .replaceAll(
          RegExp(r'[^a-z0-9]'),
          '_',
        );
  }

  String get _todayKey {
    final now = DateTime.now();

    return '${now.year}-${now.month}-${now.day}';
  }

  String get _yesterdayKey {
    final yesterday = DateTime.now().subtract(
      const Duration(days: 1),
    );

    return '${yesterday.year}-${yesterday.month}-${yesterday.day}';
  }

  Future<void> _loadLocalProgress() async {
    final prefs = await SharedPreferences.getInstance();

    final lastOpenKey =
        'hl_${_emailKey}_last_open';

    final streakKey =
        'hl_${_emailKey}_login_streak';

    final minesKey =
        'hl_${_emailKey}_mines_$_todayKey';

    final pointsTodayKey =
        'hl_${_emailKey}_points_$_todayKey';

    final historyKey =
        'hl_${_emailKey}_history_seen_$_todayKey';

    final lastOpen =
        prefs.getString(lastOpenKey);

    int streak =
        prefs.getInt(streakKey) ?? 0;

    if (lastOpen != _todayKey) {
      if (lastOpen == _yesterdayKey) {
        streak += 1;
      } else {
        streak = 1;
      }

      await prefs.setString(
        lastOpenKey,
        _todayKey,
      );

      await prefs.setInt(
        streakKey,
        streak,
      );
    }

    if (!mounted) return;

    setState(() {
      _loginStreak =
          streak <= 0 ? 1 : streak;

      _todayMines =
          prefs.getInt(minesKey) ?? 0;

      _todayPointsEarned =
          prefs.getInt(pointsTodayKey) ?? 0;

      _historySeenToday =
          prefs.getBool(historyKey) ?? false;
    });
  }

  Future<void> _saveTodayMines() async {
    final prefs =
        await SharedPreferences.getInstance();

    await prefs.setInt(
      'hl_${_emailKey}_mines_$_todayKey',
      _todayMines,
    );
  }

  Future<void> _saveTodayPoints() async {
    final prefs =
        await SharedPreferences.getInstance();

    await prefs.setInt(
      'hl_${_emailKey}_points_$_todayKey',
      _todayPointsEarned,
    );
  }

  Future<void> _markHistorySeen() async {
    final prefs =
        await SharedPreferences.getInstance();

    await prefs.setBool(
      'hl_${_emailKey}_history_seen_$_todayKey',
      true,
    );

    if (!mounted) return;

    setState(() {
      _historySeenToday = true;
    });
  }

  _LevelData _calculateLevel(
    int totalPoints,
  ) {
    int level = 1;

    int remainingXp = max(
      totalPoints,
      0,
    );

    int neededXp = 300;

    while (remainingXp >= neededXp) {
      remainingXp -= neededXp;
      level += 1;

      neededXp =
          300 + ((level - 1) * 150);
    }

    return _LevelData(
      level: level,
      currentXp: remainingXp,
      neededXp: neededXp,
    );
  }

  _LeagueData _calculateLeague(
    int totalPoints,
  ) {
    if (totalPoints < 1000) {
      return const _LeagueData(
        name: 'Bronze',
        nextName: 'Argent',
        minimum: 0,
        target: 1000,
        icon: Icons.shield_rounded,
        color: Color(0xFFCD8A52),
      );
    }

    if (totalPoints < 5000) {
      return const _LeagueData(
        name: 'Argent',
        nextName: 'Or',
        minimum: 1000,
        target: 5000,
        icon: Icons.shield_rounded,
        color: Color(0xFFC9D2DC),
      );
    }

    if (totalPoints < 15000) {
      return const _LeagueData(
        name: 'Or',
        nextName: 'Diamant',
        minimum: 5000,
        target: 15000,
        icon: Icons.workspace_premium_rounded,
        color: Color(0xFFFFC857),
      );
    }

    return const _LeagueData(
      name: 'Diamant',
      nextName: 'Maître',
      minimum: 15000,
      target: 30000,
      icon: Icons.diamond_rounded,
      color: Color(0xFF55D6FF),
    );
  }

  int _achievementCount(
    _LevelData levelData,
  ) {
    int count = 0;

    if (_points >= 10) {
      count += 1;
    }

    if (_points >= 100) {
      count += 1;
    }

    if (_chestClaimed) {
      count += 1;
    }

    if (levelData.level >= 2) {
      count += 1;
    }

    if (_loginStreak >= 7) {
      count += 1;
    }

    return count;
  }

  String _motivationText(
    _LevelData levelData,
  ) {
    if (_wheelAvailable) {
      return 'Ton tour gratuit est disponible dans la roue quotidienne.';
    }

    if (_chestClaimed) {
      return 'Coffre réclamé. Continue à gagner des points pour progresser.';
    }

    if (_canClaimChest) {
      return 'Ton coffre est débloqué. Réclame maintenant $_chestReward points.';
    }

    if (_todayMines <= 0) {
      return 'Lance ta première session pour activer les missions du jour.';
    }

    if (_todayMines < _chestTarget) {
      final remaining =
          _chestTarget - _todayMines;

      return 'Encore $remaining session${remaining > 1 ? 's' : ''} pour débloquer le coffre.';
    }

    if (_todayPointsEarned <
        _dailyPointsTarget) {
      final remaining =
          _dailyPointsTarget -
          _todayPointsEarned;

      return 'Encore $remaining points pour terminer ta mission quotidienne.';
    }

    if (levelData.xpToNext <= 100) {
      return 'Plus que ${levelData.xpToNext} XP avant le niveau ${levelData.level + 1}.';
    }

    return 'Tes objectifs avancent bien. Garde ta série active demain.';
  }

  String _wheelSubtitle() {
    if (_wheelLoading) {
      return 'Connexion au serveur...';
    }

    if (_wheelAvailable) {
      return 'Ton tour gratuit est disponible';
    }

    if (_wheelReward != null) {
      return 'Gain du jour : +$_wheelReward points';
    }

    return 'Déjà utilisée aujourd’hui';
  }

  String _wheelBadge() {
    if (_wheelLoading) {
      return '...';
    }

    return _wheelAvailable
        ? 'JOUER'
        : 'JOUÉ';
  }

  void _showMessage(
    String message, {
    Color color = const Color(0xFF111827),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showComingSoon(
    String feature,
  ) {
    _showMessage(
      '$feature sera bientôt disponible.',
    );
  }

  void _goToTab(
    int index,
  ) {
    setState(() {
      _selectedIndex = index;
    });

    if (index == 1) {
      _markHistorySeen();
      _loadHistory();
    }

    if (index == 0 ||
        index == 2 ||
        index == 3) {
      _loadDailyStatus(
        silent: true,
      );
    }
  }

  Future<void> _loadDailyStatus({
    bool silent = false,
  }) async {
    if (!silent && mounted) {
      setState(() {
        _dailyStatusLoading = true;
        _chestMessage = null;
        _wheelMessage = null;
      });
    }

    try {
      final response = await http.get(
        Uri.parse(
          '$_baseUrl/daily-status',
        ),
        headers: {
          'Content-Type':
              'application/json',
          'Authorization':
              'Bearer ${widget.user.token}',
        },
      );

      final dynamic decoded =
          response.body.isNotEmpty
              ? jsonDecode(response.body)
              : <String, dynamic>{};

      final data =
          decoded is Map<String, dynamic>
              ? decoded
              : <String, dynamic>{};

      if (response.statusCode >= 200 &&
          response.statusCode < 300) {
        final sessionsToday =
            _asInt(
                  data['sessions_today'],
                ) ??
                _todayMines;

        final chestTarget =
            _asInt(
                  data['chest_target'],
                ) ??
                _chestTarget;

        final chestReward =
            _asInt(
                  data['chest_reward'],
                ) ??
                _chestReward;

        final todayPointsEarned =
            _asInt(
                  data['today_points_earned'],
                ) ??
                _todayPointsEarned;

        final points =
            _asInt(
                  data['points'],
                ) ??
                _points;

        final chestClaimed =
            data['chest_claimed'] == true;

        final canClaim =
            data['can_claim'] == true;

        final wheelAvailable =
            data['wheel_available'] == true;

        final wheelSpun =
            data['wheel_spun'] == true;

        final wheelReward =
            _asInt(
              data['wheel_reward'],
            );

        DateTime? nextWheelAt;

        final rawNextWheel =
            data['next_wheel_at']?.toString();

        if (rawNextWheel != null &&
            rawNextWheel.isNotEmpty) {
          nextWheelAt =
              DateTime.tryParse(rawNextWheel)
                  ?.toLocal();
        }

        _todayMines = sessionsToday;
        _todayPointsEarned =
            todayPointsEarned;

        await _saveTodayMines();
        await _saveTodayPoints();

        if (!mounted) return;

        setState(() {
          _points = points;

          _todayMines =
              sessionsToday;

          _todayPointsEarned =
              todayPointsEarned;

          _chestTarget =
              chestTarget;

          _chestReward =
              chestReward;

          _chestClaimed =
              chestClaimed;

          _canClaimChest =
              canClaim;

          _wheelAvailable =
              wheelAvailable;

          _wheelSpun =
              wheelSpun;

          _wheelReward =
              wheelReward;

          _nextWheelAt =
              nextWheelAt;
        });
      } else {
        if (!mounted || silent) return;

        setState(() {
          _chestMessage =
              data['error']?.toString() ??
              'Impossible de charger les données quotidiennes.';
        });
      }
    } catch (_) {
      if (!mounted || silent) return;

      setState(() {
        _chestMessage =
            'Erreur de connexion avec le serveur.';
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

// ================= FIN PARTIE 1/8 ====================
// ==================== PARTIE 2/8 ====================

  Future<void> _openDailyWheel() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false, 
      builder: (_) {
        return _DailyWheelDialog(
          rewards: _wheelRewards,
          available: _wheelAvailable,
          previousReward: _wheelReward,
          nextAvailableAt: _nextWheelAt,
          onSpin: _spinDailyWheel,
        );
      },
    );
  }

  Future<_WheelSpinOutcome> _spinDailyWheel() async {
    if (_wheelLoading) {
      return const _WheelSpinOutcome(
        success: false,
        message: 'La roue est déjà en cours.',
      );
    }

    if (!_wheelAvailable) {
      return _WheelSpinOutcome(
        success: false,
        reward: _wheelReward,
        message: _wheelReward != null
            ? 'Roue déjà utilisée aujourd’hui : +$_wheelReward points.'
            : 'La roue a déjà été utilisée aujourd’hui.',
      );
    }

    setState(() {
      _wheelLoading = true;
      _wheelMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse(
          '$_baseUrl/spin-daily-wheel',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.user.token}',
        },
      );

      final dynamic decoded =
          response.body.isNotEmpty
              ? jsonDecode(response.body)
              : <String, dynamic>{};

      final data =
          decoded is Map<String, dynamic>
              ? decoded
              : <String, dynamic>{};

      if (response.statusCode >= 200 &&
          response.statusCode < 300) {
        final reward =
            _asInt(
                  data['reward'],
                ) ??
                0;

        final newTotal =
            _asInt(
                  data['new_total'],
                ) ??
                (_points + reward);

        final todayPointsEarned =
            _asInt(
                  data['today_points_earned'],
                ) ??
                (_todayPointsEarned + reward);

        DateTime? nextWheelAt;

        final rawNextWheel =
            data['next_wheel_at']?.toString();

        if (rawNextWheel != null &&
            rawNextWheel.isNotEmpty) {
          nextWheelAt =
              DateTime.tryParse(
                rawNextWheel,
              )?.toLocal();
        }

        _todayPointsEarned =
            todayPointsEarned;

        await _saveTodayPoints();

        if (!mounted) {
          return _WheelSpinOutcome(
            success: true,
            reward: reward,
            message: '+$reward points',
          );
        }

        setState(() {
          _points = newTotal;

          _todayPointsEarned =
              todayPointsEarned;

          _wheelAvailable = false;
          _wheelSpun = true;
          _wheelReward = reward;
          _nextWheelAt = nextWheelAt;

          _wheelMessage =
              '+$reward points gagnés avec la roue';
        });

        await _loadHistory();

        return _WheelSpinOutcome(
          success: true,
          reward: reward,
          message:
              'Félicitations, tu as gagné $reward points.',
        );
      }

      final errorMessage =
          data['error']?.toString() ??
          'Impossible de lancer la roue.';

      if (response.statusCode == 409) {
        final previousReward =
            _asInt(
              data['reward'],
            );

        DateTime? nextWheelAt;

        final rawNextWheel =
            data['next_wheel_at']?.toString();

        if (rawNextWheel != null &&
            rawNextWheel.isNotEmpty) {
          nextWheelAt =
              DateTime.tryParse(
                rawNextWheel,
              )?.toLocal();
        }

        if (mounted) {
          setState(() {
            _wheelAvailable = false;
            _wheelSpun = true;

            if (previousReward != null) {
              _wheelReward =
                  previousReward;
            }

            _nextWheelAt =
                nextWheelAt;

            _wheelMessage =
                errorMessage;
          });
        }

        return _WheelSpinOutcome(
          success: false,
          reward:
              previousReward ??
              _wheelReward,
          message:
              previousReward != null
                  ? 'Roue déjà utilisée : +$previousReward points.'
                  : errorMessage,
        );
      }

      if (mounted) {
        setState(() {
          _wheelMessage =
              errorMessage;
        });
      }

      return _WheelSpinOutcome(
        success: false,
        message: errorMessage,
      );
    } catch (_) {
      const errorMessage =
          'Erreur de connexion avec la roue.';

      if (mounted) {
        setState(() {
          _wheelMessage =
              errorMessage;
        });
      }

      return const _WheelSpinOutcome(
        success: false,
        message: errorMessage,
      );
    } finally {
      if (mounted) {
        setState(() {
          _wheelLoading = false;
        });
      }
    }
  }

  Future<void> _claimDailyChest() async {
    if (_claimLoading ||
        !_canClaimChest ||
        _chestClaimed) {
      return;
    }

    setState(() {
      _claimLoading = true;
      _chestMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse(
          '$_baseUrl/claim-daily-chest',
        ),
        headers: {
          'Content-Type':
              'application/json',
          'Authorization':
              'Bearer ${widget.user.token}',
        },
      );

      final dynamic decoded =
          response.body.isNotEmpty
              ? jsonDecode(response.body)
              : <String, dynamic>{};

      final data =
          decoded is Map<String, dynamic>
              ? decoded
              : <String, dynamic>{};

      if (response.statusCode >= 200 &&
          response.statusCode < 300) {
        final reward =
            _asInt(
                  data['reward'],
                ) ??
                _chestReward;

        final newTotal =
            _asInt(
                  data['new_total'],
                ) ??
                (_points + reward);

        final todayPointsEarned =
            _asInt(
                  data['today_points_earned'],
                ) ??
                (_todayPointsEarned + reward);

        _todayPointsEarned =
            todayPointsEarned;

        await _saveTodayPoints();

        if (!mounted) return;

        setState(() {
          _points = newTotal;

          _todayPointsEarned =
              todayPointsEarned;

          _chestClaimed = true;
          _canClaimChest = false;

          _chestMessage =
              '+$reward points ajoutés';

          _message =
              '+$reward points coffre ajoutés';
        });

        await _loadDailyStatus(
          silent: true,
        );

        await _loadHistory();
      } else {
        if (!mounted) return;

        final error =
            data['error']?.toString();

        final details =
            data['details']?.toString();

        final mainError =
            error ?? 'Erreur serveur';

        setState(() {
          _chestMessage =
              details != null &&
                      details.isNotEmpty
                  ? '$mainError : $details'
                  : mainError;

          if (response.statusCode == 409) {
            _chestClaimed = true;
            _canClaimChest = false;
          }
        });

        await _loadDailyStatus(
          silent: true,
        );
      }
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _chestMessage =
            'Erreur de connexion avec le serveur.';
      });
    } finally {
      if (!mounted) return;

      setState(() {
        _claimLoading = false;
      });
    }
  }

  Future<void> _mine() async {
    if (_miningLoading ||
        _cooldownLeft > 0) {
      return;
    }

    setState(() {
      _miningLoading = true;
      _message = null;
    });

    try {
      final response = await http.post(
        Uri.parse(
          '$_baseUrl/mine',
        ),
        headers: {
          'Content-Type':
              'application/json',
          'Authorization':
              'Bearer ${widget.user.token}',
        },
      );

      final dynamic decoded =
          response.body.isNotEmpty
              ? jsonDecode(response.body)
              : <String, dynamic>{};

      final data =
          decoded is Map<String, dynamic>
              ? decoded
              : <String, dynamic>{};

      if (response.statusCode >= 200 &&
          response.statusCode < 300) {
        final reward =
            _asInt(
                  data['reward'],
                ) ??
                0;

        final newTotal =
            _asInt(
                  data['new_total'],
                ) ??
                _asInt(
                  data['newTotal'],
                ) ??
                _asInt(
                  data['points'],
                ) ??
                (_points + reward);

        final sessionsToday =
            _asInt(
                  data['sessions_today'],
                ) ??
                _asInt(
                  data['daily_used'],
                ) ??
                (_todayMines + 1);

        final todayPointsEarned =
            _asInt(
                  data['today_points_earned'],
                ) ??
                (_todayPointsEarned + reward);

        final cooldown =
            _asInt(
                  data['cooldown_seconds'],
                ) ??
                _asInt(
                  data['cooldownSeconds'],
                ) ??
                30;

        _todayMines =
            sessionsToday;

        _todayPointsEarned =
            todayPointsEarned;

        await _saveTodayMines();
        await _saveTodayPoints();

        if (!mounted) return;

        setState(() {
          _points =
              newTotal;

          _todayMines =
              sessionsToday;

          _todayPointsEarned =
              todayPointsEarned;

          _canClaimChest =
              _todayMines >=
                  _chestTarget &&
              !_chestClaimed;

          _message =
              reward > 0
                  ? '+$reward points ajoutés'
                  : 'Session validée';
        });

        _startCooldown(
          cooldown,
        );

        await _loadDailyStatus(
          silent: true,
        );
      } else {
        final backendMessage =
            data['message'] ??
            data['error'];

        final cooldown =
            _asInt(
                  data['cooldown_seconds'],
                ) ??
                _asInt(
                  data['cooldownSeconds'],
                ) ??
                _asInt(
                  data['remaining_seconds'],
                );

        if (cooldown != null &&
            cooldown > 0) {
          _startCooldown(
            cooldown,
          );
        }

        if (!mounted) return;

        setState(() {
          _message =
              backendMessage?.toString() ??
              'Impossible de miner pour le moment.';
        });

        await _loadDailyStatus(
          silent: true,
        );
      }
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _message =
            'Erreur de connexion avec le serveur.';
      });
    } finally {
      if (!mounted) return;

      setState(() {
        _miningLoading = false;
      });
    }
  }

  void _startCooldown(
    int seconds,
  ) {
    _cooldownTimer?.cancel();

    setState(() {
      _cooldownLeft = max(
        seconds,
        0,
      );
    });

    _cooldownTimer = Timer.periodic(
      const Duration(
        seconds: 1,
      ),
      (timer) {
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
      },
    );
  }

// ================= FIN PARTIE 2/8 ====================
// ==================== PARTIE 3/8 ====================

  Future<void> _loadHistory() async {
    if (!mounted) return;

    setState(() {
      _historyLoading = true;
      _historyError = null;
    });

    try {
      final response = await http.get(
        Uri.parse(
          '$_baseUrl/mining-history',
        ),
        headers: {
          'Content-Type':
              'application/json',
          'Authorization':
              'Bearer ${widget.user.token}',
        },
      );

      final dynamic decoded =
          response.body.isNotEmpty
              ? jsonDecode(response.body)
              : <String, dynamic>{};

      if (response.statusCode >= 200 &&
          response.statusCode < 300) {
        dynamic rawList;

        if (decoded is List) {
          rawList = decoded;
        } else if (
            decoded is Map<String, dynamic>) {
          rawList =
              decoded['history'] ??
              decoded['logs'] ??
              decoded['mining_history'] ??
              decoded['data'] ??
              [];
        } else {
          rawList = [];
        }

        final entries =
            <_HistoryEntry>[];

        if (rawList is List) {
          for (final item in rawList) {
            if (item
                is Map<String, dynamic>) {
              entries.add(
                _HistoryEntry.fromJson(
                  item,
                ),
              );
            } else if (item is Map) {
              entries.add(
                _HistoryEntry.fromJson(
                  Map<String, dynamic>.from(
                    item,
                  ),
                ),
              );
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
          _historyError =
              'Impossible de charger l’historique.';
        });
      }
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _historyError =
            'Erreur de connexion avec le serveur.';
      });
    } finally {
      if (!mounted) return;

      setState(() {
        _historyLoading = false;
      });
    }
  }

  void _onNavTap(
    int index,
  ) {
    _goToTab(
      index,
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final pages = [
      _buildHomePage(),
      _buildHistoryPage(),
      _buildWithdrawPage(),
      _buildProfilePage(),
    ];

    return Scaffold(
      backgroundColor:
          const Color(0xFF05070C),
      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: pages,
        ),
      ),
      bottomNavigationBar:
          _buildBottomNav(),
    );
  }

  Widget _buildHomePage() {
    final levelData =
        _calculateLevel(
      _points,
    );

    final leagueData =
        _calculateLeague(
      _points,
    );

    return Container(
      decoration:
          const BoxDecoration(
        gradient: LinearGradient(
          begin:
              Alignment.topCenter,
          end:
              Alignment.bottomCenter,
          colors: [
            Color(0xFF0A1020),
            Color(0xFF05070C),
          ],
        ),
      ),
      child: RefreshIndicator(
        color:
            const Color(0xFF2DE2A6),
        backgroundColor:
            const Color(0xFF111827),
        onRefresh: () async {
          await _loadDailyStatus();
        },
        child: ListView(
          physics:
              const AlwaysScrollableScrollPhysics(),
          padding:
              const EdgeInsets.fromLTRB(
            16,
            16,
            16,
            26,
          ),
          children: [
            _buildCompactHeader(
              levelData,
              leagueData,
            ),
            const SizedBox(
              height: 12,
            ),
            _buildMotivationBanner(
              levelData,
            ),
            const SizedBox(
              height: 12,
            ),
            _buildMiningCard(),
            const SizedBox(
              height: 12,
            ),
            _buildDailyChest(),
            const SizedBox(
              height: 12,
            ),
            _buildDailyMissions(
              levelData,
            ),
            const SizedBox(
              height: 12,
            ),
            _buildGameZone(
              levelData,
              leagueData,
            ),
            const SizedBox(
              height: 12,
            ),
            _buildWithdrawGoal(),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactHeader(
    _LevelData levelData,
    _LeagueData leagueData,
  ) {
    return Container(
      padding:
          const EdgeInsets.all(
        16,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(
              0xFF151D31,
            ),
            leagueData.color.withOpacity(
              0.10,
            ),
          ],
        ),
        borderRadius:
            BorderRadius.circular(
          24,
        ),
        border: Border.all(
          color: leagueData.color
              .withOpacity(
            0.30,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withOpacity(
              0.24,
            ),
            blurRadius: 22,
            offset:
                const Offset(
              0,
              12,
            ),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration:
                    BoxDecoration(
                  gradient:
                      const LinearGradient(
                    colors: [
                      Color(
                        0xFF2DE2A6,
                      ),
                      Color(
                        0xFF55D6FF,
                      ),
                    ],
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    17,
                  ),
                ),
                child:
                    const Icon(
                  Icons.hexagon_rounded,
                  color: Color(
                    0xFF04110D,
                  ),
                  size: 28,
                ),
              ),
              const SizedBox(
                width: 12,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    const Text(
                      'HashLedger',
                      style: TextStyle(
                        color:
                            Colors.white,
                        fontSize: 23,
                        fontWeight:
                            FontWeight
                                .w900,
                        letterSpacing:
                            -0.6,
                      ),
                    ),
                    const SizedBox(
                      height: 3,
                    ),
                    Text(
                      widget.user.email,
                      maxLines: 1,
                      overflow:
                          TextOverflow
                              .ellipsis,
                      style: TextStyle(
                        color: Colors
                            .white
                            .withOpacity(
                          0.48,
                        ),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets
                        .symmetric(
                  horizontal: 11,
                  vertical: 8,
                ),
                decoration:
                    BoxDecoration(
                  color: leagueData
                      .color
                      .withOpacity(
                    0.12,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    16,
                  ),
                  border: Border.all(
                    color: leagueData
                        .color
                        .withOpacity(
                      0.32,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisSize:
                      MainAxisSize.min,
                  children: [
                    Icon(
                      leagueData.icon,
                      color:
                          leagueData.color,
                      size: 17,
                    ),
                    const SizedBox(
                      width: 5,
                    ),
                    Text(
                      leagueData.name,
                      style: TextStyle(
                        color:
                            leagueData.color,
                        fontWeight:
                            FontWeight
                                .w900,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 16,
          ),

          Row(
            children: [
              Expanded(
                child: _HeaderStat(
                  icon:
                      Icons.toll_rounded,
                  label: 'Solde',
                  value:
                      '$_points pts',
                  color:
                      const Color(
                    0xFF2DE2A6,
                  ),
                ),
              ),
              const SizedBox(
                width: 8,
              ),
              Expanded(
                child: _HeaderStat(
                  icon: Icons
                      .workspace_premium_rounded,
                  label: 'Niveau',
                  value:
                      '${levelData.level}',
                  color:
                      const Color(
                    0xFFFFC857,
                  ),
                ),
              ),
              const SizedBox(
                width: 8,
              ),
              Expanded(
                child: _HeaderStat(
                  icon: Icons
                      .local_fire_department_rounded,
                  label: 'Série',
                  value:
                      '$_loginStreak j',
                  color:
                      const Color(
                    0xFFFF7B54,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 14,
          ),

          Row(
            children: [
              Text(
                'Niveau ${levelData.level}',
                style: TextStyle(
                  color: Colors.white
                      .withOpacity(
                    0.72,
                  ),
                  fontWeight:
                      FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Text(
                '${levelData.currentXp}/${levelData.neededXp} XP',
                style:
                    const TextStyle(
                  color: Color(
                    0xFF2DE2A6,
                  ),
                  fontWeight:
                      FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 8,
          ),

          ClipRRect(
            borderRadius:
                BorderRadius.circular(
              50,
            ),
            child:
                LinearProgressIndicator(
              value:
                  levelData.progress,
              minHeight: 8,
              backgroundColor:
                  Colors.white
                      .withOpacity(
                0.08,
              ),
              valueColor:
                  const AlwaysStoppedAnimation<
                      Color>(
                Color(
                  0xFF2DE2A6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMotivationBanner(
    _LevelData levelData,
  ) {
    final wheelReady =
        _wheelAvailable;

    final chestReady =
        _canClaimChest ||
        _chestClaimed;

    final Color bannerColor;

    final IconData bannerIcon;

    if (wheelReady) {
      bannerColor =
          const Color(
        0xFFFF7B54,
      );

      bannerIcon =
          Icons.casino_rounded;
    } else if (chestReady) {
      bannerColor =
          const Color(
        0xFFFFC857,
      );

      bannerIcon =
          Icons.card_giftcard_rounded;
    } else {
      bannerColor =
          const Color(
        0xFF9D8AFF,
      );

      bannerIcon =
          Icons.auto_awesome_rounded;
    }

    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: bannerColor
            .withOpacity(
          0.09,
        ),
        borderRadius:
            BorderRadius.circular(
          18,
        ),
        border: Border.all(
          color: bannerColor
              .withOpacity(
            0.26,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            bannerIcon,
            color: bannerColor,
            size: 22,
          ),
          const SizedBox(
            width: 10,
          ),
          Expanded(
            child: Text(
              _motivationText(
                levelData,
              ),
              style:
                  const TextStyle(
                color: Colors.white,
                fontWeight:
                    FontWeight.w800,
                fontSize: 13,
                height: 1.3,
              ),
            ),
          ),
          if (_wheelAvailable) ...[
            const SizedBox(
              width: 8,
            ),
            InkWell(
              borderRadius:
                  BorderRadius.circular(
                15,
              ),
              onTap:
                  _wheelLoading
                      ? null
                      : _openDailyWheel,
              child: Container(
                padding:
                    const EdgeInsets
                        .symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration:
                    BoxDecoration(
                  color: bannerColor
                      .withOpacity(
                    0.13,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    15,
                  ),
                ),
                child: const Text(
                  'JOUER',
                  style: TextStyle(
                    color: Color(
                      0xFFFF7B54,
                    ),
                    fontSize: 9.5,
                    fontWeight:
                        FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

// ================= FIN PARTIE 3/8 ====================
// ==================== PARTIE 4/8 ====================

  Widget _buildMiningCard() {
    final canMine =
        !_miningLoading &&
        _cooldownLeft <= 0;

    return _SoftCard(
      padding: const EdgeInsets.all(
        15,
      ),
      child: Column(
        children: [
          Row(
            children: [
              _IconBubble(
                icon: Icons.bolt_rounded,
                color: const Color(
                  0xFF7C5CFF,
                ),
              ),
              const SizedBox(
                width: 11,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Minage',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight:
                            FontWeight.w900,
                      ),
                    ),
                    const SizedBox(
                      height: 3,
                    ),
                    Text(
                      _cooldownLeft > 0
                          ? 'Disponible dans $_cooldownLeft secondes'
                          : 'Une session rapporte des points',
                      style: TextStyle(
                        color: Colors.white
                            .withOpacity(
                          0.52,
                        ),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: canMine
                      ? const Color(
                          0xFF2DE2A6,
                        ).withOpacity(
                          0.10,
                        )
                      : Colors.white
                          .withOpacity(
                          0.05,
                        ),
                  borderRadius:
                      BorderRadius.circular(
                    20,
                  ),
                ),
                child: Text(
                  canMine
                      ? 'PRÊT'
                      : 'PAUSE',
                  style: TextStyle(
                    color: canMine
                        ? const Color(
                            0xFF2DE2A6,
                          )
                        : Colors.white
                            .withOpacity(
                            0.45,
                          ),
                    fontWeight:
                        FontWeight.w900,
                    fontSize: 10,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
            ],
          ),

          if (_message != null) ...[
            const SizedBox(
              height: 12,
            ),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: Colors.white
                    .withOpacity(
                  0.05,
                ),
                borderRadius:
                    BorderRadius.circular(
                  13,
                ),
              ),
              child: Text(
                _message!,
                style: const TextStyle(
                  color: Color(
                    0xFF2DE2A6,
                  ),
                  fontWeight:
                      FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ],

          const SizedBox(
            height: 13,
          ),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed:
                  canMine ? _mine : null,
              icon: _miningLoading
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child:
                          CircularProgressIndicator(
                        strokeWidth: 2.3,
                        color: Color(
                          0xFF04110D,
                        ),
                      ),
                    )
                  : const Icon(
                      Icons.bolt_rounded,
                      size: 22,
                    ),
              label: Text(
                _cooldownLeft > 0
                    ? 'Cooldown $_cooldownLeft s'
                    : 'Miner maintenant',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight:
                      FontWeight.w900,
                ),
              ),
              style:
                  ElevatedButton.styleFrom(
                backgroundColor:
                    const Color(
                  0xFF2DE2A6,
                ),
                disabledBackgroundColor:
                    Colors.white.withOpacity(
                  0.07,
                ),
                foregroundColor:
                    const Color(
                  0xFF04110D,
                ),
                disabledForegroundColor:
                    Colors.white.withOpacity(
                  0.38,
                ),
                elevation: 0,
                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(
                    16,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyChest() {
    final current = min(
      _todayMines,
      _chestTarget,
    );

    final progress =
        _chestTarget <= 0
            ? 0.0
            : (current / _chestTarget)
                .clamp(
                  0.0,
                  1.0,
                )
                .toDouble();

    final unlocked =
        _todayMines >=
        _chestTarget;

    final canClaim =
        _canClaimChest &&
        !_chestClaimed;

    String statusText;

    if (_chestClaimed) {
      statusText = 'Réclamé';
    } else if (canClaim) {
      statusText = 'Disponible';
    } else {
      statusText =
          '$current/$_chestTarget';
    }

    return _SoftCard(
      padding: const EdgeInsets.all(
        15,
      ),
      child: Column(
        children: [
          Row(
            children: [
              _IconBubble(
                icon: _chestClaimed
                    ? Icons
                        .check_circle_rounded
                    : unlocked
                        ? Icons
                            .lock_open_rounded
                        : Icons
                            .card_giftcard_rounded,
                color: const Color(
                  0xFFFFC857,
                ),
              ),
              const SizedBox(
                width: 11,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Coffre quotidien',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight:
                            FontWeight.w900,
                      ),
                    ),
                    const SizedBox(
                      height: 3,
                    ),
                    Text(
                      _chestClaimed
                          ? 'Bonus récupéré aujourd’hui'
                          : unlocked
                              ? '+$_chestReward points disponibles'
                              : '$_chestTarget sessions pour le débloquer',
                      style: TextStyle(
                        color: Colors.white
                            .withOpacity(
                          0.52,
                        ),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(
                    0xFFFFC857,
                  ).withOpacity(
                    0.10,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    20,
                  ),
                ),
                child: Text(
                  statusText,
                  style: const TextStyle(
                    color: Color(
                      0xFFFFC857,
                    ),
                    fontWeight:
                        FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),

          if (_chestMessage !=
              null) ...[
            const SizedBox(
              height: 12,
            ),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: Colors.white
                    .withOpacity(
                  0.05,
                ),
                borderRadius:
                    BorderRadius.circular(
                  13,
                ),
              ),
              child: Text(
                _chestMessage!,
                style: TextStyle(
                  color: _chestMessage!
                          .startsWith(
                        '+',
                      )
                      ? const Color(
                          0xFF2DE2A6,
                        )
                      : const Color(
                          0xFFFFC857,
                        ),
                  fontWeight:
                      FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ],

          const SizedBox(
            height: 13,
          ),

          ClipRRect(
            borderRadius:
                BorderRadius.circular(
              50,
            ),
            child:
                LinearProgressIndicator(
              value: progress,
              minHeight: 9,
              backgroundColor:
                  Colors.white.withOpacity(
                0.08,
              ),
              valueColor:
                  const AlwaysStoppedAnimation<
                      Color>(
                Color(
                  0xFFFFC857,
                ),
              ),
            ),
          ),

          const SizedBox(
            height: 13,
          ),

          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed:
                  canClaim &&
                          !_claimLoading
                      ? _claimDailyChest
                      : null,
              icon: _claimLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child:
                          CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Color(
                          0xFF181100,
                        ),
                      ),
                    )
                  : Icon(
                      _chestClaimed
                          ? Icons
                              .check_rounded
                          : Icons
                              .redeem_rounded,
                      size: 20,
                    ),
              label: Text(
                _claimLoading
                    ? 'Réclamation...'
                    : _chestClaimed
                        ? 'Coffre déjà réclamé'
                        : canClaim
                            ? 'Réclamer +$_chestReward points'
                            : 'Encore ${max(_chestTarget - current, 0)} session${max(_chestTarget - current, 0) > 1 ? 's' : ''}',
                style: const TextStyle(
                  fontWeight:
                      FontWeight.w900,
                  fontSize: 13,
                ),
              ),
              style:
                  ElevatedButton.styleFrom(
                backgroundColor:
                    const Color(
                  0xFFFFC857,
                ),
                disabledBackgroundColor:
                    _chestClaimed
                        ? const Color(
                            0xFF2DE2A6,
                          ).withOpacity(
                            0.10,
                          )
                        : Colors.white
                            .withOpacity(
                            0.06,
                          ),
                foregroundColor:
                    const Color(
                  0xFF181100,
                ),
                disabledForegroundColor:
                    _chestClaimed
                        ? const Color(
                            0xFF2DE2A6,
                          )
                        : Colors.white
                            .withOpacity(
                            0.38,
                          ),
                elevation: 0,
                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(
                    15,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyMissions(
    _LevelData levelData,
  ) {
    final completedMissions = [
      _todayMines >= 1,
      _todayMines >=
          _chestTarget,
      _historySeenToday,
      _todayPointsEarned >=
          _dailyPointsTarget,
    ].where(
      (
        completed,
      ) =>
          completed,
    ).length;

    return _SoftCard(
      padding: const EdgeInsets.all(
        15,
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconBubble(
                icon: Icons
                    .task_alt_rounded,
                color: const Color(
                  0xFF2DE2A6,
                ),
              ),
              const SizedBox(
                width: 11,
              ),
              const Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Missions du jour',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight:
                            FontWeight.w900,
                      ),
                    ),
                    SizedBox(
                      height: 3,
                    ),
                    Text(
                      'Des objectifs rapides à terminer',
                      style: TextStyle(
                        color: Color(
                          0xFF9097A6,
                        ),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$completedMissions/4',
                style: const TextStyle(
                  color: Color(
                    0xFF2DE2A6,
                  ),
                  fontWeight:
                      FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 14,
          ),

          _CompactMissionRow(
            icon: Icons
                .rocket_launch_rounded,
            title: 'Premier minage',
            reward: 'bonus bientôt',
            current: min(
              _todayMines,
              1,
            ),
            target: 1,
            color: const Color(
              0xFF7C5CFF,
            ),
          ),

          const SizedBox(
            height: 8,
          ),

          _CompactMissionRow(
            icon: Icons
                .local_fire_department_rounded,
            title:
                'Coffre quotidien',
            reward:
                '+$_chestReward pts',
            current: min(
              _todayMines,
              _chestTarget,
            ),
            target:
                _chestTarget,
            color: const Color(
              0xFFFFC857,
            ),
          ),

          const SizedBox(
            height: 8,
          ),

          GestureDetector(
            onTap: () {
              _goToTab(
                1,
              );
            },
            child:
                _CompactMissionRow(
              icon:
                  Icons.history_rounded,
              title:
                  'Voir l’historique',
              reward:
                  'mission visuelle',
              current:
                  _historySeenToday
                      ? 1
                      : 0,
              target: 1,
              color: const Color(
                0xFF55D6FF,
              ),
            ),
          ),

          const SizedBox(
            height: 8,
          ),

          _CompactMissionRow(
            icon:
                Icons.stars_rounded,
            title:
                'Gagner $_dailyPointsTarget points',
            reward:
                'mission quotidienne',
            current: min(
              _todayPointsEarned,
              _dailyPointsTarget,
            ),
            target:
                _dailyPointsTarget,
            color: const Color(
              0xFF2DE2A6,
            ),
          ),
        ],
      ),
    );
  }

// ================= FIN PARTIE 4/8 ====================
// ==================== PARTIE 5/8 ====================

  Widget _buildGameZone(
    _LevelData levelData,
    _LeagueData leagueData,
  ) {
    final leagueProgress =
        leagueData.progressFor(
      _points,
    );

    final leagueRemaining =
        leagueData.pointsToNext(
      _points,
    );

    final achievementCount =
        _achievementCount(
      levelData,
    );

    final streakProgress = min(
      _loginStreak,
      7,
    );

    return _SoftCard(
      padding: const EdgeInsets.all(
        15,
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconBubble(
                icon: Icons
                    .sports_esports_rounded,
                color: const Color(
                  0xFF9D8AFF,
                ),
              ),
              const SizedBox(
                width: 11,
              ),
              const Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Zone de jeu',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight:
                            FontWeight.w900,
                      ),
                    ),
                    SizedBox(
                      height: 3,
                    ),
                    Text(
                      'Récompenses et progression',
                      style: TextStyle(
                        color: Color(
                          0xFF9097A6,
                        ),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(
                    0xFF9D8AFF,
                  ).withOpacity(
                    0.10,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    20,
                  ),
                ),
                child: const Text(
                  'JEU',
                  style: TextStyle(
                    color: Color(
                      0xFF9D8AFF,
                    ),
                    fontSize: 10,
                    fontWeight:
                        FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 15,
          ),

          Container(
            padding:
                const EdgeInsets.all(
              14,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  leagueData.color
                      .withOpacity(
                    0.16,
                  ),
                  leagueData.color
                      .withOpacity(
                    0.04,
                  ),
                ],
              ),
              borderRadius:
                  BorderRadius.circular(
                18,
              ),
              border: Border.all(
                color: leagueData.color
                    .withOpacity(
                  0.28,
                ),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      leagueData.icon,
                      color:
                          leagueData.color,
                      size: 27,
                    ),
                    const SizedBox(
                      width: 10,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ligue ${leagueData.name}',
                            style:
                                const TextStyle(
                              color:
                                  Colors.white,
                              fontWeight:
                                  FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(
                            height: 3,
                          ),
                          Text(
                            leagueRemaining > 0
                                ? '$leagueRemaining points avant ${leagueData.nextName}'
                                : 'Niveau de ligue maximal atteint',
                            style: TextStyle(
                              color: Colors.white
                                  .withOpacity(
                                0.52,
                              ),
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '$_points pts',
                      style: TextStyle(
                        color:
                            leagueData.color,
                        fontWeight:
                            FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(
                  height: 12,
                ),
                ClipRRect(
                  borderRadius:
                      BorderRadius.circular(
                    50,
                  ),
                  child:
                      LinearProgressIndicator(
                    value:
                        leagueProgress,
                    minHeight: 8,
                    backgroundColor:
                        Colors.white
                            .withOpacity(
                      0.08,
                    ),
                    valueColor:
                        AlwaysStoppedAnimation<
                            Color>(
                      leagueData.color,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(
            height: 12,
          ),

          if (_wheelMessage != null) ...[
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: const Color(
                  0xFFFF7B54,
                ).withOpacity(
                  0.08,
                ),
                borderRadius:
                    BorderRadius.circular(
                  14,
                ),
                border: Border.all(
                  color: const Color(
                    0xFFFF7B54,
                  ).withOpacity(
                    0.20,
                  ),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.casino_rounded,
                    color: Color(
                      0xFFFF7B54,
                    ),
                    size: 19,
                  ),
                  const SizedBox(
                    width: 9,
                  ),
                  Expanded(
                    child: Text(
                      _wheelMessage!,
                      style:
                          const TextStyle(
                        color:
                            Colors.white,
                        fontWeight:
                            FontWeight.w800,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(
              height: 10,
            ),
          ],

          Row(
            children: [
              Expanded(
                child:
                    _GameFeatureCard(
                  icon:
                      Icons.casino_rounded,
                  title:
                      'Roue quotidienne',
                  subtitle:
                      _wheelSubtitle(),
                  badge:
                      _wheelBadge(),
                  color: const Color(
                    0xFFFF7B54,
                  ),
                  onTap: _wheelLoading
                      ? () {}
                      : _openDailyWheel,
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              Expanded(
                child:
                    _GameFeatureCard(
                  icon: Icons
                      .inventory_2_rounded,
                  title:
                      'Coffre mystère',
                  subtitle:
                      'Récompenses rares',
                  badge:
                      'Bientôt',
                  color: const Color(
                    0xFFFFC857,
                  ),
                  onTap: () {
                    _showComingSoon(
                      'Le coffre mystère',
                    );
                  },
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 12,
          ),

          Container(
            padding:
                const EdgeInsets.all(
              14,
            ),
            decoration: BoxDecoration(
              color: Colors.white
                  .withOpacity(
                0.035,
              ),
              borderRadius:
                  BorderRadius.circular(
                18,
              ),
              border: Border.all(
                color: Colors.white
                    .withOpacity(
                  0.07,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons
                          .local_fire_department_rounded,
                      color: Color(
                        0xFFFF7B54,
                      ),
                      size: 21,
                    ),
                    const SizedBox(
                      width: 8,
                    ),
                    const Expanded(
                      child: Text(
                        'Série de connexion',
                        style: TextStyle(
                          color:
                              Colors.white,
                          fontWeight:
                              FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Text(
                      '$streakProgress/7 jours',
                      style:
                          const TextStyle(
                        color: Color(
                          0xFFFF7B54,
                        ),
                        fontWeight:
                            FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),

                const SizedBox(
                  height: 13,
                ),

                Row(
                  mainAxisAlignment:
                      MainAxisAlignment
                          .spaceBetween,
                  children: List.generate(
                    7,
                    (
                      index,
                    ) {
                      final day =
                          index + 1;

                      return _StreakDay(
                        day: day,
                        completed:
                            day <=
                                streakProgress,
                        isReward:
                            day == 7,
                      );
                    },
                  ),
                ),

                const SizedBox(
                  height: 11,
                ),

                Text(
                  streakProgress >= 7
                      ? 'Série de 7 jours terminée. Le bonus sera activé plus tard.'
                      : 'Connecte-toi chaque jour pour atteindre le coffre spécial.',
                  style: TextStyle(
                    color: Colors.white
                        .withOpacity(
                      0.48,
                    ),
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(
            height: 12,
          ),

          InkWell(
            borderRadius:
                BorderRadius.circular(
              18,
            ),
            onTap: () {
              _showComingSoon(
                'La page des succès',
              );
            },
            child: Container(
              padding:
                  const EdgeInsets.all(
                14,
              ),
              decoration:
                  BoxDecoration(
                color: Colors.white
                    .withOpacity(
                  0.035,
                ),
                borderRadius:
                    BorderRadius.circular(
                  18,
                ),
                border: Border.all(
                  color: Colors.white
                      .withOpacity(
                    0.07,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration:
                        BoxDecoration(
                      color: const Color(
                        0xFFFFC857,
                      ).withOpacity(
                        0.10,
                      ),
                      borderRadius:
                          BorderRadius.circular(
                        14,
                      ),
                    ),
                    child: const Icon(
                      Icons
                          .emoji_events_rounded,
                      color: Color(
                        0xFFFFC857,
                      ),
                      size: 22,
                    ),
                  ),
                  const SizedBox(
                    width: 11,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Succès',
                          style:
                              TextStyle(
                            color:
                                Colors.white,
                            fontWeight:
                                FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(
                          height: 3,
                        ),
                        Text(
                          '$achievementCount succès débloqué${achievementCount > 1 ? 's' : ''} sur 5',
                          style: TextStyle(
                            color: Colors.white
                                .withOpacity(
                              0.50,
                            ),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '$achievementCount/5',
                    style:
                        const TextStyle(
                      color: Color(
                        0xFFFFC857,
                      ),
                      fontWeight:
                          FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(
                    width: 5,
                  ),
                  Icon(
                    Icons
                        .chevron_right_rounded,
                    color: Colors.white
                        .withOpacity(
                      0.35,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(
            height: 10,
          ),

          InkWell(
            borderRadius:
                BorderRadius.circular(
              18,
            ),
            onTap: () {
              _showComingSoon(
                'Les mini-jeux',
              );
            },
            child: Container(
              padding:
                  const EdgeInsets.all(
                14,
              ),
              decoration:
                  BoxDecoration(
                gradient:
                    LinearGradient(
                  colors: [
                    const Color(
                      0xFF7C5CFF,
                    ).withOpacity(
                      0.13,
                    ),
                    const Color(
                      0xFF55D6FF,
                    ).withOpacity(
                      0.06,
                    ),
                  ],
                ),
                borderRadius:
                    BorderRadius.circular(
                  18,
                ),
                border: Border.all(
                  color: const Color(
                    0xFF7C5CFF,
                  ).withOpacity(
                    0.25,
                  ),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons
                        .gamepad_rounded,
                    color: Color(
                      0xFF9D8AFF,
                    ),
                    size: 27,
                  ),
                  const SizedBox(
                    width: 11,
                  ),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mini-jeux',
                          style:
                              TextStyle(
                            color:
                                Colors.white,
                            fontWeight:
                                FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(
                          height: 3,
                        ),
                        Text(
                          'Gagne des points supplémentaires',
                          style:
                              TextStyle(
                            color: Color(
                              0xFF9097A6,
                            ),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets
                            .symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration:
                        BoxDecoration(
                      color: const Color(
                        0xFF9D8AFF,
                      ).withOpacity(
                        0.12,
                      ),
                      borderRadius:
                          BorderRadius.circular(
                        15,
                      ),
                    ),
                    child: const Text(
                      'BIENTÔT',
                      style:
                          TextStyle(
                        color: Color(
                          0xFF9D8AFF,
                        ),
                        fontWeight:
                            FontWeight.w900,
                        fontSize: 9,
                        letterSpacing:
                            0.5,
                      ),
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

  Widget _buildWithdrawGoal() {
    final progress =
        (_points / _withdrawTarget)
            .clamp(
              0.0,
              1.0,
            )
            .toDouble();

    final remaining = max(
      _withdrawTarget - _points,
      0,
    );

    return InkWell(
      borderRadius:
          BorderRadius.circular(
        24,
      ),
      onTap: () {
        _goToTab(
          2,
        );
      },
      child: _SoftCard(
        padding:
            const EdgeInsets.all(
          15,
        ),
        child: Column(
          children: [
            Row(
              children: [
                _IconBubble(
                  icon: Icons
                      .account_balance_wallet_rounded,
                  color: const Color(
                    0xFF55D6FF,
                  ),
                ),
                const SizedBox(
                  width: 11,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Objectif retrait',
                        style:
                            TextStyle(
                          color:
                              Colors.white,
                          fontSize: 17,
                          fontWeight:
                              FontWeight.w900,
                        ),
                      ),
                      const SizedBox(
                        height: 3,
                      ),
                      Text(
                        remaining > 0
                            ? 'Encore $remaining points à gagner'
                            : 'Premier objectif atteint',
                        style: TextStyle(
                          color: Colors.white
                              .withOpacity(
                            0.52,
                          ),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons
                      .chevron_right_rounded,
                  color: Color(
                    0xFF55D6FF,
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 14,
            ),
            Row(
              children: [
                Text(
                  '$_points points',
                  style:
                      const TextStyle(
                    color: Color(
                      0xFF55D6FF,
                    ),
                    fontWeight:
                        FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                Text(
                  '$_withdrawTarget points',
                  style: TextStyle(
                    color: Colors.white
                        .withOpacity(
                      0.48,
                    ),
                    fontWeight:
                        FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 8,
            ),
            ClipRRect(
              borderRadius:
                  BorderRadius.circular(
                50,
              ),
              child:
                  LinearProgressIndicator(
                value: progress,
                minHeight: 9,
                backgroundColor:
                    Colors.white
                        .withOpacity(
                  0.08,
                ),
                valueColor:
                    const AlwaysStoppedAnimation<
                        Color>(
                  Color(
                    0xFF55D6FF,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

// ================= FIN PARTIE 5/8 ====================
// ==================== PARTIE 6/8 ====================

  Widget _buildHistoryPage() {
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
      child: RefreshIndicator(
        color: const Color(
          0xFF2DE2A6,
        ),
        backgroundColor:
            const Color(
          0xFF111827,
        ),
        onRefresh: _loadHistory,
        child: ListView(
          physics:
              const AlwaysScrollableScrollPhysics(),
          padding:
              const EdgeInsets.fromLTRB(
            16,
            18,
            16,
            28,
          ),
          children: [
            _buildPageHeader(
              icon:
                  Icons.history_rounded,
              title: 'Historique',
              subtitle:
                  'Toutes tes récompenses',
              color: const Color(
                0xFF55D6FF,
              ),
            ),

            const SizedBox(
              height: 14,
            ),

            if (_historyLoading &&
                _history.isEmpty)
              const Padding(
                padding:
                    EdgeInsets.symmetric(
                  vertical: 60,
                ),
                child: Center(
                  child:
                      CircularProgressIndicator(
                    color: Color(
                      0xFF2DE2A6,
                    ),
                  ),
                ),
              )
            else if (_historyError !=
                null)
              _SoftCard(
                padding:
                    const EdgeInsets.all(
                  18,
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons
                          .cloud_off_rounded,
                      color: Color(
                        0xFFFF7B54,
                      ),
                      size: 38,
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    Text(
                      _historyError!,
                      textAlign:
                          TextAlign.center,
                      style:
                          const TextStyle(
                        color:
                            Colors.white,
                        fontWeight:
                            FontWeight.w800,
                      ),
                    ),
                    const SizedBox(
                      height: 14,
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          _loadHistory,
                      icon: const Icon(
                        Icons
                            .refresh_rounded,
                      ),
                      label:
                          const Text(
                        'Réessayer',
                      ),
                      style: OutlinedButton
                          .styleFrom(
                        foregroundColor:
                            const Color(
                          0xFF2DE2A6,
                        ),
                        side:
                            const BorderSide(
                          color: Color(
                            0xFF2DE2A6,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (_history.isEmpty)
              _SoftCard(
                padding:
                    const EdgeInsets.all(
                  24,
                ),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration:
                          BoxDecoration(
                        color:
                            const Color(
                          0xFF55D6FF,
                        ).withOpacity(
                          0.10,
                        ),
                        borderRadius:
                            BorderRadius
                                .circular(
                          21,
                        ),
                      ),
                      child:
                          const Icon(
                        Icons
                            .hourglass_empty_rounded,
                        color: Color(
                          0xFF55D6FF,
                        ),
                        size: 31,
                      ),
                    ),
                    const SizedBox(
                      height: 14,
                    ),
                    const Text(
                      'Aucune activité',
                      style:
                          TextStyle(
                        color:
                            Colors.white,
                        fontWeight:
                            FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(
                      height: 6,
                    ),
                    Text(
                      'Tes gains de minage, de coffre et de roue apparaîtront ici.',
                      textAlign:
                          TextAlign.center,
                      style: TextStyle(
                        color: Colors
                            .white
                            .withOpacity(
                          0.48,
                        ),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(
                      height: 16,
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        _goToTab(
                          0,
                        );
                      },
                      icon: const Icon(
                        Icons
                            .bolt_rounded,
                      ),
                      label:
                          const Text(
                        'Commencer',
                      ),
                      style: ElevatedButton
                          .styleFrom(
                        backgroundColor:
                            const Color(
                          0xFF2DE2A6,
                        ),
                        foregroundColor:
                            const Color(
                          0xFF04110D,
                        ),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
              )
            else
              ..._history.map(
                (
                  entry,
                ) =>
                    Padding(
                  padding:
                      const EdgeInsets
                          .only(
                    bottom: 10,
                  ),
                  child:
                      _buildHistoryItem(
                    entry,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryItem(
    _HistoryEntry entry,
  ) {
    final color =
        _historyColor(
      entry.type,
    );

    final icon =
        _historyIcon(
      entry.type,
    );

    return _SoftCard(
      padding:
          const EdgeInsets.all(
        14,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration:
                BoxDecoration(
              color: color.withOpacity(
                0.11,
              ),
              borderRadius:
                  BorderRadius.circular(
                15,
              ),
              border: Border.all(
                color: color.withOpacity(
                  0.20,
                ),
              ),
            ),
            child: Icon(
              icon,
              color: color,
              size: 22,
            ),
          ),

          const SizedBox(
            width: 12,
          ),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
              children: [
                Text(
                  entry.title,
                  maxLines: 1,
                  overflow:
                      TextOverflow
                          .ellipsis,
                  style:
                      const TextStyle(
                    color: Colors.white,
                    fontWeight:
                        FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(
                  height: 4,
                ),
                Text(
                  _formatHistoryDate(
                    entry.createdAt,
                  ),
                  style: TextStyle(
                    color: Colors.white
                        .withOpacity(
                      0.43,
                    ),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(
            width: 8,
          ),

          Text(
            entry.reward >= 0
                ? '+${entry.reward}'
                : '${entry.reward}',
            style: TextStyle(
              color: entry.reward >= 0
                  ? const Color(
                      0xFF2DE2A6,
                    )
                  : const Color(
                      0xFFFF7B54,
                    ),
              fontWeight:
                  FontWeight.w900,
              fontSize: 15,
            ),
          ),

          const SizedBox(
            width: 4,
          ),

          Text(
            'pts',
            style: TextStyle(
              color: Colors.white
                  .withOpacity(
                0.42,
              ),
              fontWeight:
                  FontWeight.w700,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Color _historyColor(
    String type,
  ) {
    switch (type) {
      case 'daily_chest':
        return const Color(
          0xFFFFC857,
        );

      case 'daily_wheel':
        return const Color(
          0xFFFF7B54,
        );

      case 'withdrawal':
        return const Color(
          0xFFFF6B7A,
        );

      default:
        return const Color(
          0xFF7C5CFF,
        );
    }
  }

  IconData _historyIcon(
    String type,
  ) {
    switch (type) {
      case 'daily_chest':
        return Icons
            .card_giftcard_rounded;

      case 'daily_wheel':
        return Icons.casino_rounded;

      case 'withdrawal':
        return Icons
            .account_balance_wallet_rounded;

      default:
        return Icons.bolt_rounded;
    }
  }

  String _formatHistoryDate(
    DateTime? date,
  ) {
    if (date == null) {
      return 'Date inconnue';
    }

    final localDate =
        date.toLocal();

    final now =
        DateTime.now();

    final today =
        DateTime(
      now.year,
      now.month,
      now.day,
    );

    final entryDay =
        DateTime(
      localDate.year,
      localDate.month,
      localDate.day,
    );

    final difference =
        today.difference(
      entryDay,
    ).inDays;

    final hour =
        localDate.hour
            .toString()
            .padLeft(
              2,
              '0',
            );

    final minute =
        localDate.minute
            .toString()
            .padLeft(
              2,
              '0',
            );

    if (difference == 0) {
      return 'Aujourd’hui à $hour:$minute';
    }

    if (difference == 1) {
      return 'Hier à $hour:$minute';
    }

    final day =
        localDate.day
            .toString()
            .padLeft(
              2,
              '0',
            );

    final month =
        localDate.month
            .toString()
            .padLeft(
              2,
              '0',
            );

    return '$day/$month/${localDate.year} à $hour:$minute';
  }

  Widget _buildWithdrawPage() {
    final progress =
        (_points /
                _withdrawTarget)
            .clamp(
              0.0,
              1.0,
            )
            .toDouble();

    final remaining =
        max(
      _withdrawTarget -
          _points,
      0,
    );

    final unlocked =
        _points >=
        _withdrawTarget;

    return Container(
      decoration:
          const BoxDecoration(
        gradient: LinearGradient(
          begin:
              Alignment.topCenter,
          end:
              Alignment.bottomCenter,
          colors: [
            Color(0xFF0A1020),
            Color(0xFF05070C),
          ],
        ),
      ),
      child: RefreshIndicator(
        color:
            const Color(
          0xFF2DE2A6,
        ),
        backgroundColor:
            const Color(
          0xFF111827,
        ),
        onRefresh: () {
          return _loadDailyStatus();
        },
        child: ListView(
          physics:
              const AlwaysScrollableScrollPhysics(),
          padding:
              const EdgeInsets.fromLTRB(
            16,
            18,
            16,
            28,
          ),
          children: [
            _buildPageHeader(
              icon: Icons
                  .account_balance_wallet_rounded,
              title: 'Retrait',
              subtitle:
                  'Transforme tes points plus tard',
              color: const Color(
                0xFF55D6FF,
              ),
            ),

            const SizedBox(
              height: 14,
            ),

            Container(
              padding:
                  const EdgeInsets.all(
                20,
              ),
              decoration:
                  BoxDecoration(
                gradient:
                    const LinearGradient(
                  colors: [
                    Color(
                      0xFF16243A,
                    ),
                    Color(
                      0xFF0D1525,
                    ),
                  ],
                ),
                borderRadius:
                    BorderRadius.circular(
                  25,
                ),
                border: Border.all(
                  color: const Color(
                    0xFF55D6FF,
                  ).withOpacity(
                    0.28,
                  ),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration:
                        BoxDecoration(
                      color: const Color(
                        0xFF55D6FF,
                      ).withOpacity(
                        0.11,
                      ),
                      shape:
                          BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons
                          .savings_rounded,
                      color: Color(
                        0xFF55D6FF,
                      ),
                      size: 34,
                    ),
                  ),

                  const SizedBox(
                    height: 15,
                  ),

                  Text(
                    '$_points points',
                    style:
                        const TextStyle(
                      color:
                          Colors.white,
                      fontSize: 31,
                      fontWeight:
                          FontWeight.w900,
                    ),
                  ),

                  const SizedBox(
                    height: 5,
                  ),

                  Text(
                    unlocked
                        ? 'Seuil de retrait atteint'
                        : 'Encore $remaining points avant le premier retrait',
                    textAlign:
                        TextAlign.center,
                    style: TextStyle(
                      color: Colors.white
                          .withOpacity(
                        0.52,
                      ),
                      fontSize: 12,
                    ),
                  ),

                  const SizedBox(
                    height: 18,
                  ),

                  ClipRRect(
                    borderRadius:
                        BorderRadius.circular(
                      50,
                    ),
                    child:
                        LinearProgressIndicator(
                      value: progress,
                      minHeight: 10,
                      backgroundColor:
                          Colors.white
                              .withOpacity(
                        0.08,
                      ),
                      valueColor:
                          const AlwaysStoppedAnimation<
                              Color>(
                        Color(
                          0xFF55D6FF,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(
                    height: 9,
                  ),

                  Row(
                    children: [
                      Text(
                        '$_points',
                        style:
                            const TextStyle(
                          color: Color(
                            0xFF55D6FF,
                          ),
                          fontWeight:
                              FontWeight
                                  .w900,
                          fontSize: 11,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '$_withdrawTarget pts',
                        style: TextStyle(
                          color: Colors
                              .white
                              .withOpacity(
                            0.42,
                          ),
                          fontWeight:
                              FontWeight
                                  .w800,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(
              height: 14,
            ),

            _SoftCard(
              padding:
                  const EdgeInsets.all(
                16,
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  const Text(
                    'Comment cela fonctionnera ?',
                    style:
                        TextStyle(
                      color:
                          Colors.white,
                      fontWeight:
                          FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),

                  const SizedBox(
                    height: 14,
                  ),

                  const _InfoStep(
                    number: '1',
                    title:
                        'Atteindre le seuil',
                    subtitle:
                        'Accumule au minimum 10 000 points.',
                  ),

                  const SizedBox(
                    height: 12,
                  ),

                  const _InfoStep(
                    number: '2',
                    title:
                        'Choisir une récompense',
                    subtitle:
                        'Les méthodes de retrait seront ajoutées ultérieurement.',
                  ),

                  const SizedBox(
                    height: 12,
                  ),

                  const _InfoStep(
                    number: '3',
                    title:
                        'Validation sécurisée',
                    subtitle:
                        'Chaque demande sera vérifiée pour éviter la fraude.',
                  ),
                ],
              ),
            ),

            const SizedBox(
              height: 14,
            ),

            SizedBox(
              height: 51,
              child: ElevatedButton.icon(
                onPressed: unlocked
                    ? () {
                        _showComingSoon(
                          'Les retraits',
                        );
                      }
                    : null,
                icon: Icon(
                  unlocked
                      ? Icons
                          .lock_open_rounded
                      : Icons
                          .lock_rounded,
                ),
                label: Text(
                  unlocked
                      ? 'Voir les retraits'
                      : 'Retrait verrouillé',
                  style:
                      const TextStyle(
                    fontWeight:
                        FontWeight.w900,
                  ),
                ),
                style:
                    ElevatedButton.styleFrom(
                  backgroundColor:
                      const Color(
                    0xFF55D6FF,
                  ),
                  disabledBackgroundColor:
                      Colors.white
                          .withOpacity(
                    0.07,
                  ),
                  foregroundColor:
                      const Color(
                    0xFF04121A,
                  ),
                  disabledForegroundColor:
                      Colors.white
                          .withOpacity(
                    0.35,
                  ),
                  elevation: 0,
                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(
                      16,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfilePage() {
    final levelData =
        _calculateLevel(
      _points,
    );

    final leagueData =
        _calculateLeague(
      _points,
    );

    return Container(
      decoration:
          const BoxDecoration(
        gradient: LinearGradient(
          begin:
              Alignment.topCenter,
          end:
              Alignment.bottomCenter,
          colors: [
            Color(0xFF0A1020),
            Color(0xFF05070C),
          ],
        ),
      ),
      child: RefreshIndicator(
        color:
            const Color(
          0xFF2DE2A6,
        ),
        backgroundColor:
            const Color(
          0xFF111827,
        ),
        onRefresh: () {
          return _loadDailyStatus();
        },
        child: ListView(
          physics:
              const AlwaysScrollableScrollPhysics(),
          padding:
              const EdgeInsets.fromLTRB(
            16,
            18,
            16,
            28,
          ),
          children: [
            _buildPageHeader(
              icon:
                  Icons.person_rounded,
              title: 'Profil',
              subtitle:
                  'Tes informations et statistiques',
              color: const Color(
                0xFF9D8AFF,
              ),
            ),

            const SizedBox(
              height: 14,
            ),

            _SoftCard(
              padding:
                  const EdgeInsets.all(
                18,
              ),
              child: Column(
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration:
                        BoxDecoration(
                      gradient:
                          const LinearGradient(
                        colors: [
                          Color(
                            0xFF7C5CFF,
                          ),
                          Color(
                            0xFF55D6FF,
                          ),
                        ],
                      ),
                      borderRadius:
                          BorderRadius.circular(
                        25,
                      ),
                    ),
                    child:
                        const Icon(
                      Icons
                          .person_rounded,
                      color:
                          Colors.white,
                      size: 40,
                    ),
                  ),

                  const SizedBox(
                    height: 13,
                  ),

                  Text(
                    widget.user.email,
                    textAlign:
                        TextAlign.center,
                    style:
                        const TextStyle(
                      color:
                          Colors.white,
                      fontWeight:
                          FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),

                  const SizedBox(
                    height: 7,
                  ),

                  Container(
                    padding:
                        const EdgeInsets
                            .symmetric(
                      horizontal: 11,
                      vertical: 6,
                    ),
                    decoration:
                        BoxDecoration(
                      color: leagueData
                          .color
                          .withOpacity(
                        0.11,
                      ),
                      borderRadius:
                          BorderRadius.circular(
                        18,
                      ),
                    ),
                    child: Text(
                      'Ligue ${leagueData.name} • Niveau ${levelData.level}',
                      style: TextStyle(
                        color:
                            leagueData.color,
                        fontWeight:
                            FontWeight.w900,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(
              height: 12,
            ),

            Row(
              children: [
                Expanded(
                  child:
                      _ProfileStatCard(
                    icon:
                        Icons.toll_rounded,
                    value:
                        '$_points',
                    label:
                        'Points',
                    color:
                        const Color(
                      0xFF2DE2A6,
                    ),
                  ),
                ),
                const SizedBox(
                  width: 10,
                ),
                Expanded(
                  child:
                      _ProfileStatCard(
                    icon: Icons
                        .bolt_rounded,
                    value:
                        '$_todayMines',
                    label:
                        'Minages du jour',
                    color:
                        const Color(
                      0xFF7C5CFF,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(
              height: 10,
            ),

            Row(
              children: [
                Expanded(
                  child:
                      _ProfileStatCard(
                    icon: Icons
                        .stars_rounded,
                    value:
                        '$_todayPointsEarned',
                    label:
                        'Points du jour',
                    color:
                        const Color(
                      0xFFFFC857,
                    ),
                  ),
                ),
                const SizedBox(
                  width: 10,
                ),
                Expanded(
                  child:
                      _ProfileStatCard(
                    icon: Icons
                        .local_fire_department_rounded,
                    value:
                        '$_loginStreak',
                    label:
                        'Jours de série',
                    color:
                        const Color(
                      0xFFFF7B54,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(
              height: 12,
            ),

            _SoftCard(
              padding:
                  const EdgeInsets.all(
                15,
              ),
              child: Column(
                children: [
                  _ProfileOption(
                    icon: Icons
                        .verified_user_rounded,
                    title:
                        'Sécurité du compte',
                    subtitle:
                        'Connexion protégée par token',
                    color:
                        const Color(
                      0xFF2DE2A6,
                    ),
                    onTap: () {
                      _showComingSoon(
                        'Les paramètres de sécurité',
                      );
                    },
                  ),

                  const Divider(
                    color: Color(
                      0xFF222938,
                    ),
                    height: 24,
                  ),

                  _ProfileOption(
                    icon: Icons
                        .notifications_rounded,
                    title:
                        'Notifications',
                    subtitle:
                        'Rappels quotidiens bientôt disponibles',
                    color:
                        const Color(
                      0xFFFFC857,
                    ),
                    onTap: () {
                      _showComingSoon(
                        'Les notifications',
                      );
                    },
                  ),

                  const Divider(
                    color: Color(
                      0xFF222938,
                    ),
                    height: 24,
                  ),

                  _ProfileOption(
                    icon:
                        Icons.help_rounded,
                    title:
                        'Aide',
                    subtitle:
                        'Guide et questions fréquentes',
                    color:
                        const Color(
                      0xFF55D6FF,
                    ),
                    onTap: () {
                      _showComingSoon(
                        'Le centre d’aide',
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration:
              BoxDecoration(
            color: color.withOpacity(
              0.11,
            ),
            borderRadius:
                BorderRadius.circular(
              17,
            ),
            border: Border.all(
              color: color.withOpacity(
                0.24,
              ),
            ),
          ),
          child: Icon(
            icon,
            color: color,
            size: 25,
          ),
        ),

        const SizedBox(
          width: 12,
        ),

        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment
                    .start,
            children: [
              Text(
                title,
                style:
                    const TextStyle(
                  color:
                      Colors.white,
                  fontSize: 23,
                  fontWeight:
                      FontWeight.w900,
                  letterSpacing:
                      -0.4,
                ),
              ),
              const SizedBox(
                height: 3,
              ),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white
                      .withOpacity(
                    0.47,
                  ),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),

        if (_dailyStatusLoading)
          const SizedBox(
            width: 20,
            height: 20,
            child:
                CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(
                0xFF2DE2A6,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBottomNav() {
    const items = [
      _BottomNavItem(
        icon: Icons.home_rounded,
        label: 'Accueil',
      ),
      _BottomNavItem(
        icon: Icons.history_rounded,
        label: 'Historique',
      ),
      _BottomNavItem(
        icon: Icons
            .account_balance_wallet_rounded,
        label: 'Retrait',
      ),
      _BottomNavItem(
        icon: Icons.person_rounded,
        label: 'Profil',
      ),
    ];

    return Container(
      decoration:
          const BoxDecoration(
        color: Color(
          0xFF090D16,
        ),
        border: Border(
          top: BorderSide(
            color: Color(
              0xFF1C2330,
            ),
          ),
        ),
      ),
      padding:
          const EdgeInsets.fromLTRB(
        8,
        7,
        8,
        8,
      ),
      child: Row(
        children:
            List.generate(
          items.length,
          (
            index,
          ) {
            final item =
                items[index];

            final selected =
                index ==
                _selectedIndex;

            return Expanded(
              child: InkWell(
                borderRadius:
                    BorderRadius.circular(
                  16,
                ),
                onTap: () {
                  _onNavTap(
                    index,
                  );
                },
                child: AnimatedContainer(
                  duration:
                      const Duration(
                    milliseconds: 180,
                  ),
                  padding:
                      const EdgeInsets
                          .symmetric(
                    vertical: 8,
                  ),
                  decoration:
                      BoxDecoration(
                    color: selected
                        ? const Color(
                            0xFF2DE2A6,
                          ).withOpacity(
                            0.10,
                          )
                        : Colors
                            .transparent,
                    borderRadius:
                        BorderRadius.circular(
                      16,
                    ),
                  ),
                  child: Column(
                    mainAxisSize:
                        MainAxisSize.min,
                    children: [
                      Icon(
                        item.icon,
                        color: selected
                            ? const Color(
                                0xFF2DE2A6,
                              )
                            : Colors.white
                                .withOpacity(
                                0.38,
                              ),
                        size: 22,
                      ),
                      const SizedBox(
                        height: 3,
                      ),
                      Text(
                        item.label,
                        style: TextStyle(
                          color: selected
                              ? const Color(
                                  0xFF2DE2A6,
                                )
                              : Colors.white
                                  .withOpacity(
                                  0.38,
                                ),
                          fontSize: 10,
                          fontWeight:
                              selected
                                  ? FontWeight
                                      .w900
                                  : FontWeight
                                      .w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ================= FIN PARTIE 6/8 ====================
// ==================== PARTIE 7/8 ====================

int? _asInt(
  dynamic value,
) {
  if (value == null) {
    return null;
  }

  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(
    value.toString(),
  );
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

  int get xpToNext {
    return max(
      neededXp - currentXp,
      0,
    );
  }

  double get progress {
    if (neededXp <= 0) {
      return 0;
    }

    return (currentXp / neededXp)
        .clamp(
          0.0,
          1.0,
        )
        .toDouble();
  }
}

class _LeagueData {
  final String name;
  final String nextName;

  final int minimum;
  final int target;

  final IconData icon;
  final Color color;

  const _LeagueData({
    required this.name,
    required this.nextName,
    required this.minimum,
    required this.target,
    required this.icon,
    required this.color,
  });

  double progressFor(
    int points,
  ) {
    final range =
        target - minimum;

    if (range <= 0) {
      return 1;
    }

    final current =
        points - minimum;

    return (current / range)
        .clamp(
          0.0,
          1.0,
        )
        .toDouble();
  }

  int pointsToNext(
    int points,
  ) {
    return max(
      target - points,
      0,
    );
  }
}

class _HistoryEntry {
  final int reward;
  final String type;
  final String description;
  final DateTime? createdAt;

  const _HistoryEntry({
    required this.reward,
    required this.type,
    required this.description,
    required this.createdAt,
  });

  factory _HistoryEntry.fromJson(
    Map<String, dynamic> json,
  ) {
    final reward =
        _asInt(
          json['reward'],
        ) ??
        _asInt(
          json['reward_points'],
        ) ??
        0;

    final type =
        json['type']
            ?.toString()
            .trim() ??
        'mining';

    final description =
        json['description']
            ?.toString()
            .trim() ??
        '';

    final rawDate =
        json['created_at'] ??
        json['createdAt'] ??
        json['date'];

    return _HistoryEntry(
      reward: reward,
      type: type.isEmpty
          ? 'mining'
          : type,
      description:
          description,
      createdAt:
          rawDate == null
              ? null
              : DateTime.tryParse(
                  rawDate.toString(),
                ),
    );
  }

  String get title {
    if (description.isNotEmpty) {
      return description;
    }

    switch (type) {
      case 'daily_chest':
        return 'Coffre quotidien';

      case 'daily_wheel':
        return 'Roue quotidienne';

      case 'withdrawal':
        return 'Retrait';

      default:
        return 'Session de minage';
    }
  }
}

class _WheelSpinOutcome {
  final bool success;
  final int? reward;
  final String message;

  const _WheelSpinOutcome({
    required this.success,
    this.reward,
    required this.message,
  });
}

class _BottomNavItem {
  final IconData icon;
  final String label;

  const _BottomNavItem({
    required this.icon,
    required this.label,
  });
}

class _SoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _SoftCard({
    required this.child,
    required this.padding,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(
          0xFF101622,
        ),
        borderRadius:
            BorderRadius.circular(
          24,
        ),
        border: Border.all(
          color: Colors.white
              .withOpacity(
            0.07,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withOpacity(
              0.18,
            ),
            blurRadius: 18,
            offset:
                const Offset(
              0,
              9,
            ),
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
  Widget build(
    BuildContext context,
  ) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withOpacity(
          0.11,
        ),
        borderRadius:
            BorderRadius.circular(
          14,
        ),
        border: Border.all(
          color: color.withOpacity(
            0.19,
          ),
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

class _HeaderStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _HeaderStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 11,
      ),
      decoration: BoxDecoration(
        color: Colors.white
            .withOpacity(
          0.045,
        ),
        borderRadius:
            BorderRadius.circular(
          16,
        ),
        border: Border.all(
          color: Colors.white
              .withOpacity(
            0.06,
          ),
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: color,
            size: 19,
          ),
          const SizedBox(
            height: 6,
          ),
          Text(
            value,
            maxLines: 1,
            overflow:
                TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight:
                  FontWeight.w900,
            ),
          ),
          const SizedBox(
            height: 2,
          ),
          Text(
            label,
            maxLines: 1,
            overflow:
                TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white
                  .withOpacity(
                0.42,
              ),
              fontSize: 9.5,
              fontWeight:
                  FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactMissionRow
    extends StatelessWidget {
  final IconData icon;
  final String title;
  final String reward;

  final int current;
  final int target;

  final Color color;

  const _CompactMissionRow({
    required this.icon,
    required this.title,
    required this.reward,
    required this.current,
    required this.target,
    required this.color,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final safeTarget =
        max(
      target,
      1,
    );

    final safeCurrent =
        current.clamp(
      0,
      safeTarget,
    );

    final completed =
        current >= target &&
        target > 0;

    final progress =
        (safeCurrent / safeTarget)
            .clamp(
              0.0,
              1.0,
            )
            .toDouble();

    return Container(
      padding:
          const EdgeInsets.all(
        11,
      ),
      decoration: BoxDecoration(
        color: completed
            ? color.withOpacity(
                0.08,
              )
            : Colors.white
                .withOpacity(
                0.032,
              ),
        borderRadius:
            BorderRadius.circular(
          16,
        ),
        border: Border.all(
          color: completed
              ? color.withOpacity(
                  0.20,
                )
              : Colors.white
                  .withOpacity(
                  0.055,
                ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration:
                BoxDecoration(
              color: color.withOpacity(
                0.10,
              ),
              borderRadius:
                  BorderRadius.circular(
                12,
              ),
            ),
            child: Icon(
              completed
                  ? Icons
                      .check_rounded
                  : icon,
              color: color,
              size: 19,
            ),
          ),

          const SizedBox(
            width: 10,
          ),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow:
                            TextOverflow
                                .ellipsis,
                        style:
                            const TextStyle(
                          color:
                              Colors.white,
                          fontWeight:
                              FontWeight
                                  .w900,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    const SizedBox(
                      width: 7,
                    ),
                    Text(
                      '$safeCurrent/$safeTarget',
                      style: TextStyle(
                        color: completed
                            ? color
                            : Colors.white
                                .withOpacity(
                                0.48,
                              ),
                        fontWeight:
                            FontWeight
                                .w900,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),

                const SizedBox(
                  height: 4,
                ),

                Text(
                  reward,
                  maxLines: 1,
                  overflow:
                      TextOverflow
                          .ellipsis,
                  style: TextStyle(
                    color: color
                        .withOpacity(
                      0.78,
                    ),
                    fontSize: 10,
                    fontWeight:
                        FontWeight.w700,
                  ),
                ),

                const SizedBox(
                  height: 7,
                ),

                ClipRRect(
                  borderRadius:
                      BorderRadius.circular(
                    50,
                  ),
                  child:
                      LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    backgroundColor:
                        Colors.white
                            .withOpacity(
                      0.07,
                    ),
                    valueColor:
                        AlwaysStoppedAnimation<
                            Color>(
                      color,
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
}

class _GameFeatureCard
    extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;

  final Color color;
  final VoidCallback onTap;

  const _GameFeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return InkWell(
      borderRadius:
          BorderRadius.circular(
        18,
      ),
      onTap: onTap,
      child: Container(
        constraints:
            const BoxConstraints(
          minHeight: 145,
        ),
        padding:
            const EdgeInsets.all(
          13,
        ),
        decoration: BoxDecoration(
          gradient:
              LinearGradient(
            begin:
                Alignment.topLeft,
            end:
                Alignment.bottomRight,
            colors: [
              color.withOpacity(
                0.14,
              ),
              color.withOpacity(
                0.035,
              ),
            ],
          ),
          borderRadius:
              BorderRadius.circular(
            18,
          ),
          border: Border.all(
            color: color.withOpacity(
              0.24,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment
                  .start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration:
                      BoxDecoration(
                    color:
                        color.withOpacity(
                      0.12,
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      13,
                    ),
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: 21,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets
                          .symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration:
                      BoxDecoration(
                    color:
                        color.withOpacity(
                      0.11,
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      13,
                    ),
                  ),
                  child: Text(
                    badge.toUpperCase(),
                    style: TextStyle(
                      color: color,
                      fontSize: 8.5,
                      fontWeight:
                          FontWeight
                              .w900,
                      letterSpacing:
                          0.4,
                    ),
                  ),
                ),
              ],
            ),

            const Spacer(),

            Text(
              title,
              maxLines: 2,
              overflow:
                  TextOverflow.ellipsis,
              style:
                  const TextStyle(
                color: Colors.white,
                fontWeight:
                    FontWeight.w900,
                fontSize: 13.5,
                height: 1.15,
              ),
            ),

            const SizedBox(
              height: 5,
            ),

            Text(
              subtitle,
              maxLines: 2,
              overflow:
                  TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white
                    .withOpacity(
                  0.47,
                ),
                fontSize: 10.5,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StreakDay
    extends StatelessWidget {
  final int day;
  final bool completed;
  final bool isReward;

  const _StreakDay({
    required this.day,
    required this.completed,
    required this.isReward,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final color =
        isReward
            ? const Color(
                0xFFFFC857,
              )
            : const Color(
                0xFFFF7B54,
              );

    return Column(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration:
              BoxDecoration(
            color: completed
                ? color
                : color.withOpacity(
                    0.08,
                  ),
            shape:
                BoxShape.circle,
            border: Border.all(
              color: completed
                  ? color
                  : color.withOpacity(
                      0.20,
                    ),
            ),
          ),
          child: Icon(
            isReward
                ? Icons
                    .card_giftcard_rounded
                : completed
                    ? Icons
                        .check_rounded
                    : Icons
                        .circle_outlined,
            color: completed
                ? const Color(
                    0xFF211000,
                  )
                : color,
            size: isReward
                ? 16
                : 14,
          ),
        ),
        const SizedBox(
          height: 5,
        ),
        Text(
          'J$day',
          style: TextStyle(
            color: completed
                ? color
                : Colors.white
                    .withOpacity(
                    0.35,
                  ),
            fontWeight:
                FontWeight.w800,
            fontSize: 9,
          ),
        ),
      ],
    );
  }
}

class _InfoStep
    extends StatelessWidget {
  final String number;
  final String title;
  final String subtitle;

  const _InfoStep({
    required this.number,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Container(
          width: 31,
          height: 31,
          decoration:
              const BoxDecoration(
            color: Color(
              0xFF55D6FF,
            ),
            shape: BoxShape.circle,
          ),
          alignment:
              Alignment.center,
          child: Text(
            number,
            style:
                const TextStyle(
              color: Color(
                0xFF04121A,
              ),
              fontWeight:
                  FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(
          width: 11,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment
                    .start,
            children: [
              Text(
                title,
                style:
                    const TextStyle(
                  color: Colors.white,
                  fontWeight:
                      FontWeight.w900,
                  fontSize: 13,
                ),
              ),
              const SizedBox(
                height: 4,
              ),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white
                      .withOpacity(
                    0.47,
                  ),
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileStatCard
    extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _ProfileStatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding:
          const EdgeInsets.all(
        14,
      ),
      decoration: BoxDecoration(
        color: const Color(
          0xFF101622,
        ),
        borderRadius:
            BorderRadius.circular(
          20,
        ),
        border: Border.all(
          color: color.withOpacity(
            0.15,
          ),
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: color,
            size: 23,
          ),
          const SizedBox(
            height: 8,
          ),
          Text(
            value,
            maxLines: 1,
            overflow:
                TextOverflow.ellipsis,
            style:
                const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight:
                  FontWeight.w900,
            ),
          ),
          const SizedBox(
            height: 3,
          ),
          Text(
            label,
            maxLines: 1,
            overflow:
                TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white
                  .withOpacity(
                0.44,
              ),
              fontSize: 10.5,
              fontWeight:
                  FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileOption
    extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ProfileOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return InkWell(
      borderRadius:
          BorderRadius.circular(
        15,
      ),
      onTap: onTap,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(
          vertical: 4,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration:
                  BoxDecoration(
                color:
                    color.withOpacity(
                  0.10,
                ),
                borderRadius:
                    BorderRadius.circular(
                  13,
                ),
              ),
              child: Icon(
                icon,
                color: color,
                size: 21,
              ),
            ),
            const SizedBox(
              width: 11,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  Text(
                    title,
                    style:
                        const TextStyle(
                      color:
                          Colors.white,
                      fontWeight:
                          FontWeight
                              .w900,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(
                    height: 3,
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white
                          .withOpacity(
                        0.45,
                      ),
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons
                  .chevron_right_rounded,
              color: Colors.white
                  .withOpacity(
                0.30,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= FIN PARTIE 7/8 ====================
// ==================== PARTIE 8/8 ====================

class _DailyWheelDialog
    extends StatefulWidget {
  final List<int> rewards;
  final bool available;
  final int? previousReward;
  final DateTime? nextAvailableAt;

  final Future<_WheelSpinOutcome>
      Function() onSpin;

  const _DailyWheelDialog({
    required this.rewards,
    required this.available,
    required this.previousReward,
    required this.nextAvailableAt,
    required this.onSpin,
  });

  @override
  State<_DailyWheelDialog>
      createState() =>
          _DailyWheelDialogState();
}

class _DailyWheelDialogState
    extends State<_DailyWheelDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController
      _controller;

  Animation<double>?
      _rotationAnimation;

  late bool _available;

  bool _spinning = false;

  double _rotation = 0;

  int? _reward;

  String? _statusMessage;

  @override
  void initState() {
    super.initState();

    _available =
        widget.available;

    _reward =
        widget.previousReward;

    _controller =
        AnimationController(
      vsync: this,
      duration:
          const Duration(
        milliseconds: 4700,
      ),
    );

    if (!_available &&
        _reward != null) {
      _rotation =
          _rotationForReward(
        _reward!,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _rotationForReward(
    int reward,
  ) {
    if (widget.rewards.isEmpty) {
      return 0;
    }

    int index =
        widget.rewards.indexOf(
      reward,
    );

    if (index < 0) {
      index = 0;
    }

    final segmentAngle =
        (2 * pi) /
        widget.rewards.length;

    final desiredRotation =
        -(
          index + 0.5
        ) *
        segmentAngle;

    return desiredRotation;
  }

  Future<void> _startSpin() async {
    if (_spinning ||
        !_available) {
      return;
    }

    setState(() {
      _spinning = true;
      _statusMessage =
          'Validation du tour...';
    });

    try {
      final outcome =
          await widget.onSpin();

      if (!mounted) return;

      if (!outcome.success ||
          outcome.reward == null) {
        setState(() {
          _spinning = false;

          _statusMessage =
              outcome.message;

          if (outcome.reward !=
              null) {
            _reward =
                outcome.reward;

            _available =
                false;

            _rotation =
                _rotationForReward(
              outcome.reward!,
            );
          }
        });

        return;
      }

      final reward =
          outcome.reward!;

      int rewardIndex =
          widget.rewards.indexOf(
        reward,
      );

      if (rewardIndex < 0) {
        rewardIndex = 0;
      }

      final segmentAngle =
          (2 * pi) /
          widget.rewards.length;

      double desiredPosition =
          -(
            rewardIndex + 0.5
          ) *
          segmentAngle;

      desiredPosition %=
          2 * pi;

      final currentPosition =
          _rotation %
          (2 * pi);

      double finalDifference =
          desiredPosition -
          currentPosition;

      while (finalDifference < 0) {
        finalDifference +=
            2 * pi;
      }

      const completeTurns = 6;

      final targetRotation =
          _rotation +
          (
            completeTurns *
            2 *
            pi
          ) +
          finalDifference;

      _rotationAnimation =
          Tween<double>(
        begin: _rotation,
        end: targetRotation,
      ).animate(
        CurvedAnimation(
          parent: _controller,
          curve:
              Curves.easeOutQuart,
        ),
      );

      setState(() {
        _statusMessage =
            'La roue tourne...';
      });

      await _controller.forward(
        from: 0,
      );

      if (!mounted) return;

      setState(() {
        _rotation =
            targetRotation;

        _reward =
            reward;

        _available =
            false;

        _spinning =
            false;

        _statusMessage =
            outcome.message;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _spinning = false;

        _statusMessage =
            'Une erreur est survenue pendant le tour.';
      });
    }
  }

  String _availabilityText() {
    if (_available) {
      return 'Un tour gratuit disponible';
    }

    if (_reward != null) {
      return 'Gain du jour : +$_reward points';
    }

    return 'Tour déjà utilisé aujourd’hui';
  }

  String _nextWheelText() {
    if (_available) {
      return 'La récompense est déterminée par le serveur.';
    }

    final nextDate =
        widget.nextAvailableAt;

    if (nextDate == null) {
      return 'Un nouveau tour sera disponible demain.';
    }

    final hour =
        nextDate.hour
            .toString()
            .padLeft(
              2,
              '0',
            );

    final minute =
        nextDate.minute
            .toString()
            .padLeft(
              2,
              '0',
            );

    return 'Prochain tour disponible à $hour:$minute.';
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final screenWidth =
        MediaQuery.of(
      context,
    ).size.width;

    final wheelSize =
        min(
      screenWidth - 72,
      290.0,
    );

    return Dialog(
      backgroundColor:
          Colors.transparent,
      insetPadding:
          const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 24,
      ),
      child: Container(
        width: double.infinity,
        constraints:
            const BoxConstraints(
          maxWidth: 390,
        ),
        padding:
            const EdgeInsets.fromLTRB(
          18,
          15,
          18,
          19,
        ),
        decoration:
            BoxDecoration(
          gradient:
              const LinearGradient(
            begin:
                Alignment.topLeft,
            end:
                Alignment.bottomRight,
            colors: [
              Color(
                0xFF171D2C,
              ),
              Color(
                0xFF090D16,
              ),
            ],
          ),
          borderRadius:
              BorderRadius.circular(
            28,
          ),
          border: Border.all(
            color: const Color(
              0xFFFF7B54,
            ).withOpacity(
              0.28,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black
                  .withOpacity(
                0.52,
              ),
              blurRadius: 32,
              offset:
                  const Offset(
                0,
                18,
              ),
            ),
          ],
        ),
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 43,
                  height: 43,
                  decoration:
                      BoxDecoration(
                    color: const Color(
                      0xFFFF7B54,
                    ).withOpacity(
                      0.11,
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      14,
                    ),
                  ),
                  child:
                      const Icon(
                    Icons
                        .casino_rounded,
                    color: Color(
                      0xFFFF7B54,
                    ),
                    size: 23,
                  ),
                ),

                const SizedBox(
                  width: 11,
                ),

                const Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      Text(
                        'Roue quotidienne',
                        style:
                            TextStyle(
                          color:
                              Colors.white,
                          fontSize: 19,
                          fontWeight:
                              FontWeight
                                  .w900,
                        ),
                      ),
                      SizedBox(
                        height: 3,
                      ),
                      Text(
                        'Un gain garanti chaque jour',
                        style:
                            TextStyle(
                          color: Color(
                            0xFF9097A6,
                          ),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),

                IconButton(
                  onPressed:
                      _spinning
                          ? null
                          : () {
                              Navigator.of(
                                context,
                              ).pop();
                            },
                  icon: Icon(
                    Icons
                        .close_rounded,
                    color: Colors.white
                        .withOpacity(
                      0.55,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(
              height: 12,
            ),

            Text(
              _availabilityText(),
              textAlign:
                  TextAlign.center,
              style:
                  const TextStyle(
                color:
                    Colors.white,
                fontWeight:
                    FontWeight.w900,
                fontSize: 14,
              ),
            ),

            const SizedBox(
              height: 15,
            ),

            SizedBox(
              width: wheelSize,
              height: wheelSize,
              child: Stack(
                alignment:
                    Alignment.center,
                clipBehavior:
                    Clip.none,
                children: [
                  AnimatedBuilder(
                    animation:
                        _controller,
                    builder: (
                      context,
                      child,
                    ) {
                      final rotation =
                          _rotationAnimation
                                  ?.value ??
                              _rotation;

                      return CustomPaint(
                        size: Size.square(
                          wheelSize,
                        ),
                        painter:
                            _DailyWheelPainter(
                          rewards:
                              widget.rewards,
                          rotation:
                              rotation,
                          selectedReward:
                              _reward,
                        ),
                      );
                    },
                  ),

                  Positioned(
                    top: -4,
                    child: Container(
                      width: 36,
                      height: 42,
                      decoration:
                          BoxDecoration(
                        color:
                            const Color(
                          0xFFFFC857,
                        ),
                        borderRadius:
                            BorderRadius.circular(
                          12,
                        ),
                        border: Border.all(
                          color:
                              Colors.white,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                Colors.black
                                    .withOpacity(
                              0.36,
                            ),
                            blurRadius:
                                10,
                            offset:
                                const Offset(
                              0,
                              5,
                            ),
                          ),
                        ],
                      ),
                      child:
                          const Icon(
                        Icons
                            .arrow_drop_down_rounded,
                        color: Color(
                          0xFF241800,
                        ),
                        size: 35,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(
              height: 14,
            ),

            if (_statusMessage !=
                null)
              Container(
                width:
                    double.infinity,
                padding:
                    const EdgeInsets
                        .symmetric(
                  horizontal: 13,
                  vertical: 11,
                ),
                decoration:
                    BoxDecoration(
                  color: const Color(
                    0xFFFF7B54,
                  ).withOpacity(
                    0.08,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    15,
                  ),
                  border: Border.all(
                    color: const Color(
                      0xFFFF7B54,
                    ).withOpacity(
                      0.18,
                    ),
                  ),
                ),
                child: Text(
                  _statusMessage!,
                  textAlign:
                      TextAlign.center,
                  style:
                      const TextStyle(
                    color:
                        Colors.white,
                    fontWeight:
                        FontWeight.w800,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ),

            const SizedBox(
              height: 13,
            ),

            Text(
              _nextWheelText(),
              textAlign:
                  TextAlign.center,
              style: TextStyle(
                color: Colors.white
                    .withOpacity(
                  0.45,
                ),
                fontSize: 10.5,
                height: 1.35,
              ),
            ),

            const SizedBox(
              height: 15,
            ),

            SizedBox(
              width: double.infinity,
              height: 51,
              child:
                  ElevatedButton.icon(
                onPressed:
                    _available &&
                            !_spinning
                        ? _startSpin
                        : null,
                icon: _spinning
                    ? const SizedBox(
                        width: 19,
                        height: 19,
                        child:
                            CircularProgressIndicator(
                          strokeWidth:
                              2.2,
                          color: Color(
                            0xFF231000,
                          ),
                        ),
                      )
                    : Icon(
                        _available
                            ? Icons
                                .play_arrow_rounded
                            : Icons
                                .check_circle_rounded,
                        size: 23,
                      ),
                label: Text(
                  _spinning
                      ? 'La roue tourne...'
                      : _available
                          ? 'Lancer mon tour'
                          : 'Tour utilisé aujourd’hui',
                  style:
                      const TextStyle(
                    fontWeight:
                        FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                style:
                    ElevatedButton.styleFrom(
                  backgroundColor:
                      const Color(
                    0xFFFF7B54,
                  ),
                  disabledBackgroundColor:
                      _available
                          ? const Color(
                              0xFFFF7B54,
                            ).withOpacity(
                              0.55,
                            )
                          : const Color(
                              0xFF2DE2A6,
                            ).withOpacity(
                              0.10,
                            ),
                  foregroundColor:
                      const Color(
                    0xFF231000,
                  ),
                  disabledForegroundColor:
                      _available
                          ? const Color(
                              0xFF231000,
                            )
                          : const Color(
                              0xFF2DE2A6,
                            ),
                  elevation: 0,
                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(
                      17,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyWheelPainter
    extends CustomPainter {
  final List<int> rewards;
  final double rotation;
  final int? selectedReward;

  const _DailyWheelPainter({
    required this.rewards,
    required this.rotation,
    required this.selectedReward,
  });

  static const List<Color>
      _segmentColors = [
    Color(
      0xFF7C5CFF,
    ),
    Color(
      0xFFFF7B54,
    ),
    Color(
      0xFF2DA9FF,
    ),
    Color(
      0xFF2DE2A6,
    ),
    Color(
      0xFFFFC857,
    ),
    Color(
      0xFFE95CFF,
    ),
  ];

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    if (rewards.isEmpty) {
      return;
    }

    final center = Offset(
      size.width / 2,
      size.height / 2,
    );

    final radius =
        min(
      size.width,
      size.height,
    ) /
        2 -
        10;

    final wheelRect =
        Rect.fromCircle(
      center: center,
      radius: radius,
    );

    final segmentAngle =
        (2 * pi) /
        rewards.length;

    final outerShadowPaint =
        Paint()
          ..color = Colors.black
              .withOpacity(
            0.34,
          )
          ..maskFilter =
              const MaskFilter.blur(
            BlurStyle.normal,
            12,
          );

    canvas.drawCircle(
      center.translate(
        0,
        7,
      ),
      radius,
      outerShadowPaint,
    );

    for (
      int index = 0;
      index < rewards.length;
      index++
    ) {
      final reward =
          rewards[index];

      final startAngle =
          -pi / 2 +
          rotation +
          (
            index *
            segmentAngle
          );

      final selected =
          selectedReward ==
          reward;

      final segmentPaint =
          Paint()
            ..style =
                PaintingStyle.fill
            ..color =
                _segmentColors[
                  index %
                      _segmentColors
                          .length
                ].withOpacity(
                  selected
                      ? 1
                      : 0.86,
                );

      canvas.drawArc(
        wheelRect,
        startAngle,
        segmentAngle,
        true,
        segmentPaint,
      );

      final separatorPaint =
          Paint()
            ..style =
                PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white
                .withOpacity(
              0.30,
            );

      canvas.drawLine(
        center,
        Offset(
          center.dx +
              cos(
                startAngle,
              ) *
              radius,
          center.dy +
              sin(
                startAngle,
              ) *
              radius,
        ),
        separatorPaint,
      );

      final textAngle =
          startAngle +
          segmentAngle / 2;

      final textPosition =
          Offset(
        center.dx +
            cos(
              textAngle,
            ) *
            radius *
            0.62,
        center.dy +
            sin(
              textAngle,
            ) *
            radius *
            0.62,
      );

      final textPainter =
          TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text:
                  '+$reward\n',
              style:
                  const TextStyle(
                color:
                    Colors.white,
                fontSize: 17,
                fontWeight:
                    FontWeight.w900,
                shadows: [
                  Shadow(
                    color:
                        Colors.black54,
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
            TextSpan(
              text: 'PTS',
              style: TextStyle(
                color: Colors.white
                    .withOpacity(
                  0.78,
                ),
                fontSize: 8,
                fontWeight:
                    FontWeight.w900,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
        textAlign:
            TextAlign.center,
        textDirection:
            TextDirection.ltr,
      );

      textPainter.layout();

      textPainter.paint(
        canvas,
        Offset(
          textPosition.dx -
              textPainter.width /
                  2,
          textPosition.dy -
              textPainter.height /
                  2,
        ),
      );
    }

    final outerBorderPaint =
        Paint()
          ..style =
              PaintingStyle.stroke
          ..strokeWidth = 7
          ..color =
              const Color(
            0xFFFFC857,
          );

    canvas.drawCircle(
      center,
      radius,
      outerBorderPaint,
    );

    final innerBorderPaint =
        Paint()
          ..style =
              PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white
              .withOpacity(
            0.56,
          );

    canvas.drawCircle(
      center,
      radius - 7,
      innerBorderPaint,
    );

    final hubShadow =
        Paint()
          ..color = Colors.black
              .withOpacity(
            0.38,
          )
          ..maskFilter =
              const MaskFilter.blur(
            BlurStyle.normal,
            7,
          );

    canvas.drawCircle(
      center.translate(
        0,
        4,
      ),
      radius * 0.18,
      hubShadow,
    );

    final hubPaint =
        Paint()
          ..shader =
              const LinearGradient(
            colors: [
              Color(
                0xFFFFE39A,
              ),
              Color(
                0xFFFF9F43,
              ),
            ],
          ).createShader(
            Rect.fromCircle(
              center: center,
              radius:
                  radius * 0.18,
            ),
          );

    canvas.drawCircle(
      center,
      radius * 0.18,
      hubPaint,
    );

    final hubBorder =
        Paint()
          ..style =
              PaintingStyle.stroke
          ..strokeWidth = 3
          ..color =
              Colors.white;

    canvas.drawCircle(
      center,
      radius * 0.18,
      hubBorder,
    );

    final centerIcon =
        TextPainter(
      text:
          const TextSpan(
        text: 'H',
        style:
            TextStyle(
          color: Color(
            0xFF2A1600,
          ),
          fontSize: 24,
          fontWeight:
              FontWeight.w900,
        ),
      ),
      textDirection:
          TextDirection.ltr,
    );

    centerIcon.layout();

    centerIcon.paint(
      canvas,
      Offset(
        center.dx -
            centerIcon.width / 2,
        center.dy -
            centerIcon.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(
    covariant
        _DailyWheelPainter
        oldDelegate,
  ) {
    return oldDelegate.rotation !=
            rotation ||
        oldDelegate.selectedReward !=
            selectedReward ||
        oldDelegate.rewards !=
            rewards;
  }
}

// ================= FIN PARTIE 8/8 ====================