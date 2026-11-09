import 'package:flutter/material.dart';

import 'screens/join_screen.dart';

void main() => runApp(const EasyChatApp());

class EasyChatApp extends StatelessWidget {
  const EasyChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF4F46E5),
        brightness: brightness,
      ),
      useMaterial3: true,
    );

    return MaterialApp(
      title: 'easy_chat',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const JoinScreen(),
    );
  }
}
