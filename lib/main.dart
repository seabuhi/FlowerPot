import 'package:flutter/material.dart';

import 'connect_page.dart';
import 'control_page.dart';
import 'pot_controller.dart';

void main() => runApp(const AgilliDibcekApp());

class AgilliDibcekApp extends StatefulWidget {
  const AgilliDibcekApp({super.key});

  @override
  State<AgilliDibcekApp> createState() => _AgilliDibcekAppState();
}

class _AgilliDibcekAppState extends State<AgilliDibcekApp> {
  final pot = PotController();

  @override
  void dispose() {
    pot.dispose();
    super.dispose();
  }

  ThemeData _theme(Brightness b) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32), brightness: b),
        cardTheme: const CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ağıllı Dibçək',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: ListenableBuilder(
        listenable: pot,
        builder: (context, _) => pot.connected
            ? ControlPage(pot: pot)
            : ConnectPage(onConnected: pot.attach),
      ),
    );
  }
}
