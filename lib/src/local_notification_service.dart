import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationService {
  final FlutterLocalNotificationsPlugin notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
    InitializationSettings(android: androidSettings);

    await notificationsPlugin.initialize(initializationSettings);
  }

  notificationDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        'security_channel',
        'Security Notifications',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
      ),
    );
  }

  Future showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    return notificationsPlugin.show(id, title, body, notificationDetails());
  }
}
