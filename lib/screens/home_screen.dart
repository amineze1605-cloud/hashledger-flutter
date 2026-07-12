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

  int _selectedIndex = 0;
  late int _points;

  bool _miningLoading = false;
  bool _claimLoading = false;
  bool _dailyStatusLoading = false;

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
    if (_chestClaimed) {
      return 'Coffre du jour réclamé. Continue à miner pour préparer ton prochain niveau.';
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

      return 'Encore $remaining points à gagner pour terminer ta mission quotidienne.';
    }

    if (levelData.xpToNext <= 100) {
      return 'Plus que ${levelData.xpToNext} XP avant le niveau ${levelData.level + 1}.';
    }

    return 'Tes objectifs avancent bien. Garde ta série active demain.';
  }

  void _showComingSoon(
    String feature,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$feature sera bientôt disponible.',
        ),
        backgroundColor:
            const Color(0xFF111827),
        behavior:
            SnackBarBehavior.floating,
      ),
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

        final chestClaimed =
            data['chest_claimed'] == true;

        final canClaim =
            data['can_claim'] == true;

        final points =
            _asInt(
                  data['points'],
                ) ??
                _points;

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
          _chestMessage =
              data['error']?.toString() ??
              'Impossible de charger le coffre.';
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

        _todayPointsEarned += max(
          reward,
          0,
        );

        await _saveTodayPoints();

        if (!mounted) return;

        setState(() {
          _points = newTotal;
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

        final cooldown =
            _asInt(
                  data['cooldown_seconds'],
                ) ??
                _asInt(
                  data['cooldownSeconds'],
                ) ??
                30;

        _todayMines = sessionsToday;

        _todayPointsEarned += max(
          reward,
          0,
        );

        await _saveTodayMines();
        await _saveTodayPoints();

        if (!mounted) return;

        setState(() {
          _points = newTotal;
          _todayMines = sessionsToday;

          _canClaimChest =
              _todayMines >= _chestTarget &&
              !_chestClaimed;

          _message = reward > 0
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
      decoration: const BoxDecoration(
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

// ================= FIN PARTIE 2/8 ====================
// ==================== PARTIE 3/8 ====================

  Widget _buildCompactHeader(
    _LevelData levelData,
    _LeagueData leagueData,
  ) {
    return Container(
      padding: const EdgeInsets.all(
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
        borderRadius: BorderRadius.circular(
          24,
        ),
        border: Border.all(
          color: leagueData.color.withOpacity(
            0.30,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              0.24,
            ),
            blurRadius: 22,
            offset: const Offset(
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
                decoration: BoxDecoration(
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
                child: const Icon(
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
                      CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'HashLedger',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight:
                            FontWeight.w900,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(
                      height: 3,
                    ),
                    Text(
                      widget.user.email,
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white
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
                    const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color:
                      leagueData.color.withOpacity(
                    0.12,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    16,
                  ),
                  border: Border.all(
                    color: leagueData.color
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
                            FontWeight.w900,
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
                  value: '$_points pts',
                  color: const Color(
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
                  color: const Color(
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
                  color: const Color(
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
                style: const TextStyle(
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
            child: LinearProgressIndicator(
              value: levelData.progress,
              minHeight: 8,
              backgroundColor:
                  Colors.white.withOpacity(
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
    final chestReady =
        _canClaimChest ||
        _chestClaimed;

    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: chestReady
            ? const Color(
                0xFFFFC857,
              ).withOpacity(
                0.09,
              )
            : const Color(
                0xFF7C5CFF,
              ).withOpacity(
                0.09,
              ),
        borderRadius:
            BorderRadius.circular(
          18,
        ),
        border: Border.all(
          color: chestReady
              ? const Color(
                  0xFFFFC857,
                ).withOpacity(
                  0.28,
                )
              : const Color(
                  0xFF7C5CFF,
                ).withOpacity(
                  0.24,
                ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            chestReady
                ? Icons
                    .card_giftcard_rounded
                : Icons
                    .auto_awesome_rounded,
            color: chestReady
                ? const Color(
                    0xFFFFC857,
                  )
                : const Color(
                    0xFF9D8AFF,
                  ),
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
              style: const TextStyle(
                color: Colors.white,
                fontWeight:
                    FontWeight.w800,
                fontSize: 13,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiningCard() {
    final canMine =
        !_miningLoading &&
        _cooldownLeft <= 0;

    return _SoftCard(
      padding:
          const EdgeInsets.all(
        15,
      ),
      child: Column(
        children: [
          Row(
            children: [
              _IconBubble(
                icon:
                    Icons.bolt_rounded,
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
                decoration:
                    BoxDecoration(
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
              decoration:
                  BoxDecoration(
                color:
                    Colors.white.withOpacity(
                  0.05,
                ),
                borderRadius:
                    BorderRadius.circular(
                  13,
                ),
              ),
              child: Text(
                _message!,
                style:
                    const TextStyle(
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
                style:
                    const TextStyle(
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

// ================= FIN PARTIE 3/8 ====================
// ==================== PARTIE 4/8 ====================

  Widget _buildDailyChest() {
    final current = min(
      _todayMines,
      _chestTarget,
    );

    final progress = _chestTarget <= 0
        ? 0.0
        : (current / _chestTarget)
            .clamp(0.0, 1.0)
            .toDouble();

    final unlocked =
        _todayMines >= _chestTarget;

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
      padding:
          const EdgeInsets.all(
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
                decoration:
                    BoxDecoration(
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
                  style:
                      const TextStyle(
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
              decoration:
                  BoxDecoration(
                color:
                    Colors.white.withOpacity(
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
                style:
                    const TextStyle(
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
      (completed) => completed,
    ).length;

    return _SoftCard(
      padding:
          const EdgeInsets.all(
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
                style:
                    const TextStyle(
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
            title:
                'Premier minage',
            reward:
                'bonus bientôt',
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
              icon: Icons
                  .history_rounded,
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
                  'NOUVEAU',
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
                            CrossAxisAlignment
                                .start,
                        children: [
                          Text(
                            'Ligue ${leagueData.name}',
                            style:
                                const TextStyle(
                              color:
                                  Colors.white,
                              fontWeight:
                                  FontWeight
                                      .w900,
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
                              color: Colors
                                  .white
                                  .withOpacity(
                                0.52,
                              ),
                              fontSize:
                                  11.5,
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
                      '1 tour gratuit',
                  badge:
                      'Bientôt',
                  color: const Color(
                    0xFFFF7B54,
                  ),
                  onTap: () {
                    _showComingSoon(
                      'La roue quotidienne',
                    );
                  },
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
              color: Colors.white.withOpacity(
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
                      ? 'Série de 7 jours terminée. Le bonus serveur sera ajouté plus tard.'
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
                color:
                    Colors.white.withOpacity(
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
                          CrossAxisAlignment
                              .start,
                      children: [
                        const Text(
                          'Succès',
                          style:
                              TextStyle(
                            color:
                                Colors.white,
                            fontWeight:
                                FontWeight
                                    .w900,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(
                          height: 3,
                        ),
                        Text(
                          '$achievementCount succès débloqué${achievementCount > 1 ? 's' : ''} sur 5',
                          style: TextStyle(
                            color: Colors
                                .white
                                .withOpacity(
                              0.50,
                            ),
                            fontSize:
                                11.5,
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
                          CrossAxisAlignment
                              .start,
                      children: [
                        Text(
                          'Mini-jeux',
                          style:
                              TextStyle(
                            color:
                                Colors.white,
                            fontWeight:
                                FontWeight
                                    .w900,
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
                            fontSize:
                                11.5,
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
                            FontWeight
                                .w900,
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
                        CrossAxisAlignment
                            .start,
                    children: [
                      const Text(
                        'Objectif retrait',
                        style:
                            TextStyle(
                          color:
                              Colors.white,
                          fontSize: 17,
                          fontWeight:
                              FontWeight
                                  .w900,
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
                          color: Colors
                              .white
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
      color: const Color(
        0xFF05070C,
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
            16,
            16,
            26,
          ),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      Text(
                        'Historique',
                        style: TextStyle(
                          color:
                              Colors.white,
                          fontSize: 28,
                          fontWeight:
                              FontWeight
                                  .w900,
                          letterSpacing:
                              -0.6,
                        ),
                      ),
                      SizedBox(
                        height: 4,
                      ),
                      Text(
                        'Toutes tes récompenses',
                        style: TextStyle(
                          color: Color(
                            0xFF9097A6,
                          ),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed:
                      _historyLoading
                          ? null
                          : _loadHistory,
                  icon: const Icon(
                    Icons
                        .refresh_rounded,
                    color: Colors.white,
                  ),
                ),
              ],
            ),

            const SizedBox(
              height: 16,
            ),

            _SoftCard(
              padding:
                  const EdgeInsets.all(
                15,
              ),
              child: Row(
                children: [
                  Expanded(
                    child:
                        _HistoryStat(
                      icon:
                          Icons.toll_rounded,
                      label: 'Solde',
                      value:
                          '$_points pts',
                      color: const Color(
                        0xFF2DE2A6,
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 42,
                    color: Colors.white
                        .withOpacity(
                      0.07,
                    ),
                  ),
                  Expanded(
                    child:
                        _HistoryStat(
                      icon: Icons
                          .receipt_long_rounded,
                      label: 'Activités',
                      value:
                          '${_history.length}',
                      color: const Color(
                        0xFF55D6FF,
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 42,
                    color: Colors.white
                        .withOpacity(
                      0.07,
                    ),
                  ),
                  Expanded(
                    child:
                        _HistoryStat(
                      icon: Icons
                          .calendar_today_rounded,
                      label:
                          'Aujourd’hui',
                      value:
                          '$_todayMines',
                      color: const Color(
                        0xFFFFC857,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(
              height: 14,
            ),

            if (_historyLoading)
              const Center(
                child: Padding(
                  padding:
                      EdgeInsets.only(
                    top: 40,
                  ),
                  child:
                      CircularProgressIndicator(
                    color: Color(
                      0xFF2DE2A6,
                    ),
                  ),
                ),
              )
            else if (
                _historyError != null)
              _SoftCard(
                padding:
                    const EdgeInsets.all(
                  16,
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons
                          .cloud_off_rounded,
                      color: Color(
                        0xFFFF7B54,
                      ),
                      size: 32,
                    ),
                    const SizedBox(
                      height: 10,
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
                            FontWeight
                                .w800,
                      ),
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    TextButton.icon(
                      onPressed:
                          _loadHistory,
                      icon: const Icon(
                        Icons
                            .refresh_rounded,
                      ),
                      label: const Text(
                        'Réessayer',
                      ),
                      style:
                          TextButton.styleFrom(
                        foregroundColor:
                            const Color(
                          0xFF2DE2A6,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (
                _history.isEmpty)
              _SoftCard(
                padding:
                    const EdgeInsets.all(
                  18,
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons
                          .history_toggle_off_rounded,
                      color: Colors.white
                          .withOpacity(
                        0.35,
                      ),
                      size: 38,
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    const Text(
                      'Aucune activité',
                      style:
                          TextStyle(
                        color:
                            Colors.white,
                        fontSize: 16,
                        fontWeight:
                            FontWeight
                                .w900,
                      ),
                    ),
                    const SizedBox(
                      height: 5,
                    ),
                    Text(
                      'Lance une session de minage pour créer ta première entrée.',
                      textAlign:
                          TextAlign.center,
                      style: TextStyle(
                        color: Colors
                            .white
                            .withOpacity(
                          0.50,
                        ),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              )
            else
              ..._history.map(
                (
                  entry,
                ) {
                  final isChest =
                      entry.type ==
                          'daily_chest';

                  final color =
                      isChest
                          ? const Color(
                              0xFFFFC857,
                            )
                          : const Color(
                              0xFF2DE2A6,
                            );

                  return Padding(
                    padding:
                        const EdgeInsets
                            .only(
                      bottom: 9,
                    ),
                    child: _SoftCard(
                      padding:
                          const EdgeInsets
                              .all(
                        14,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration:
                                BoxDecoration(
                              color: color
                                  .withOpacity(
                                0.10,
                              ),
                              borderRadius:
                                  BorderRadius
                                      .circular(
                                15,
                              ),
                              border:
                                  Border.all(
                                color: color
                                    .withOpacity(
                                  0.25,
                                ),
                              ),
                            ),
                            child: Icon(
                              isChest
                                  ? Icons
                                      .card_giftcard_rounded
                                  : Icons
                                      .bolt_rounded,
                              color: color,
                              size: 22,
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
                                  entry.description
                                          .isNotEmpty
                                      ? entry
                                          .description
                                      : isChest
                                          ? 'Coffre quotidien'
                                          : 'Session de minage',
                                  style:
                                      const TextStyle(
                                    color:
                                        Colors.white,
                                    fontWeight:
                                        FontWeight
                                            .w900,
                                    fontSize:
                                        14,
                                  ),
                                ),
                                const SizedBox(
                                  height: 4,
                                ),
                                Text(
                                  entry.dateLabel,
                                  style:
                                      TextStyle(
                                    color: Colors
                                        .white
                                        .withOpacity(
                                      0.48,
                                    ),
                                    fontSize:
                                        11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding:
                                const EdgeInsets
                                    .symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration:
                                BoxDecoration(
                              color: color
                                  .withOpacity(
                                0.09,
                              ),
                              borderRadius:
                                  BorderRadius
                                      .circular(
                                16,
                              ),
                            ),
                            child: Text(
                              '+${entry.reward}',
                              style:
                                  TextStyle(
                                color: color,
                                fontWeight:
                                    FontWeight
                                        .w900,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWithdrawPage() {
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

    final percent =
        (progress * 100).floor();

    final canRequestWithdraw =
        _points >= _withdrawTarget;

    return Container(
      color: const Color(
        0xFF05070C,
      ),
      child: ListView(
        padding:
            const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          26,
        ),
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    Text(
                      'Retrait',
                      style: TextStyle(
                        color:
                            Colors.white,
                        fontSize: 28,
                        fontWeight:
                            FontWeight
                                .w900,
                        letterSpacing:
                            -0.6,
                      ),
                    ),
                    SizedBox(
                      height: 4,
                    ),
                    Text(
                      'Prépare ton premier retrait',
                      style: TextStyle(
                        color: Color(
                          0xFF9097A6,
                        ),
                        fontSize: 13,
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
                  vertical: 7,
                ),
                decoration:
                    BoxDecoration(
                  color: const Color(
                    0xFFFFC857,
                  ).withOpacity(
                    0.10,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    20,
                  ),
                  border: Border.all(
                    color: const Color(
                      0xFFFFC857,
                    ).withOpacity(
                      0.28,
                    ),
                  ),
                ),
                child: const Text(
                  'BIENTÔT',
                  style: TextStyle(
                    color: Color(
                      0xFFFFC857,
                    ),
                    fontWeight:
                        FontWeight.w900,
                    fontSize: 10,
                    letterSpacing:
                        0.5,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 16,
          ),

          Container(
            padding:
                const EdgeInsets.all(
              18,
            ),
            decoration: BoxDecoration(
              gradient:
                  const LinearGradient(
                begin:
                    Alignment.topLeft,
                end:
                    Alignment.bottomRight,
                colors: [
                  Color(
                    0xFF15253A,
                  ),
                  Color(
                    0xFF0C1726,
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
              boxShadow: [
                BoxShadow(
                  color: Colors.black
                      .withOpacity(
                    0.26,
                  ),
                  blurRadius: 22,
                  offset: const Offset(
                    0,
                    13,
                  ),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 45,
                      height: 45,
                      decoration:
                          BoxDecoration(
                        color: const Color(
                          0xFF55D6FF,
                        ).withOpacity(
                          0.12,
                        ),
                        borderRadius:
                            BorderRadius
                                .circular(
                          15,
                        ),
                      ),
                      child: const Icon(
                        Icons
                            .account_balance_wallet_rounded,
                        color: Color(
                          0xFF55D6FF,
                        ),
                        size: 23,
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
                            'Solde disponible',
                            style:
                                TextStyle(
                              color: Colors
                                  .white
                                  .withOpacity(
                                0.52,
                              ),
                              fontSize: 12,
                              fontWeight:
                                  FontWeight
                                      .w700,
                            ),
                          ),
                          const SizedBox(
                            height: 3,
                          ),
                          Text(
                            '$_points points',
                            style:
                                const TextStyle(
                              color:
                                  Colors.white,
                              fontSize: 28,
                              fontWeight:
                                  FontWeight
                                      .w900,
                              letterSpacing:
                                  -0.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(
                  height: 18,
                ),

                Row(
                  children: [
                    const Text(
                      'Premier objectif',
                      style:
                          TextStyle(
                        color:
                            Colors.white,
                        fontWeight:
                            FontWeight
                                .w900,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$percent%',
                      style:
                          const TextStyle(
                        color: Color(
                          0xFF55D6FF,
                        ),
                        fontWeight:
                            FontWeight
                                .w900,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),

                const SizedBox(
                  height: 9,
                ),

                ClipRRect(
                  borderRadius:
                      BorderRadius.circular(
                    50,
                  ),
                  child:
                      LinearProgressIndicator(
                    value: progress,
                    minHeight: 11,
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
                      '$_points pts',
                      style: TextStyle(
                        color: Colors
                            .white
                            .withOpacity(
                          0.48,
                        ),
                        fontSize: 11.5,
                        fontWeight:
                            FontWeight
                                .w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$_withdrawTarget pts',
                      style: TextStyle(
                        color: Colors
                            .white
                            .withOpacity(
                          0.48,
                        ),
                        fontSize: 11.5,
                        fontWeight:
                            FontWeight
                                .w700,
                      ),
                    ),
                  ],
                ),

                const SizedBox(
                  height: 15,
                ),

                Container(
                  width:
                      double.infinity,
                  padding:
                      const EdgeInsets
                          .all(
                    13,
                  ),
                  decoration:
                      BoxDecoration(
                    color: Colors.white
                        .withOpacity(
                      0.045,
                    ),
                    borderRadius:
                        BorderRadius
                            .circular(
                      16,
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
                      Icon(
                        canRequestWithdraw
                            ? Icons
                                .check_circle_rounded
                            : Icons
                                .lock_clock_rounded,
                        color:
                            canRequestWithdraw
                                ? const Color(
                                    0xFF2DE2A6,
                                  )
                                : const Color(
                                    0xFF55D6FF,
                                  ),
                        size: 23,
                      ),
                      const SizedBox(
                        width: 10,
                      ),
                      Expanded(
                        child: Text(
                          canRequestWithdraw
                              ? 'Objectif atteint. Le formulaire sera activé plus tard.'
                              : 'Encore $remaining points avant de débloquer la demande.',
                          style:
                              const TextStyle(
                            color:
                                Colors.white,
                            fontWeight:
                                FontWeight
                                    .w800,
                            fontSize:
                                12.5,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

// ================= FIN PARTIE 6/8 ====================
// ==================== PARTIE 7/8 ====================

          const SizedBox(
            height: 14,
          ),

          _SoftCard(
            padding:
                const EdgeInsets.all(
              15,
            ),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                _sectionTitle(
                  title:
                      'Destination du retrait',
                  subtitle:
                      'Configuration préparée pour les futurs retraits crypto.',
                  icon:
                      Icons.send_rounded,
                  color: const Color(
                    0xFF2DE2A6,
                  ),
                ),

                const SizedBox(
                  height: 16,
                ),

                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding:
                            const EdgeInsets
                                .all(
                          13,
                        ),
                        decoration:
                            BoxDecoration(
                          color: Colors.white
                              .withOpacity(
                            0.04,
                          ),
                          borderRadius:
                              BorderRadius
                                  .circular(
                            17,
                          ),
                          border:
                              Border.all(
                            color: Colors
                                .white
                                .withOpacity(
                              0.07,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: [
                            Text(
                              'Crypto',
                              style:
                                  TextStyle(
                                color: Colors
                                    .white
                                    .withOpacity(
                                  0.48,
                                ),
                                fontSize: 11,
                                fontWeight:
                                    FontWeight
                                        .w700,
                              ),
                            ),
                            const SizedBox(
                              height: 8,
                            ),
                            const Row(
                              children: [
                                Icon(
                                  Icons
                                      .monetization_on_rounded,
                                  color: Color(
                                    0xFF2DE2A6,
                                  ),
                                  size: 20,
                                ),
                                SizedBox(
                                  width: 7,
                                ),
                                Expanded(
                                  child: Text(
                                    'USDT',
                                    style:
                                        TextStyle(
                                      color: Colors
                                          .white,
                                      fontWeight:
                                          FontWeight
                                              .w900,
                                      fontSize:
                                          14,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons
                                      .keyboard_arrow_down_rounded,
                                  color: Color(
                                    0xFF697180,
                                  ),
                                  size: 20,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(
                      width: 10,
                    ),

                    Expanded(
                      child: Container(
                        padding:
                            const EdgeInsets
                                .all(
                          13,
                        ),
                        decoration:
                            BoxDecoration(
                          color: Colors.white
                              .withOpacity(
                            0.04,
                          ),
                          borderRadius:
                              BorderRadius
                                  .circular(
                            17,
                          ),
                          border:
                              Border.all(
                            color: Colors
                                .white
                                .withOpacity(
                              0.07,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: [
                            Text(
                              'Réseau',
                              style:
                                  TextStyle(
                                color: Colors
                                    .white
                                    .withOpacity(
                                  0.48,
                                ),
                                fontSize: 11,
                                fontWeight:
                                    FontWeight
                                        .w700,
                              ),
                            ),
                            const SizedBox(
                              height: 8,
                            ),
                            const Row(
                              children: [
                                Icon(
                                  Icons
                                      .hub_rounded,
                                  color: Color(
                                    0xFF55D6FF,
                                  ),
                                  size: 20,
                                ),
                                SizedBox(
                                  width: 7,
                                ),
                                Expanded(
                                  child: Text(
                                    'TRC20',
                                    style:
                                        TextStyle(
                                      color: Colors
                                          .white,
                                      fontWeight:
                                          FontWeight
                                              .w900,
                                      fontSize:
                                          14,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons
                                      .keyboard_arrow_down_rounded,
                                  color: Color(
                                    0xFF697180,
                                  ),
                                  size: 20,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(
                  height: 15,
                ),

                Text(
                  'Adresse du wallet',
                  style: TextStyle(
                    color: Colors.white
                        .withOpacity(
                      0.60,
                    ),
                    fontWeight:
                        FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),

                const SizedBox(
                  height: 8,
                ),

                TextField(
                  enabled: false,
                  style:
                      const TextStyle(
                    color: Colors.white,
                  ),
                  decoration:
                      InputDecoration(
                    hintText:
                        'Adresse du wallet USDT TRC20',
                    hintStyle:
                        TextStyle(
                      color: Colors.white
                          .withOpacity(
                        0.30,
                      ),
                      fontSize: 12.5,
                    ),
                    filled: true,
                    fillColor: Colors.white
                        .withOpacity(
                      0.04,
                    ),
                    prefixIcon: Icon(
                      Icons
                          .account_balance_wallet_rounded,
                      color: Colors.white
                          .withOpacity(
                        0.34,
                      ),
                    ),
                    border:
                        OutlineInputBorder(
                      borderRadius:
                          BorderRadius
                              .circular(
                        17,
                      ),
                      borderSide:
                          BorderSide.none,
                    ),
                    disabledBorder:
                        OutlineInputBorder(
                      borderRadius:
                          BorderRadius
                              .circular(
                        17,
                      ),
                      borderSide:
                          BorderSide(
                        color: Colors
                            .white
                            .withOpacity(
                          0.07,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(
                  height: 14,
                ),

                Text(
                  'Montant demandé',
                  style: TextStyle(
                    color: Colors.white
                        .withOpacity(
                      0.60,
                    ),
                    fontWeight:
                        FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),

                const SizedBox(
                  height: 8,
                ),

                TextField(
                  enabled: false,
                  keyboardType:
                      TextInputType.number,
                  style:
                      const TextStyle(
                    color: Colors.white,
                  ),
                  decoration:
                      InputDecoration(
                    hintText:
                        'Minimum $_withdrawTarget points',
                    hintStyle:
                        TextStyle(
                      color: Colors.white
                          .withOpacity(
                        0.30,
                      ),
                      fontSize: 12.5,
                    ),
                    filled: true,
                    fillColor: Colors.white
                        .withOpacity(
                      0.04,
                    ),
                    prefixIcon: Icon(
                      Icons.toll_rounded,
                      color: Colors.white
                          .withOpacity(
                        0.34,
                      ),
                    ),
                    suffixText:
                        'points',
                    suffixStyle:
                        TextStyle(
                      color: Colors.white
                          .withOpacity(
                        0.38,
                      ),
                      fontWeight:
                          FontWeight.w800,
                      fontSize: 12,
                    ),
                    border:
                        OutlineInputBorder(
                      borderRadius:
                          BorderRadius
                              .circular(
                        17,
                      ),
                      borderSide:
                          BorderSide.none,
                    ),
                    disabledBorder:
                        OutlineInputBorder(
                      borderRadius:
                          BorderRadius
                              .circular(
                        17,
                      ),
                      borderSide:
                          BorderSide(
                        color: Colors
                            .white
                            .withOpacity(
                          0.07,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(
                  height: 15,
                ),

                Container(
                  padding:
                      const EdgeInsets.all(
                    13,
                  ),
                  decoration:
                      BoxDecoration(
                    color: const Color(
                      0xFF55D6FF,
                    ).withOpacity(
                      0.055,
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      17,
                    ),
                    border: Border.all(
                      color: const Color(
                        0xFF55D6FF,
                      ).withOpacity(
                        0.16,
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Text(
                            'Valeur estimée',
                            style:
                                TextStyle(
                              color: Colors
                                  .white
                                  .withOpacity(
                                0.50,
                              ),
                              fontSize: 12,
                              fontWeight:
                                  FontWeight
                                      .w700,
                            ),
                          ),
                          const Spacer(),
                          const Text(
                            'Calculée plus tard',
                            style:
                                TextStyle(
                              color: Color(
                                0xFF55D6FF,
                              ),
                              fontSize: 12,
                              fontWeight:
                                  FontWeight
                                      .w900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(
                        height: 10,
                      ),
                      Row(
                        children: [
                          Text(
                            'Frais de réseau',
                            style:
                                TextStyle(
                              color: Colors
                                  .white
                                  .withOpacity(
                                0.50,
                              ),
                              fontSize: 12,
                              fontWeight:
                                  FontWeight
                                      .w700,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Affichés avant validation',
                            style:
                                TextStyle(
                              color: Colors
                                  .white
                                  .withOpacity(
                                0.72,
                              ),
                              fontSize: 12,
                              fontWeight:
                                  FontWeight
                                      .w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(
                  height: 15,
                ),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child:
                      ElevatedButton.icon(
                    onPressed: null,
                    icon: Icon(
                      canRequestWithdraw
                          ? Icons
                              .send_rounded
                          : Icons
                              .lock_rounded,
                      size: 20,
                    ),
                    label: Text(
                      canRequestWithdraw
                          ? 'Retrait bientôt disponible'
                          : 'Solde minimum non atteint',
                      style:
                          const TextStyle(
                        fontWeight:
                            FontWeight
                                .w900,
                        fontSize: 13.5,
                      ),
                    ),
                    style:
                        ElevatedButton
                            .styleFrom(
                      disabledBackgroundColor:
                          canRequestWithdraw
                              ? const Color(
                                  0xFF2DE2A6,
                                ).withOpacity(
                                  0.12,
                                )
                              : Colors
                                  .white
                                  .withOpacity(
                                    0.055,
                                  ),
                      disabledForegroundColor:
                          canRequestWithdraw
                              ? const Color(
                                  0xFF2DE2A6,
                                )
                              : Colors
                                  .white
                                  .withOpacity(
                                    0.34,
                                  ),
                      elevation: 0,
                      shape:
                          RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius
                                .circular(
                          16,
                        ),
                      ),
                    ),
                  ),
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
              15,
            ),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                _sectionTitle(
                  title:
                      'Sécurité et conditions',
                  subtitle:
                      'Chaque demande sera contrôlée avant son envoi.',
                  icon: Icons
                      .verified_user_rounded,
                  color: const Color(
                    0xFFFFC857,
                  ),
                ),

                const SizedBox(
                  height: 13,
                ),

                _WithdrawRuleLine(
                  icon:
                      Icons.flag_rounded,
                  title:
                      'Minimum de retrait',
                  value:
                      '10 000 points',
                  active: _points >=
                      _withdrawTarget,
                ),

                _WithdrawRuleLine(
                  icon: Icons
                      .account_balance_wallet_rounded,
                  title:
                      'Adresse wallet valide',
                  value:
                      'Obligatoire',
                  active: false,
                ),

                const _WithdrawRuleLine(
                  icon: Icons
                      .security_rounded,
                  title:
                      'Contrôle anti-fraude',
                  value:
                      'Automatique',
                  active: true,
                ),

                const _WithdrawRuleLine(
                  icon:
                      Icons.timer_rounded,
                  title:
                      'Délai de traitement',
                  value:
                      '24 à 72 h',
                  active: true,
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
              15,
            ),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                _sectionTitle(
                  title:
                      'Historique des retraits',
                  subtitle:
                      'Suis ici le statut de tes futures demandes.',
                  icon: Icons
                      .receipt_long_rounded,
                  color: const Color(
                    0xFF9D8AFF,
                  ),
                ),

                const SizedBox(
                  height: 16,
                ),

                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.all(
                    17,
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
                        0.065,
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons
                            .hourglass_empty_rounded,
                        color: Colors.white
                            .withOpacity(
                          0.28,
                        ),
                        size: 31,
                      ),
                      const SizedBox(
                        height: 9,
                      ),
                      const Text(
                        'Aucune demande',
                        style:
                            TextStyle(
                          color:
                              Colors.white,
                          fontWeight:
                              FontWeight
                                  .w900,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(
                        height: 5,
                      ),
                      Text(
                        'Tes retraits apparaîtront ici avec leur statut.',
                        textAlign:
                            TextAlign.center,
                        style: TextStyle(
                          color: Colors
                              .white
                              .withOpacity(
                            0.46,
                          ),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
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
    final levelData =
        _calculateLevel(
      _points,
    );

    final leagueData =
        _calculateLeague(
      _points,
    );

    final achievementCount =
        _achievementCount(
      levelData,
    );

    final leagueProgress =
        leagueData.progressFor(
      _points,
    );

    final initial =
        widget.user.email.isNotEmpty
            ? widget.user.email[0]
                .toUpperCase()
            : 'H';

    return Container(
      color: const Color(
        0xFF05070C,
      ),
      child: ListView(
        padding:
            const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          26,
        ),
        children: [
          const Text(
            'Profil',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight:
                  FontWeight.w900,
              letterSpacing: -0.6,
            ),
          ),

          const SizedBox(
            height: 16,
          ),

          Container(
            padding:
                const EdgeInsets.all(
              18,
            ),
            decoration:
                BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(
                    0xFF151D31,
                  ),
                  leagueData.color
                      .withOpacity(
                    0.10,
                  ),
                ],
              ),
              borderRadius:
                  BorderRadius.circular(
                25,
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
                    Container(
                      width: 58,
                      height: 58,
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
                            BorderRadius
                                .circular(
                          20,
                        ),
                      ),
                      alignment:
                          Alignment.center,
                      child: Text(
                        initial,
                        style:
                            const TextStyle(
                          color: Color(
                            0xFF04110D,
                          ),
                          fontSize: 25,
                          fontWeight:
                              FontWeight
                                  .w900,
                        ),
                      ),
                    ),

                    const SizedBox(
                      width: 13,
                    ),

                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          const Text(
                            'Mineur HashLedger',
                            style:
                                TextStyle(
                              color:
                                  Colors.white,
                              fontSize: 18,
                              fontWeight:
                                  FontWeight
                                      .w900,
                            ),
                          ),
                          const SizedBox(
                            height: 4,
                          ),
                          Text(
                            widget.user.email,
                            maxLines: 1,
                            overflow:
                                TextOverflow
                                    .ellipsis,
                            style:
                                TextStyle(
                              color: Colors
                                  .white
                                  .withOpacity(
                                0.50,
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
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration:
                          BoxDecoration(
                        color: leagueData
                            .color
                            .withOpacity(
                          0.11,
                        ),
                        borderRadius:
                            BorderRadius
                                .circular(
                          16,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            leagueData.icon,
                            color:
                                leagueData
                                    .color,
                            size: 19,
                          ),
                          const SizedBox(
                            height: 3,
                          ),
                          Text(
                            leagueData.name,
                            style:
                                TextStyle(
                              color:
                                  leagueData
                                      .color,
                              fontWeight:
                                  FontWeight
                                      .w900,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(
                  height: 17,
                ),

                Row(
                  children: [
                    Text(
                      'Niveau ${levelData.level}',
                      style: TextStyle(
                        color: Colors.white
                            .withOpacity(
                          0.70,
                        ),
                        fontWeight:
                            FontWeight
                                .w800,
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
                            FontWeight
                                .w900,
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
          ),

          const SizedBox(
            height: 14,
          ),

          _SoftCard(
            padding:
                const EdgeInsets.all(
              15,
            ),
            child: Row(
              children: [
                Expanded(
                  child: _HeaderStat(
                    icon:
                        Icons.toll_rounded,
                    label: 'Points',
                    value: '$_points',
                    color: const Color(
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
                        .local_fire_department_rounded,
                    label: 'Série',
                    value:
                        '$_loginStreak j',
                    color: const Color(
                      0xFFFF7B54,
                    ),
                  ),
                ),
                const SizedBox(
                  width: 8,
                ),
                Expanded(
                  child: _HeaderStat(
                    icon: Icons
                        .emoji_events_rounded,
                    label: 'Succès',
                    value:
                        '$achievementCount/5',
                    color: const Color(
                      0xFFFFC857,
                    ),
                  ),
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
              15,
            ),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                _sectionTitle(
                  title:
                      'Progression du compte',
                  subtitle:
                      'Résumé de ton activité HashLedger.',
                  icon:
                      Icons.insights_rounded,
                  color: const Color(
                    0xFF55D6FF,
                  ),
                ),

                const SizedBox(
                  height: 13,
                ),

                _ProfileLine(
                  label:
                      'Niveau actuel',
                  value:
                      '${levelData.level}',
                ),

                _ProfileLine(
                  label:
                      'Prochain niveau',
                  value:
                      '${levelData.xpToNext} XP',
                ),

                _ProfileLine(
                  label:
                      'Sessions aujourd’hui',
                  value:
                      '$_todayMines',
                ),

                _ProfileLine(
                  label:
                      'Points gagnés aujourd’hui',
                  value:
                      '$_todayPointsEarned/$_dailyPointsTarget',
                ),

                _ProfileLine(
                  label:
                      'Coffre quotidien',
                  value: _chestClaimed
                      ? 'Réclamé'
                      : '${min(_todayMines, _chestTarget)}/$_chestTarget',
                ),

                _ProfileLine(
                  label:
                      'Historique consulté',
                  value:
                      _historySeenToday
                          ? 'Oui'
                          : 'Non',
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
              15,
            ),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      leagueData.icon,
                      color:
                          leagueData.color,
                      size: 25,
                    ),
                    const SizedBox(
                      width: 10,
                    ),
                    Expanded(
                      child: Text(
                        'Ligue ${leagueData.name}',
                        style:
                            const TextStyle(
                          color:
                              Colors.white,
                          fontSize: 17,
                          fontWeight:
                              FontWeight
                                  .w900,
                        ),
                      ),
                    ),
                    Text(
                      '$_points pts',
                      style: TextStyle(
                        color:
                            leagueData.color,
                        fontWeight:
                            FontWeight
                                .w900,
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
                    minHeight: 9,
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

                const SizedBox(
                  height: 10,
                ),

                Text(
                  '${leagueData.pointsToNext(_points)} points avant la ligue ${leagueData.nextName}.',
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

          const SizedBox(
            height: 14,
          ),

          Container(
            padding:
                const EdgeInsets.all(
              16,
            ),
            decoration:
                BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(
                    0xFF7C5CFF,
                  ).withOpacity(
                    0.15,
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
                22,
              ),
              border: Border.all(
                color: const Color(
                  0xFF7C5CFF,
                ).withOpacity(
                  0.24,
                ),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons
                      .auto_awesome_rounded,
                  color: Color(
                    0xFF9D8AFF,
                  ),
                  size: 29,
                ),
                const SizedBox(
                  width: 12,
                ),
                const Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      Text(
                        'Saison HashLedger',
                        style:
                            TextStyle(
                          color:
                              Colors.white,
                          fontSize: 15,
                          fontWeight:
                              FontWeight
                                  .w900,
                        ),
                      ),
                      SizedBox(
                        height: 4,
                      ),
                      Text(
                        'Défis, badges et récompenses mensuelles bientôt disponibles.',
                        style:
                            TextStyle(
                          color: Color(
                            0xFF9DA4B3,
                          ),
                          fontSize: 11.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(
                  width: 8,
                ),
                const Text(
                  'BIENTÔT',
                  style: TextStyle(
                    color: Color(
                      0xFF9D8AFF,
                    ),
                    fontWeight:
                        FontWeight.w900,
                    fontSize: 9,
                  ),
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
        color: const Color(
          0xFF080B12,
        ),
        border: Border(
          top: BorderSide(
            color: Colors.white
                .withOpacity(
              0.07,
            ),
          ),
        ),
      ),
      child: BottomNavigationBar(
        currentIndex:
            _selectedIndex,
        onTap: _onNavTap,
        type:
            BottomNavigationBarType
                .fixed,
        backgroundColor:
            Colors.transparent,
        elevation: 0,
        selectedItemColor:
            const Color(
          0xFF2DE2A6,
        ),
        unselectedItemColor:
            Colors.white.withOpacity(
          0.36,
        ),
        selectedLabelStyle:
            const TextStyle(
          fontWeight:
              FontWeight.w900,
          fontSize: 11.5,
        ),
        unselectedLabelStyle:
            const TextStyle(
          fontWeight:
              FontWeight.w600,
          fontSize: 11.5,
        ),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(
              Icons.home_rounded,
            ),
            label: 'Accueil',
          ),
          BottomNavigationBarItem(
            icon: Icon(
              Icons.history_rounded,
            ),
            label: 'Historique',
          ),
          BottomNavigationBarItem(
            icon: Icon(
              Icons
                  .account_balance_wallet_rounded,
            ),
            label: 'Retrait',
          ),
          BottomNavigationBarItem(
            icon: Icon(
              Icons.person_rounded,
            ),
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
    Color color =
        const Color(
      0xFF2DE2A6,
    ),
  }) {
    return Row(
      children: [
        _IconBubble(
          icon: icon,
          color: color,
        ),
        const SizedBox(
          width: 11,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style:
                    const TextStyle(
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
                subtitle,
                style: TextStyle(
                  color: Colors.white
                      .withOpacity(
                    0.50,
                  ),
                  fontSize: 11.8,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ================= FIN PARTIE 7/8 ====================
// ==================== PARTIE 8/8 ====================

class _SoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _SoftCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(
          0xFF111827,
        ).withOpacity(
          0.92,
        ),
        borderRadius:
            BorderRadius.circular(
          24,
        ),
        border: Border.all(
          color: Colors.white
              .withOpacity(
            0.075,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withOpacity(
              0.25,
            ),
            blurRadius: 20,
            offset: const Offset(
              0,
              12,
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
      width: 41,
      height: 41,
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
            0.25,
          ),
        ),
      ),
      child: Icon(
        icon,
        color: color,
        size: 21,
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
        horizontal: 9,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(
          0.04,
        ),
        borderRadius:
            BorderRadius.circular(
          15,
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
            style:
                const TextStyle(
              color: Colors.white,
              fontWeight:
                  FontWeight.w900,
              fontSize: 12.5,
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
                0.43,
              ),
              fontWeight:
                  FontWeight.w700,
              fontSize: 9.5,
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
        target <= 0 ? 1 : target;

    final safeCurrent =
        current.clamp(
      0,
      safeTarget,
    );

    final progress =
        (safeCurrent / safeTarget)
            .clamp(
              0.0,
              1.0,
            )
            .toDouble();

    final completed =
        current >= target &&
        target > 0;

    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: completed
            ? const Color(
                0xFF2DE2A6,
              ).withOpacity(
                0.055,
              )
            : Colors.white
                .withOpacity(
                0.03,
              ),
        borderRadius:
            BorderRadius.circular(
          16,
        ),
        border: Border.all(
          color: completed
              ? const Color(
                  0xFF2DE2A6,
                ).withOpacity(
                  0.22,
                )
              : Colors.white
                  .withOpacity(
                  0.06,
                ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 35,
            height: 35,
            decoration:
                BoxDecoration(
              color: completed
                  ? const Color(
                      0xFF2DE2A6,
                    ).withOpacity(
                      0.10,
                    )
                  : color.withOpacity(
                      0.10,
                    ),
              borderRadius:
                  BorderRadius.circular(
                12,
              ),
            ),
            child: Icon(
              completed
                  ? Icons.check_rounded
                  : icon,
              color: completed
                  ? const Color(
                      0xFF2DE2A6,
                    )
                  : color,
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
                    Flexible(
                      child: Text(
                        completed
                            ? 'Terminé'
                            : reward,
                        maxLines: 1,
                        overflow:
                            TextOverflow
                                .ellipsis,
                        textAlign:
                            TextAlign.right,
                        style: TextStyle(
                          color: completed
                              ? const Color(
                                  0xFF2DE2A6,
                                )
                              : Colors
                                  .white
                                  .withOpacity(
                                    0.45,
                                  ),
                          fontWeight:
                              FontWeight
                                  .w800,
                          fontSize: 9.5,
                        ),
                      ),
                    ),
                  ],
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
                      completed
                          ? const Color(
                              0xFF2DE2A6,
                            )
                          : color,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(
            width: 9,
          ),

          Text(
            '$safeCurrent/$safeTarget',
            style: TextStyle(
              color: completed
                  ? const Color(
                      0xFF2DE2A6,
                    )
                  : Colors.white
                      .withOpacity(
                      0.48,
                    ),
              fontWeight:
                  FontWeight.w900,
              fontSize: 10.5,
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
                0.04,
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
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration:
                      BoxDecoration(
                    color:
                        color.withOpacity(
                      0.12,
                    ),
                    borderRadius:
                        BorderRadius
                            .circular(
                      12,
                    ),
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: 20,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets
                          .symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  decoration:
                      BoxDecoration(
                    color:
                        color.withOpacity(
                      0.10,
                    ),
                    borderRadius:
                        BorderRadius
                            .circular(
                      12,
                    ),
                  ),
                  child: Text(
                    badge.toUpperCase(),
                    style: TextStyle(
                      color: color,
                      fontWeight:
                          FontWeight.w900,
                      fontSize: 7.5,
                      letterSpacing:
                          0.3,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(
              height: 11,
            ),

            Text(
              title,
              maxLines: 1,
              overflow:
                  TextOverflow.ellipsis,
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
              subtitle,
              maxLines: 1,
              overflow:
                  TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white
                    .withOpacity(
                  0.46,
                ),
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StreakDay extends StatelessWidget {
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
    final activeColor = isReward
        ? const Color(
            0xFFFFC857,
          )
        : const Color(
            0xFFFF7B54,
          );

    return Column(
      children: [
        Container(
          width: 31,
          height: 31,
          decoration: BoxDecoration(
            color: completed
                ? activeColor
                    .withOpacity(
                    0.15,
                  )
                : Colors.white
                    .withOpacity(
                    0.035,
                  ),
            borderRadius:
                BorderRadius.circular(
              11,
            ),
            border: Border.all(
              color: completed
                  ? activeColor
                      .withOpacity(
                      0.45,
                    )
                  : Colors.white
                      .withOpacity(
                      0.07,
                    ),
            ),
          ),
          child: Icon(
            completed
                ? Icons.check_rounded
                : isReward
                    ? Icons
                        .card_giftcard_rounded
                    : Icons
                        .circle_outlined,
            color: completed
                ? activeColor
                : Colors.white
                    .withOpacity(
                    0.26,
                  ),
            size:
                isReward ? 17 : 15,
          ),
        ),
        const SizedBox(
          height: 5,
        ),
        Text(
          'J$day',
          style: TextStyle(
            color: completed
                ? activeColor
                : Colors.white
                    .withOpacity(
                    0.35,
                  ),
            fontWeight:
                FontWeight.w800,
            fontSize: 8.5,
          ),
        ),
      ],
    );
  }
}

class _HistoryStat
    extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _HistoryStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Column(
      children: [
        Icon(
          icon,
          color: color,
          size: 20,
        ),
        const SizedBox(
          height: 6,
        ),
        Text(
          value,
          maxLines: 1,
          overflow:
              TextOverflow.ellipsis,
          style:
              const TextStyle(
            color: Colors.white,
            fontWeight:
                FontWeight.w900,
            fontSize: 13,
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
              0.42,
            ),
            fontWeight:
                FontWeight.w700,
            fontSize: 9.5,
          ),
        ),
      ],
    );
  }
}

class _WithdrawRuleLine
    extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final bool active;

  const _WithdrawRuleLine({
    required this.icon,
    required this.title,
    required this.value,
    required this.active,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        vertical: 11,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white
                .withOpacity(
              0.055,
            ),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration:
                BoxDecoration(
              color: active
                  ? const Color(
                      0xFF2DE2A6,
                    ).withOpacity(
                      0.09,
                    )
                  : Colors.white
                      .withOpacity(
                      0.035,
                    ),
              borderRadius:
                  BorderRadius.circular(
                11,
              ),
            ),
            child: Icon(
              active
                  ? Icons.check_rounded
                  : icon,
              color: active
                  ? const Color(
                      0xFF2DE2A6,
                    )
                  : Colors.white
                      .withOpacity(
                      0.36,
                    ),
              size: 18,
            ),
          ),

          const SizedBox(
            width: 10,
          ),

          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: Colors.white
                    .withOpacity(
                  0.62,
                ),
                fontWeight:
                    FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),

          const SizedBox(
            width: 8,
          ),

          Text(
            value,
            textAlign:
                TextAlign.right,
            style: TextStyle(
              color: active
                  ? const Color(
                      0xFF2DE2A6,
                    )
                  : Colors.white
                      .withOpacity(
                      0.78,
                    ),
              fontWeight:
                  FontWeight.w900,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileLine
    extends StatelessWidget {
  final String label;
  final String value;

  const _ProfileLine({
    required this.label,
    required this.value,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        vertical: 11,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white
                .withOpacity(
              0.055,
            ),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white
                    .withOpacity(
                  0.52,
                ),
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(
            width: 10,
          ),
          Text(
            value,
            textAlign:
                TextAlign.right,
            style:
                const TextStyle(
              color: Colors.white,
              fontWeight:
                  FontWeight.w900,
              fontSize: 12.5,
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
    int totalPoints,
  ) {
    final range =
        target - minimum;

    if (range <= 0) {
      return 1;
    }

    final current =
        totalPoints - minimum;

    return (current / range)
        .clamp(
          0.0,
          1.0,
        )
        .toDouble();
  }

  int pointsToNext(
    int totalPoints,
  ) {
    return max(
      target - totalPoints,
      0,
    );
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

  factory _HistoryEntry.fromJson(
    Map<String, dynamic> json,
  ) {
    return _HistoryEntry(
      reward: _asInt(
            json['reward'] ??
                json['points'] ??
                json['amount'] ??
                json['earned_points'],
          ) ??
          0,
      rawDate: (
        json['created_at'] ??
        json['createdAt'] ??
        json['mined_at'] ??
        json['date'] ??
        json['timestamp'] ??
        ''
      ).toString(),
      type: (
        json['type'] ??
        'mine'
      ).toString(),
      description: (
        json['description'] ??
        ''
      ).toString(),
    );
  }

  String get dateLabel {
    if (rawDate.isEmpty) {
      return 'Session de minage';
    }

    try {
      final parsed =
          DateTime.parse(
        rawDate,
      ).toLocal();

      final day = parsed.day
          .toString()
          .padLeft(
            2,
            '0',
          );

      final month = parsed.month
          .toString()
          .padLeft(
            2,
            '0',
          );

      final hour = parsed.hour
          .toString()
          .padLeft(
            2,
            '0',
          );

      final minute = parsed.minute
          .toString()
          .padLeft(
            2,
            '0',
          );

      return '$day/$month à $hour:$minute';
    } catch (_) {
      return rawDate;
    }
  }
}

int? _asInt(
  dynamic value,
) {
  if (value == null) {
    return null;
  }

  if (value is int) {
    return value;
  }

  if (value is double) {
    return value.round();
  }

  if (value is num) {
    return value.toInt();
  }

  if (value is String) {
    return int.tryParse(
      value,
    );
  }

  return null;
}

// ================= FIN PARTIE 8/8 ====================