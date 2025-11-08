import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:furtive/core/entities/activity_entity.dart';

class ActivityNotificationUseCase {
  static final ActivityNotificationUseCase _instance =
      ActivityNotificationUseCase._internal();
  factory ActivityNotificationUseCase() => _instance;
  ActivityNotificationUseCase._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const int _notificationId = 1;

  Function(String?)? onNotificationAction;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/launcher_icon',
    );

    final iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: false,
    );

    final initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        if (onNotificationAction != null) {
          onNotificationAction!(details.actionId);
        }
      },
    );
    _initialized = true;
  }

  Future<void> showActivityNotification({
    required ActivityEntity activity,
    required Duration elapsed,
    required bool isPaused,
  }) async {
    if (!_initialized) await initialize();

    final distance = activity.activeDistanceInKm.toStringAsFixed(2);
    final pace = activity.activePaceMinPerKm;
    final duration = _formatDuration(elapsed);

    final androidDetails = AndroidNotificationDetails(
      'activity_tracking',
      'Activity Tracking',
      channelDescription: 'Shows your current activity statistics',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      playSound: false,
      enableVibration: false,
      showWhen: false,
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: false,
      categoryIdentifier: 'activity_actions',
      interruptionLevel: InterruptionLevel.passive,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      _notificationId,
      'Activity in Progress',
      '$duration · $distance km · $pace /km',
      details,
    );
  }

  Future<void> cancelActivityNotification() async {
    await _notifications.cancel(_notificationId);
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
