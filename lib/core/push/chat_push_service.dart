import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../config/app_config.dart';
import '../storage/session_storage.dart';
import 'chat_device_api.dart';
import 'push_payload_crypto.dart';

const _chatNotificationChannelId = 'mcs_chat_messages';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await ChatPushService.instance.handleRemoteMessage(message);
}

typedef ChatPushRoomTap = void Function(String roomId, String roomName);

class ChatPushService {
  ChatPushService._();

  static final ChatPushService instance = ChatPushService._();

  final _deviceApi = ChatDeviceApi();
  final _crypto = const PushPayloadCrypto();
  final _localNotifications = FlutterLocalNotificationsPlugin();
  final _sessionStorage = SessionStorage();

  bool _initialized = false;
  String? _authToken;
  String? _fcmToken;
  ChatPushRoomTap? _onRoomTap;

  void setRoomTapHandler(ChatPushRoomTap? handler) {
    _onRoomTap = handler;
  }

  Future<void> bindSession(String authToken) async {
    _authToken = authToken;
    if (!AppConfig.pushEnabled) return;
    if (!AppConfig.hasFirebaseOptions) {
      debugPrint('ChatPushService: PUSH_ENABLED but Firebase dart-defines missing');
      return;
    }

    try {
      await _ensureFirebase();
      await _ensureLocalNotifications();
      await FirebaseMessaging.instance.requestPermission();
      if (Platform.isAndroid) {
        final android = _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        await android?.requestNotificationsPermission();
      }
      if (!_initialized) {
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
        FirebaseMessaging.onMessage.listen((message) {
          handleRemoteMessage(message);
        });
        FirebaseMessaging.onMessageOpenedApp.listen((message) {
          _handleOpenedMessage(message);
        });
        final initial = await FirebaseMessaging.instance.getInitialMessage();
        if (initial != null) {
          await _handleOpenedMessage(initial);
        }
        _initialized = true;
      }

      await _registerCurrentToken();
      FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
        _fcmToken = token;
        await _registerToken(token);
      });
    } catch (e, st) {
      debugPrint('ChatPushService bind failed: $e\n$st');
    }
  }

  Future<void> unbindSession() async {
    final token = _authToken;
    final fcm = _fcmToken;
    _authToken = null;
    if (token != null && fcm != null) {
      try {
        await _deviceApi.unregisterDevice(token: token, fcmToken: fcm);
      } catch (_) {}
    }
    _fcmToken = null;
  }

  Future<void> handleRemoteMessage(RemoteMessage message) async {
    if (!AppConfig.pushEnabled) return;
    final material = await _sessionStorage.readPushCrypto();
    if (material == null) return;

    final payload = await _crypto.decrypt(
      material,
      message.data.map((key, value) => MapEntry(key, '$value')),
    );
    if (payload == null) return;
    if (payload['type'] != 'chat_message') return;

    final roomName = payload['roomName'] as String? ?? 'New message';
    final preview = payload['preview'] as String? ?? 'You have a new message';
    final roomId = payload['roomId'] as String? ?? '';

    await _ensureLocalNotifications();
    final notificationId = roomId.hashCode.abs() % 100000;
    await _localNotifications.show(
      id: notificationId,
      title: roomName,
      body: preview,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _chatNotificationChannelId,
          'Chat messages',
          channelDescription: 'School announcements and direct messages',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: roomId.isEmpty ? null : jsonEncode({'roomId': roomId, 'roomName': roomName}),
    );
  }

  Future<void> _ensureFirebase() async {
    if (Firebase.apps.isNotEmpty) return;
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: AppConfig.firebaseApiKey,
        appId: AppConfig.firebaseAppId,
        messagingSenderId: AppConfig.firebaseMessagingSenderId,
        projectId: AppConfig.firebaseProjectId,
      ),
    );
  }

  Future<void> _ensureLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _localNotifications.initialize(
      settings: const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final map = jsonDecode(payload) as Map<String, dynamic>;
          final roomId = map['roomId'] as String? ?? '';
          final roomName = map['roomName'] as String? ?? 'Chat';
          if (roomId.isNotEmpty) {
            _onRoomTap?.call(roomId, roomName);
          }
        } catch (_) {}
      },
    );

    if (Platform.isAndroid) {
      final android = _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _chatNotificationChannelId,
          'Chat messages',
          description: 'School announcements and direct messages',
          importance: Importance.high,
        ),
      );
    }
  }

  Future<void> _registerCurrentToken() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    _fcmToken = token;
    await _registerToken(token);
  }

  Future<void> _registerToken(String fcmToken) async {
    final authToken = _authToken;
    if (authToken == null) return;
    final platform = Platform.isIOS
        ? 'ios'
        : Platform.isAndroid
            ? 'android'
            : 'web';
    await _deviceApi.registerDevice(
      token: authToken,
      fcmToken: fcmToken,
      platform: platform,
    );
  }

  Future<void> _handleOpenedMessage(RemoteMessage message) async {
    final material = await _sessionStorage.readPushCrypto();
    if (material == null) return;
    final payload = await _crypto.decrypt(
      material,
      message.data.map((key, value) => MapEntry(key, '$value')),
    );
    if (payload == null) return;
    final roomId = payload['roomId'] as String? ?? '';
    if (roomId.isEmpty) return;
    final roomName = payload['roomName'] as String? ?? 'Chat';
    _onRoomTap?.call(roomId, roomName);
  }
}
