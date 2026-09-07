import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../testing/e2e_keys.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/validation/login_validator.dart';
import '../../../core/auth/jwt_utils.dart';
import '../../../core/storage/session_storage.dart';
import '../data/auth_api.dart';
import '../../home/presentation/role_home_screen.dart';
import '../../chat/presentation/student_chat_shell.dart';
import '../../chat/presentation/teacher_chat_shell.dart';
import '../../chat/presentation/admin_staff_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.onLoggedIn});

  final void Function(StoredSession session)? onLoggedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authApi = AuthApi();
  final _sessionStorage = SessionStorage();

  bool _obscurePassword = true;
  bool _loading = false;
  String? _apiError;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _apiError = null);

    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    final identifier = _identifierController.text.trim();
    final password = _passwordController.text;

    setState(() => _loading = true);
    try {
      final response = await _authApi.login(
        identifier: identifier,
        password: password,
      );

      final payload = decodeJwtPayload(response.token);
      if (payload == null) {
        setState(() => _apiError = 'Invalid session from server');
        return;
      }

      if (isWebOnlyRole(payload.role)) {
        setState(() => _apiError = LoginValidator.mapApiError('This account uses the web portal only'));
        return;
      }

      if (!isMobileAppRole(payload.role)) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => RoleHomeScreen(
              session: StoredSession(
                token: response.token,
                payload: payload,
                user: response.user,
              ),
              unsupported: true,
            ),
          ),
        );
        return;
      }

      await _sessionStorage.saveSession(response);

      final session = StoredSession(
        token: response.token,
        payload: payload,
        user: response.user,
      );

      widget.onLoggedIn?.call(session);
      if (!mounted) return;
      if (payload.role == 'student') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => StudentChatShell(session: session)),
        );
        return;
      }
      if (payload.role == 'teacher') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => TeacherChatShell(session: session)),
        );
        return;
      }
      if (isStaffAdminRole(payload.role)) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => AdminStaffShell(session: session)),
        );
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => RoleHomeScreen(session: session)),
      );
    } on AuthApiException catch (e) {
      setState(() => _apiError = LoginValidator.mapApiError(e.message));
    } on SocketException {
      setState(() => _apiError = 'Cannot reach the server. Please check your internet connection and try again.');
    } on TimeoutException {
      setState(() => _apiError = 'The server took too long to respond. Please try again.');
    } catch (e) {
      setState(() {
        _apiError = 'Something went wrong. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.disabled,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    Center(
                      child: AppLogo(
                        size: 140,
                        borderRadius: 0,
                        showBackground: false,
                        asset: AppAssets.bglessLogo,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Mother Care School',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                            letterSpacing: -0.2,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Sign in with your school credentials',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textMuted,
                          ),
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      key: E2eKeys.loginIdentifier,
                      controller: _identifierController,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Username, email, or phone',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: LoginValidator.validateIdentifier,
                      enabled: !_loading,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: E2eKeys.loginPassword,
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: _loading
                              ? null
                              : () => setState(() => _obscurePassword = !_obscurePassword),
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          ),
                        ),
                      ),
                      validator: LoginValidator.validatePassword,
                      enabled: !_loading,
                    ),
                    if (_apiError != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _apiError!,
                                style: const TextStyle(color: AppColors.error, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    ElevatedButton(
                      key: E2eKeys.loginSubmit,
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Sign In'),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Accounts are created by your school.\nThere is no public sign-up.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textMuted,
                            height: 1.4,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
