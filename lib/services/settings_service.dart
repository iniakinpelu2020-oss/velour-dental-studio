import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String keyWorkerUrl = 'worker_url';
  static const String keyAuthToken = 'auth_token';
  static const String keyModelId = 'model_id';

  static const String keyMasterAutoReplyEnabled = 'master_auto_reply_enabled';
  static const String keyRequireConfirmation = 'require_confirmation';
  static const String keyIgnoreGroupChats = 'ignore_group_chats';
  static const String keyCooldownSeconds = 'cooldown_seconds';
  static const String keyGlobalRule = 'global_rule';

  static const String keyAppModesJson = 'app_modes_json';
  static const String keyAppRulesJson = 'app_rules_json';
  static const String keyContactRulesJson = 'contact_rules_json';
  static const String keyContactModesJson = 'contact_modes_json';
  static const String keyAllowlistJson = 'allowlist_json';
  static const String keyBlocklistJson = 'blocklist_json';
  static const String keyAutoReplyHistoryJson = 'auto_reply_history_json';

  static const String defaultModelId = '@hf/nousresearch/hermes-2-pro-mistral-7b';

  static SharedPreferences? _prefs;

  static Future<SharedPreferences> get _instance async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  static Future<void> reload() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Worker / model settings
  static Future<String> getWorkerUrl() async => (await _instance).getString(keyWorkerUrl) ?? '';
  static Future<void> setWorkerUrl(String value) async => (await _instance).setString(keyWorkerUrl, value.trim());

  static Future<String> getAuthToken() async => (await _instance).getString(keyAuthToken) ?? '';
  static Future<void> setAuthToken(String value) async => (await _instance).setString(keyAuthToken, value.trim());

  static Future<String> getModelId() async => (await _instance).getString(keyModelId) ?? defaultModelId;
  static Future<void> setModelId(String value) async {
    final v = value.trim();
    await (await _instance).setString(keyModelId, v.isEmpty ? defaultModelId : v);
  }

  // Auto-reply toggles
  static Future<bool> getMasterAutoReplyEnabled() async =>
      (await _instance).getBool(keyMasterAutoReplyEnabled) ?? false;
  static Future<void> setMasterAutoReplyEnabled(bool value) async =>
      (await _instance).setBool(keyMasterAutoReplyEnabled, value);

  static Future<bool> getRequireConfirmation() async =>
      (await _instance).getBool(keyRequireConfirmation) ?? true;
  static Future<void> setRequireConfirmation(bool value) async =>
      (await _instance).setBool(keyRequireConfirmation, value);

  static Future<bool> getIgnoreGroupChats() async =>
      (await _instance).getBool(keyIgnoreGroupChats) ?? true;
  static Future<void> setIgnoreGroupChats(bool value) async =>
      (await _instance).setBool(keyIgnoreGroupChats, value);

  static Future<int> getCooldownSeconds() async =>
      (await _instance).getInt(keyCooldownSeconds) ?? 60;
  static Future<void> setCooldownSeconds(int value) async =>
      (await _instance).setInt(keyCooldownSeconds, value.clamp(0, 3600));

  static Future<String> getGlobalRule() async => (await _instance).getString(keyGlobalRule) ?? '';
  static Future<void> setGlobalRule(String value) async =>
      (await _instance).setString(keyGlobalRule, value);

  // JSON map helpers
  static Future<Map<String, String>> getStringMap(String key) async {
    final raw = (await _instance).getString(key) ?? '';
    if (raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
      }
    } catch (_) {}
    return {};
  }

  static Future<void> setStringMap(String key, Map<String, String> value) async {
    await (await _instance).setString(key, jsonEncode(value));
  }

  static Future<List<String>> getStringListJson(String key) async {
    final raw = (await _instance).getString(key) ?? '';
    if (raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<void> setStringListJson(String key, List<String> value) async {
    await (await _instance).setString(key, jsonEncode(value));
  }

  // App modes: packageName -> auto_reply|alert_only|off
  static Future<Map<String, String>> getAppModes() async => getStringMap(keyAppModesJson);
  static Future<void> setAppModes(Map<String, String> value) async => setStringMap(keyAppModesJson, value);

  // App rules: packageName -> rule text
  static Future<Map<String, String>> getAppRules() async => getStringMap(keyAppRulesJson);
  static Future<void> setAppRules(Map<String, String> value) async => setStringMap(keyAppRulesJson, value);

  // Contact rules: senderKey -> rule text
  static Future<Map<String, String>> getContactRules() async => getStringMap(keyContactRulesJson);
  static Future<void> setContactRules(Map<String, String> value) async => setStringMap(keyContactRulesJson, value);

  // Contact modes: senderKey -> allow|block|off
  static Future<Map<String, String>> getContactModes() async => getStringMap(keyContactModesJson);
  static Future<void> setContactModes(Map<String, String> value) async => setStringMap(keyContactModesJson, value);

  static Future<List<String>> getAllowlist() async => getStringListJson(keyAllowlistJson);
  static Future<void> setAllowlist(List<String> value) async => setStringListJson(keyAllowlistJson, value);

  static Future<List<String>> getBlocklist() async => getStringListJson(keyBlocklistJson);
  static Future<void> setBlocklist(List<String> value) async => setStringListJson(keyBlocklistJson, value);

  static Future<List<Map<String, dynamic>>> getAutoReplyHistory() async {
    final raw = (await _instance).getString(keyAutoReplyHistoryJson) ?? '';
    if (raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList();
      }
    } catch (_) {}
    return [];
  }
}
