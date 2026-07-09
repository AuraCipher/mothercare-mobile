import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/validation/login_validator.dart';

void main() {
  group('LoginValidator', () {
    test('rejects empty identifier', () {
      expect(LoginValidator.validateIdentifier(''), isNotNull);
      expect(LoginValidator.validateIdentifier('   '), isNotNull);
    });

    test('accepts username email phone', () {
      expect(LoginValidator.validateIdentifier('student_ahmed'), isNull);
      expect(LoginValidator.validateIdentifier('ceo@mothercareschool.com'), isNull);
      expect(LoginValidator.validateIdentifier('+92 300 1110001'), isNull);
    });

    test('rejects invalid identifier chars', () {
      expect(LoginValidator.validateIdentifier('bad id!'), isNotNull);
    });

    test('password min length', () {
      expect(LoginValidator.validatePassword(''), isNotNull);
      expect(LoginValidator.validatePassword('12345'), isNotNull);
      expect(LoginValidator.validatePassword('Student@123'), isNull);
    });
  });
}
