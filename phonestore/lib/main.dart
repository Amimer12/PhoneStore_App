import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/app_theme.dart';
import 'screens/auth_gate.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  // main.dart — only this block changes
  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final supabaseServiceKey = dotenv.env['SUPABASE_ANON_KEY']; // ← changed

  if (supabaseUrl == null || supabaseServiceKey == null) {
  throw Exception('Missing Supabase environment variables.');
}

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseServiceKey,
  );

  runApp(const ShopAdminApp());
}

class ShopAdminApp extends StatelessWidget {
  const ShopAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shop Admin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const AuthGate(),
    );
  }
}
