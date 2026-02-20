import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import 'dart:async';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  final UserModel user;
  HomeScreen({required this.user});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late UserModel user;
  int sessionTime = 30;
  bool isSessionActive = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    user = widget.user;
  }

  void startSession() {
    if (isSessionActive) return;
    setState(() { isSessionActive = true; sessionTime = 30; });

    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() { sessionTime--; });
      if (sessionTime <= 0) {
        timer.cancel();
        endSession();
      }
    });
  }

  void endSession() async {
    setState(() { isSessionActive = false; });
    int basePoints = 20;
    int bonusPoints = (DateTime.now().millisecondsSinceEpoch % 2 == 0) ? 20 : 0;
    int totalPoints = basePoints + bonusPoints;

    try {
      var data = await ApiService.addSession(user.token, basePoints, bonusPoints);
      setState(() { user = UserModel(id: user.id, email: user.email, points: data['totalPoints'] + user.points, token: user.token); });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Session terminée ! +$totalPoints points')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur session')));
    }
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Dashboard'),
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: () {
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LoginScreen()));
            },
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            Text('Utilisateur : ${user.email}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            SizedBox(height: 10),
            Text('Points : ${user.points}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            SizedBox(height: 20),
            isSessionActive
                ? Text('Session en cours : $sessionTime s', style: TextStyle(fontSize: 18))
                : ElevatedButton(onPressed: startSession, child: Text('Commencer Session (+20 points)')),
            SizedBox(height: 20),
            Text('Astuce : parfois regarder une pub double vos points !', style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }
}
