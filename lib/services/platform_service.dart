import 'dart:convert';

import 'package:flutter/services.dart';

class PlatformService {
  static const MethodChannel _accessibility =
      MethodChannel('com.apex.agent/accessibility');
  static const MethodChannel _background =
      MethodChannel('com.apex.agent/background');

  // Accessibility
  static Future<bool> isAccessibilityEnabled() async {
    try {
      return await _accessibility.invokeMethod<bool>('isEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openAccessibilitySettings() async {
    try {
      return await _accessibility.invokeMethod<bool>('openSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<String> getScreenStateJson() async {
    try {
      return await _accessibility.invokeMethod<String>('getScreenStateJson') ?? '{}';
    } catch (e) {
      return jsonEncode({'error': e.toString(), 'elements': []});
    }
  }

  static Future<bool> openApp(String packageOrName) async {
    try {
      return await _accessibility.invokeMethod<bool>(
            'openApp',
            {'packageOrName': packageOrName},
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> clickText(String target) async {
    try {
      return await _accessibility.invokeMethod<bool>(
            'clickText',
            {'target': target},
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> typeText({
    String? targetOrFocused,
    required String text,
  }) async {
    try {
      return await _accessibility.invokeMethod<bool>('typeText', {
            'targetOrFocused': targetOrFocused,
            'text': text,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> scrollScreen(String direction) async {
    try {
      return await _accessibility.invokeMethod<bool>(
            'scrollScreen',
            {'direction': direction},
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> pressGlobal(String action) async {
    try {
      return await _accessibility.invokeMethod<bool>(
            'pressGlobal',
            {'action': action},
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  // Background / notifications / phone / tts
  static Future<bool> isNotificationListenerEnabled() async {
    try {
      return await _background.invokeMethod<bool>('isNotificationListenerEnabled') ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openNotificationListenerSettings() async {
    try {
      return await _background.invokeMethod<bool>('openNotificationListenerSettings') ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isBackgroundServiceRunning() async {
    try {
      return await _background.invokeMethod<bool>('isBackgroundServiceRunning') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> startBackgroundService() async {
    try {
      return await _background.invokeMethod<bool>('startBackgroundService') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> stopBackgroundService() async {
    try {
      return await _background.invokeMethod<bool>('stopBackgroundService') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      return await _background.invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestIgnoreBatteryOptimizations() async {
    try {
      return await _background.invokeMethod<bool>('requestIgnoreBatteryOptimizations') ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, String>>> getInstalledApps() async {
    try {
      final raw = await _background.invokeMethod<List<dynamic>>('getInstalledApps');
      if (raw == null) return [];
      return raw
          .whereType<Map>()
          .map((m) => {
                'packageName': m['packageName']?.toString() ?? '',
                'appName': m['appName']?.toString() ?? '',
              })
          .where((m) => m['packageName']!.isNotEmpty && m['appName']!.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<String> getRecentNotifications({int limit = 20}) async {
    try {
      return await _background.invokeMethod<String>(
            'getRecentNotifications',
            {'limit': limit},
          ) ??
          '[]';
    } catch (_) {
      return '[]';
    }
  }

  static Future<bool> replyToNotification({
    required String notificationKey,
    required String message,
  }) async {
    try {
      return await _background.invokeMethod<bool>('replyToNotification', {
            'notificationKey': notificationKey,
            'message': message,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> setAlarm({
    required int hour,
    required int minute,
    String? message,
  }) async {
    try {
      return await _background.invokeMethod<bool>('setAlarm', {
            'hour': hour,
            'minute': minute,
            'message': message,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> saveNote({
    required String title,
    required String content,
  }) async {
    try {
      return await _background.invokeMethod<bool>('saveNote', {
            'title': title,
            'content': content,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<String> getNotes() async {
    try {
      return await _background.invokeMethod<String>('getNotes') ?? '[]';
    } catch (_) {
      return '[]';
    }
  }

  static Future<String> getAutoReplyHistory() async {
    try {
      return await _background.invokeMethod<String>('getAutoReplyHistory') ?? '[]';
    } catch (_) {
      return '[]';
    }
  }

  static Future<bool> clearAutoReplyHistory() async {
    try {
      return await _background.invokeMethod<bool>('clearAutoReplyHistory') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, bool>> getDeviceStatus() async {
    try {
      final raw = await _background.invokeMethod<Map<dynamic, dynamic>>('getDeviceStatus');
      if (raw == null) {
        return _fallbackStatus();
      }
      return {
        'accessibilityEnabled': raw['accessibilityEnabled'] == true,
        'notificationListenerEnabled': raw['notificationListenerEnabled'] == true,
        'backgroundServiceRunning': raw['backgroundServiceRunning'] == true,
        'ignoringBatteryOptimizations': raw['ignoringBatteryOptimizations'] == true,
        'phoneSmsPermissionsGranted': raw['phoneSmsPermissionsGranted'] == true,
      };
    } catch (_) {
      return _fallbackStatus();
    }
  }

  static Future<bool> requestPostNotifications() async {
    try {
      return await _background.invokeMethod<bool>('requestPostNotifications') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, bool>> getPhoneSmsPermissionStatus() async {
    try {
      final raw = await _background.invokeMethod<Map<dynamic, dynamic>>('getPhoneSmsPermissionStatus');
      if (raw == null) return {'allGranted': false};
      return raw.map((k, v) => MapEntry(k.toString(), v == true));
    } catch (_) {
      return {'allGranted': false};
    }
  }

  static Future<Map<String, bool>> requestPhoneSmsPermissions() async {
    try {
      final raw = await _background.invokeMethod<Map<dynamic, dynamic>>('requestPhoneSmsPermissions');
      if (raw == null) return {'allGranted': false};
      return raw.map((k, v) => MapEntry(k.toString(), v == true));
    } catch (_) {
      return {'allGranted': false};
    }
  }

  static Future<bool> makeCall(String phoneNumber) async {
    try {
      return await _background.invokeMethod<bool>('makeCall', {'phoneNumber': phoneNumber}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> sendSms({required String phoneNumber, required String message}) async {
    try {
      return await _background.invokeMethod<bool>('sendSms', {
            'phoneNumber': phoneNumber,
            'message': message,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openWhatsAppChat({required String phoneNumber, String message = ''}) async {
    try {
      return await _background.invokeMethod<bool>('openWhatsAppChat', {
            'phoneNumber': phoneNumber,
            'message': message,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> speakText(String text) async {
    try {
      return await _background.invokeMethod<bool>('speakText', {'text': text}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> stopSpeaking() async {
    try {
      return await _background.invokeMethod<bool>('stopSpeaking') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isMicrophonePermissionGranted() async {
    try {
      return await _background.invokeMethod<bool>('isMicrophonePermissionGranted') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestMicrophonePermission() async {
    try {
      return await _background.invokeMethod<bool>('requestMicrophonePermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<String> listenForSpeech() async {
    try {
      return await _background.invokeMethod<String>('listenForSpeech') ?? '';
    } catch (_) {
      return '';
    }
  }

  static Map<String, bool> _fallbackStatus() => {
        'accessibilityEnabled': false,
        'notificationListenerEnabled': false,
        'backgroundServiceRunning': false,
        'ignoringBatteryOptimizations': false,
        'phoneSmsPermissionsGranted': false,
      };
}
