import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/app_logo.dart';
import 'core/storage/session_storage.dart';
import 'core/auth/jwt_utils.dart';
import 'features/chat/presentation/student_chat_shell.dart';
import 'features/chat/presentation/teacher_chat_shell.dart';
import 'features/chat/presentation/admin_staff_shell.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/home/presentation/role_home_screen.dart';

void main() {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
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
    FlutterNativeSplash.remove();
    if (!mounted) return;
    setState(() {
      _session = session;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Fail fast when the build missed `--dart-define=API_BASE_URL=...`.
    // The backend origin is never hardcoded; it must come from the build.
    if (!AppConfig.isConfigured) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Missing API_BASE_URL.\n\n'
                'Rebuild with --dart-define=API_BASE_URL=<backend-origin>\n'
                'or --dart-define-from-file=dart_defines/production.json.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }
    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppLogo(
                size: 140,
                borderRadius: 0,
                showBackground: false,
                asset: AppAssets.bglessLogo,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(color: AppColors.violet),
            ],
          ),
        ),
      );
    }

    if (_session != null) {
      final role = _session!.payload.role;
      if (isWebOnlyRole(role) || !isMobileAppRole(role)) {
        return RoleHomeScreen(session: _session!, unsupported: true);
      }
      if (role == 'student') {
        return StudentChatShell(session: _session!);
      }
      if (role == 'teacher') {
        return TeacherChatShell(session: _session!);
      }
      if (isStaffAdminRole(role)) {
        return AdminStaffShell(session: _session!);
      }
      return RoleHomeScreen(session: _session!);
    }

    return const LoginScreen();
  }
}
