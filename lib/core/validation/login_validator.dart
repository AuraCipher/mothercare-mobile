/// Client-side checks before calling POST /auth/login.
class LoginValidator {
  static final RegExp _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static final RegExp _phone = RegExp(r'^\+?[0-9][0-9\s\-()]{6,}$');
  static final RegExp _username = RegExp(r'^[a-zA-Z0-9._\-]+$');

  static String? validateIdentifier(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) {
      return 'Enter your username, email, or phone';
    }
    if (value.length < 2) {
      return 'Identifier is too short';
    }
    if (value.length > 100) {
      return 'Identifier is too long';
    }
    final ok = _email.hasMatch(value) || _phone.hasMatch(value) || _username.hasMatch(value);
    if (!ok) {
      return 'Use a valid username, email, or phone number';
    }
    return null;
  }

  static String? validatePassword(String? raw) {
    final value = raw ?? '';
    if (value.isEmpty) {
      return 'Enter your password';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    if (value.length > 128) {
      return 'Password is too long';
    }
    return null;
  }

  /// Map backend messages to user-friendly copy (mirrors web login).
  static String mapApiError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('invalid credentials')) {
      return 'Incorrect username or password';
    }
    if (lower.contains('disabled after graduation')) {
      return 'Account closed after graduation. Contact school admin.';
    }
    if (lower.contains('not enrolled in any active academic year')) {
      return 'No active enrollment. Contact school admin.';
    }
    if (lower.contains('teacher profile not found') || lower.contains('teacher branch membership')) {
      return 'Teacher access is not set up. Contact school admin.';
    }
    if (lower.contains('not active')) {
      return 'This account is inactive. Contact school admin.';
    }
    if (lower.contains('web portal only')) {
      return 'This account uses the web admin portal only.';
    }
    if (lower.contains('cannot reach') || lower.contains('failed to fetch') || lower.contains('network')) {
      return 'Cannot reach the server. Please check your internet connection.';
    }
    if (lower.contains('timed out') || lower.contains('timeout')) {
      return 'The server took too long to respond. Please try again.';
    }
    // Developer-facing messages should never reach end users
    if (lower.contains('set host=') || lower.contains('dart-define') || lower.contains('npm run dev')) {
      return 'Cannot reach the server. Please check your internet connection and try again.';
    }
    // Fallback: only pass through if short and safe
    if (message.length < 80 && !message.contains('prisma') && !message.contains('P20') && !message.contains('http://') && !message.contains('localhost')) {
      return message;
    }
    return 'Something went wrong. Please try again.';
  }
}
