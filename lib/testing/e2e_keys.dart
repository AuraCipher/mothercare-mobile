import 'package:flutter/material.dart';

/// Stable keys for integration / E2E tests.
abstract final class E2eKeys {
  static const loginIdentifier = Key('e2e_login_identifier');
  static const loginPassword = Key('e2e_login_password');
  static const loginSubmit = Key('e2e_login_submit');
  static const chatRoomTilePrefix = ValueKey<String>('e2e_chat_room');
}
