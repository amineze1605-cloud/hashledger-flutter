import 'package:flutter/material.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(HashLedgerApp());
}

class HashLedgerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HashLedger',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: LoginScreen(),
    );
  }
}
