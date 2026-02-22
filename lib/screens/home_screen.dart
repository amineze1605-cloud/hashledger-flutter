import 'package:flutter/material.dart';
import 'dart:async';
import '../models/user_model.dart';
import '../services/api_service.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  final UserModel user;

  HomeScreen({required this.user});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late UserModel currentUser;
  bool sessionActive = false;
  int sessionTime = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    currentUser = widget.user;
  }

  void startSession() {
    if (sessionActive) return;
    setState(() {
      sessionActive = true;
      sessionTime = 30;
    });

    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() => sessionTime--);
      if (sessionTime <= 0) {
        timer.cancel();
        endSession();
      }
    });
  }

  void endSession() async {
    setState(() => sessionActive = false);

    int basePoints = 20;
    int bonus = (DateTime.now().millisecondsSinceEpoch % 2 == 0) ? 20 : 0;

    final result = await ApiService.addSession(
        currentUser.token, basePoints, bonus);

    setState(() {
      currentUser = UserModel(
          id: currentUser.id,
          email: currentUser.email,
          points: currentUser.points + result['totalPoints'],
          token: currentUser.token);
    });

    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Session +${result['totalPoints']} points")));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Dashboard"),
        actions: [
          IconButton(
              icon: Icon(Icons.logout),
              onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => LoginScreen()),
                  )),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            Text("Email : ${currentUser.email}",
                style: TextStyle(fontSize: 16)),
            SizedBox(height: 10),
            Text("Points : ${currentUser.points}",
                style: TextStyle(fontSize: 24)),
            SizedBox(height: 20),
            sessionActive
                ? Text("Session : $sessionTime s")
                : ElevatedButton(
                    onPressed: startSession,
                    child: Text("Commencer Session"),
                  ),
          ],
        ),
      ),
    );
  }
}