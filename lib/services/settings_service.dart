import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String keyWorkerUrl = 'worker_url';
  static const String keyAuthToken = 'auth_token';
  static const String keyModelId = 'model_id';
  static const String keyCustomLlmEndpoint = 'custom_llm_endpoint';

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

  static const String keyBusinessPhoneNumber = 'business_phone_number';
  static const String keyDefaultCountryCode = 'default_country_code';
  static const String keyVoiceInputEnabled = 'voice_input_enabled';
  static const String keySpeakRepliesEnabled = 'speak_replies_enabled';
  static const String keyTtsRate = 'tts_rate';
  static const String keyMemoryEnabled = 'memory_enabled';
  static const String keyMemoryNotesJson = 'memory_notes_json';
  static const String keyMemoryBookingsJson = 'memory_bookings_json';
  static const String keyMemoryContactsJson = 'memory_contacts_json';
  static const String keyMemoryContext = 'memory_context';
  static const String keyWorkflowsJson = 'workflows_json';

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

  static Future<String> getCustomLlmEndpoint() async =>
      (await _instance).getString(keyCustomLlmEndpoint) ?? '';
  static Future<void> setCustomLlmEndpoint(String value) async =>
      (await _instance).setString(keyCustomLlmEndpoint, value.trim());

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

  // Business / voice / memory settings
  static Future<String> getBusinessPhoneNumber() async =>
      (await _instance).getString(keyBusinessPhoneNumber) ?? '';
  static Future<void> setBusinessPhoneNumber(String value) async =>
      (await _instance).setString(keyBusinessPhoneNumber, value.trim());

  static Future<String> getDefaultCountryCode() async =>
      (await _instance).getString(keyDefaultCountryCode) ?? '+234';
  static Future<void> setDefaultCountryCode(String value) async {
    final v = value.trim();
    await (await _instance).setString(keyDefaultCountryCode, v.isEmpty ? '+234' : v);
  }

  static Future<bool> getVoiceInputEnabled() async =>
      (await _instance).getBool(keyVoiceInputEnabled) ?? false;
  static Future<void> setVoiceInputEnabled(bool value) async =>
      (await _instance).setBool(keyVoiceInputEnabled, value);

  static Future<bool> getSpeakRepliesEnabled() async =>
      (await _instance).getBool(keySpeakRepliesEnabled) ?? false;
  static Future<void> setSpeakRepliesEnabled(bool value) async =>
      (await _instance).setBool(keySpeakRepliesEnabled, value);

  static Future<double> getTtsRate() async =>
      ((await _instance).getDouble(keyTtsRate) ?? 0.5).clamp(0.2, 1.0);
  static Future<void> setTtsRate(double value) async =>
      (await _instance).setDouble(keyTtsRate, value.clamp(0.2, 1.0));

  static Future<bool> getMemoryEnabled() async =>
      (await _instance).getBool(keyMemoryEnabled) ?? true;
  static Future<void> setMemoryEnabled(bool value) async =>
      (await _instance).setBool(keyMemoryEnabled, value);

  static Future<String> getMemoryContext() async =>
      (await _instance).getString(keyMemoryContext) ?? '';
  static Future<void> setMemoryContext(String value) async =>
      (await _instance).setString(keyMemoryContext, value);

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

  static Future<List<Map<String, dynamic>>> getJsonList(String key) async {
    final raw = (await _instance).getString(key) ?? '';
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

  static Future<void> setJsonList(String key, List<Map<String, dynamic>> value) async {
    await (await _instance).setString(key, jsonEncode(value));
  }

  // App/contact rules and modes
  static Future<Map<String, String>> getAppModes() async => getStringMap(keyAppModesJson);
  static Future<void> setAppModes(Map<String, String> value) async => setStringMap(keyAppModesJson, value);

  static Future<Map<String, String>> getAppRules() async => getStringMap(keyAppRulesJson);
  static Future<void> setAppRules(Map<String, String> value) async => setStringMap(keyAppRulesJson, value);

  static Future<Map<String, String>> getContactRules() async => getStringMap(keyContactRulesJson);
  static Future<void> setContactRules(Map<String, String> value) async => setStringMap(keyContactRulesJson, value);

  static Future<Map<String, String>> getContactModes() async => getStringMap(keyContactModesJson);
  static Future<void> setContactModes(Map<String, String> value) async => setStringMap(keyContactModesJson, value);

  static Future<List<String>> getAllowlist() async => getStringListJson(keyAllowlistJson);
  static Future<void> setAllowlist(List<String> value) async => setStringListJson(keyAllowlistJson, value);

  static Future<List<String>> getBlocklist() async => getStringListJson(keyBlocklistJson);
  static Future<void> setBlocklist(List<String> value) async => setStringListJson(keyBlocklistJson, value);

  static Future<List<Map<String, dynamic>>> getAutoReplyHistory() async {
    return getJsonList(keyAutoReplyHistoryJson);
  }

  // Persistent memory
  static Future<List<Map<String, dynamic>>> getMemoryNotes() async => getJsonList(keyMemoryNotesJson);
  static Future<void> setMemoryNotes(List<Map<String, dynamic>> value) async =>
      setJsonList(keyMemoryNotesJson, value);

  static Future<List<Map<String, dynamic>>> getMemoryBookings() async => getJsonList(keyMemoryBookingsJson);
  static Future<void> setMemoryBookings(List<Map<String, dynamic>> value) async =>
      setJsonList(keyMemoryBookingsJson, value);

  static Future<List<Map<String, dynamic>>> getMemoryContacts() async => getJsonList(keyMemoryContactsJson);
  static Future<void> setMemoryContacts(List<Map<String, dynamic>> value) async =>
      setJsonList(keyMemoryContactsJson, value);

  static Future<Map<String, dynamic>> getMemorySnapshot() async {
    return {
      'notes': await getMemoryNotes(),
      'bookings': await getMemoryBookings(),
      'contacts': await getMemoryContacts(),
      'context': await getMemoryContext(),
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
  }

  static Future<void> saveMemorySnapshot(Map<String, dynamic> memory) async {
    List<Map<String, dynamic>> asList(dynamic v) {
      if (v is List) {
        return v.whereType<Map>().map((e) => e.map((k, val) => MapEntry(k.toString(), val))).toList();
      }
      return [];
    }

    if (memory['notes'] != null) await setMemoryNotes(asList(memory['notes']));
    if (memory['bookings'] != null) await setMemoryBookings(asList(memory['bookings']));
    if (memory['contacts'] != null) await setMemoryContacts(asList(memory['contacts']));
    if (memory['context'] != null) await setMemoryContext(memory['context'].toString());
  }

  static Future<void> clearMemory() async {
    await setMemoryNotes([]);
    await setMemoryBookings([]);
    await setMemoryContacts([]);
    await setMemoryContext('');
  }

  // Workflows
  static Future<List<Map<String, dynamic>>> getWorkflows() async => getJsonList(keyWorkflowsJson);
  static Future<void> setWorkflows(List<Map<String, dynamic>> value) async =>
      setJsonList(keyWorkflowsJson, value);
}
