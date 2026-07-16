import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'presentation/notes_page.dart';

void main() {
  runApp(const ProviderScope(child: PotokApp()));
}

class PotokApp extends StatelessWidget {
  const PotokApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Studio Light (дефолтная тема ТЗ 0.6.6); остальные темы — WP-07.
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF3457D5));
    return MaterialApp(
      title: 'Поток',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFE9EDF2),
        useMaterial3: true,
      ),
      home: const NotesPage(),
    );
  }
}
