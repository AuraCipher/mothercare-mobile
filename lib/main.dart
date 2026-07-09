import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'core/storage/session_storage.dart';
import 'core/auth/jwt_utils.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/home/presentation/role_home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const McsApp());
}

class McsApp extends StatelessWidget {
  const McsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _sessionStorage = SessionStorage();
  StoredSession? _session;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final session = await _sessionStorage.readSession();
    if (!mounted) return;
    setState(() {
      _session = session;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_session != null) {
      final role = _session!.payload.role;
      if (!isMobileAppRole(role)) {
        return RoleHomeScreen(session: _session!, unsupported: true);
      }
      return RoleHomeScreen(session: _session!);
    }

    return const LoginScreen();
  }
}
