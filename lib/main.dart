import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'imageget.dart';
import 'Auth/login.dart';

// 🔑 SUPABASE CONFIG
const String _supabaseUrl = 'https://pffshbkpvbxakvblflzw.supabase.co';
const String _supabaseAnonKey =
'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBmZnNoYmtwdmJ4YWt2YmxmbHp3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ2MDUyMTIsImV4cCI6MjA5MDE4MTIxMn0.4rUiGa7rBz7dwloK6nXHqKx2_2nJj1lQpGM7PZQXMLY'

;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnonKey,
  );

  runApp(const MyApp());
}

// Global client
final supabase = Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PersonaLens',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home:  LoginScreen(),
    );
  }
}