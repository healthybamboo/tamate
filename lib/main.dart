import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/notifications/local_notification_service.dart';
import 'core/notifications/notification_service.dart';
import 'core/providers/shared_preferences_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final notifications = LocalNotificationService();
  await notifications.initialize();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        notificationServiceProvider.overrideWithValue(notifications),
      ],
      child: const TamateApp(),
    ),
  );
}
