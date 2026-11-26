import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/agent_models.dart';
import 'platform_service.dart';
import 'settings_service.dart';

typedef AgentLogCallback = void Function(AgentStep step);
typedef AgentConfirmationCallback = Future<bool> Function(String message);
typedef AgentStateCallback = void Function(bool isRunning);

class AgentService {
  AgentService({
    required this.onLog,
    required this.onStateChanged,
    required this.onConfirmation,
  });

  final AgentLogCallback onLog;
  final AgentStateCallback onStateChanged;
  final AgentConfirmationCallback onConfirmation;

  final List<AgentMessage> _messages = [];
  bool _running = false;
  bool _stopRequested = false;
  int _screenActionCount = 0;

  static const int maxScreenActions = 10;
  static const int maxIterations = 30;
  static const Set<String> silentTools = {
    'read_notifications',
    'reply_notification',
    'make_call',
    'send_sms',
    'open_whatsapp_chat',
    'set_alarm',
    'save_note',
    'read_notes',
    'manage_booking',
  };
  static const Set<String> screenTools = {
    'open_app',
    'click_text',
    'type_text',
    'scroll_screen',
    'press_global',
  };

  bool get isRunning => _running;

  void stop() {
    _stopRequested = true;
    onLog(AgentStep(
      type: AgentStepType.info,
      title: 'Stop requested',
      detail: 'The agent will stop after the current step.',
    ));
  }

  Future<void> runCommand(String command) async {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return;
    if (_running) {
      onLog(AgentStep(
        type: AgentStepType.error,
        title: 'Agent already running',
        detail: 'Stop the current task before starting a new one.',
      ));
      return;
    }

    _running = true;
    _stopRequested = false;
    _screenActionCount = 0;
    _messages.clear();
    onStateChanged(true);

    onLog(AgentStep(type: AgentStepType.user, title: 'User command', detail: trimmed));
    _messages.add(AgentMessage(role: 'user', content: trimmed));

    try {
      await _loop();
    } catch (e) {
      onLog(AgentStep(
        type: AgentStepType.error,
        title: 'Agent error',
        detail: e.toString(),
      ));
    } finally {
      _running = false;
      onStateChanged(false);
    }
  }

  Future<void> _loop() async {
    String? lastScreenState;
    for (int iteration = 0; iteration < maxIterations; iteration++) {
      if (_stopRequested) {
        onLog(AgentStep(type: AgentStepType.info, title: 'Agent stopped', detail: 'Stopped by user.'));
        return;
      }

      final workerUrl = await SettingsService.getWorkerUrl();
      final authToken = await SettingsService.getAuthToken();
      final modelId = await SettingsService.getModelId();
      final customEndpoint = await SettingsService.getCustomLlmEndpoint();
      final memoryEnabled = await SettingsService.getMemoryEnabled();

      final endpoint = customEndpoint.isNotEmpty ? customEndpoint : workerUrl;
      if (endpoint.isEmpty || authToken.isEmpty) {
        onLog(AgentStep(
          type: AgentStepType.error,
          title: 'Missing configuration',
          detail: 'Set the Worker URL (or custom LLM endpoint) and Bearer Secret Token in Settings.',
        ));
        return;
      }

      final uri = _buildAgentUri(endpoint);
      final payload = <String, dynamic>{
        'messages': _messages.map((m) => m.toJson()).toList(),
        'model': modelId,
      };
      if (lastScreenState != null && lastScreenState.isNotEmpty) {
        payload['screenState'] = lastScreenState;
      }
      if (memoryEnabled) {
        payload['memory'] = await SettingsService.getMemorySnapshot();
        payload['memoryKey'] = 'default';
      }

      onLog(AgentStep(
        type: AgentStepType.info,
        title: 'Contacting worker',
        detail: 'Iteration ${iteration + 1}',
      ));

      http.Response response;
      try {
        response = await http
            .post(
              uri,
              headers: {
                'Authorization': 'Bearer $authToken',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 60));
      } catch (e) {
        onLog(AgentStep(
          type: AgentStepType.error,
          title: 'Worker request failed',
          detail: e.toString(),
        ));
        return;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        onLog(AgentStep(
          type: AgentStepType.error,
          title: 'Worker error ${response.statusCode}',
          detail: _safeBody(response.body),
        ));
        return;
      }

      Map<String, dynamic> body;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Unexpected response shape');
        }
        body = decoded;
      } catch (e) {
        onLog(AgentStep(
          type: AgentStepType.error,
          title: 'Invalid worker response',
          detail: _safeBody(response.body),
        ));
        return;
      }

      // Persist memory snapshot if returned
      if (memoryEnabled && body['memory'] is Map) {
        await SettingsService.saveMemorySnapshot(
          (body['memory'] as Map).map((k, v) => MapEntry(k.toString(), v)),
        );
      }

      final type = body['type']?.toString() ?? '';
      if (type == 'final') {
        final msg = body['message']?.toString() ?? 'Done.';
        onLog(AgentStep(type: AgentStepType.done, title: 'Agent finished', detail: msg));
        _messages.add(AgentMessage(role: 'assistant', content: msg));
        return;
      }

      if (type != 'tool_calls') {
        final msg = body['message']?.toString() ?? body['assistant_message']?.toString() ?? 'Unexpected worker response.';
        onLog(AgentStep(type: AgentStepType.done, title: 'Agent finished', detail: msg));
        _messages.add(AgentMessage(role: 'assistant', content: msg));
        return;
      }

      final assistantMessage = body['assistant_message']?.toString() ?? '';
      final rawToolCalls = body['tool_calls'];
      final toolCalls = _normalizeToolCalls(rawToolCalls);
      if (toolCalls.isEmpty) {
        onLog(AgentStep(
          type: AgentStepType.error,
          title: 'No tool calls returned',
          detail: assistantMessage.isNotEmpty ? assistantMessage : 'Worker returned an empty tool call list.',
        ));
        return;
      }

      _messages.add(AgentMessage(
        role: 'assistant',
        content: assistantMessage,
        toolCalls: toolCalls.map((tc) => tc.toMessageJson()).toList(),
      ));

      if (assistantMessage.isNotEmpty) {
        onLog(AgentStep(type: AgentStepType.assistant, title: 'Assistant', detail: assistantMessage));
      }

      final ordered = _orderToolCalls(toolCalls);
      bool doneSeen = false;
      bool screenStateDirty = false;

      for (final tc in ordered) {
        if (_stopRequested) {
          onLog(AgentStep(type: AgentStepType.info, title: 'Agent stopped', detail: 'Stopped by user.'));
          return;
        }

        if (tc.name == 'done') {
          final msg = tc.args['message']?.toString() ?? 'Done.';
          onLog(AgentStep(type: AgentStepType.toolCall, title: 'Tool: done', detail: msg));
          _messages.add(AgentMessage(
            role: 'tool',
            name: 'done',
            toolCallId: tc.id,
            content: jsonEncode({'ok': true, 'message': msg}),
          ));
          onLog(AgentStep(type: AgentStepType.done, title: 'Agent finished', detail: msg));
          doneSeen = true;
          break;
        }

        if (tc.name == 'ask_confirmation') {
          final question = tc.args['message']?.toString() ?? 'Do you want to proceed?';
          onLog(AgentStep(type: AgentStepType.toolCall, title: 'Confirmation requested', detail: question));
          final approved = await onConfirmation(question);
          final result = {'approved': approved};
          onLog(AgentStep(
            type: AgentStepType.toolResult,
            title: approved ? 'Confirmation approved' : 'Confirmation denied',
            detail: question,
          ));
          _messages.add(AgentMessage(
            role: 'tool',
            name: tc.name,
            toolCallId: tc.id,
            content: jsonEncode(result),
          ));
          continue;
        }

        final isScreen = screenTools.contains(tc.name);
        if (isScreen && _screenActionCount >= maxScreenActions) {
          final msg =
              'Screen action cap reached ($maxScreenActions). Refusing further screen actions.';
          onLog(AgentStep(type: AgentStepType.error, title: 'Screen cap reached', detail: tc.name));
          _messages.add(AgentMessage(
            role: 'tool',
            name: tc.name,
            toolCallId: tc.id,
            content: jsonEncode({'ok': false, 'error': msg}),
          ));
          continue;
        }

        onLog(AgentStep(
          type: AgentStepType.toolCall,
          title: 'Tool: ${tc.name}',
          detail: jsonEncode(tc.args),
          isScreenAction: isScreen,
        ));

        final result = await _executeTool(tc);
        if (isScreen) {
          _screenActionCount++;
          screenStateDirty = true;
        }

        onLog(AgentStep(
          type: AgentStepType.toolResult,
          title: 'Result: ${tc.name}',
          detail: _truncate(jsonEncode(result), 2000),
          isScreenAction: isScreen,
        ));

        _messages.add(AgentMessage(
          role: 'tool',
          name: tc.name,
          toolCallId: tc.id,
          content: jsonEncode(result),
        ));
      }

      if (doneSeen) return;

      if (screenStateDirty) {
        lastScreenState = await PlatformService.getScreenStateJson();
        if (lastScreenState.length > 12000) {
          lastScreenState = lastScreenState.substring(0, 12000);
        }
      }
    }

    onLog(AgentStep(
      type: AgentStepType.error,
      title: 'Iteration limit reached',
      detail: 'The agent stopped after $maxIterations iterations.',
    ));
  }

  Uri _buildAgentUri(String workerUrl) {
    final trimmed = workerUrl.trim();
    final base = Uri.parse(trimmed);
    if (base.path.isEmpty || base.path == '/') {
      return base.replace(path: '/');
    }
    if (base.path.endsWith('/auto-reply')) {
      final newPath = base.path.substring(0, base.path.length - '/auto-reply'.length);
      return base.replace(path: newPath.isEmpty ? '/' : newPath);
    }
    return base;
  }

  List<_ToolCall> _normalizeToolCalls(dynamic raw) {
    if (raw is! List) return [];
    final out = <_ToolCall>[];
    for (int i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final fn = map['function'];
      String name = '';
      dynamic args = {};
      if (fn is Map) {
        name = fn['name']?.toString() ?? '';
        args = fn['arguments'];
      } else {
        name = map['name']?.toString() ?? '';
        args = map['arguments'];
      }
      if (args is String) {
        try {
          args = jsonDecode(args);
        } catch (_) {
          args = {'_raw': args};
        }
      }
      if (args is! Map) args = <String, dynamic>{};
      final id = map['id']?.toString() ?? 'call_$i';
      if (name.isEmpty) continue;
      out.add(_ToolCall(id: id, name: name, args: Map<String, dynamic>.from(args)));
    }
    return out;
  }

  List<_ToolCall> _orderToolCalls(List<_ToolCall> calls) {
    int rank(String name) {
      if (silentTools.contains(name)) return 0;
      if (name == 'ask_confirmation' || name == 'done') return 1;
      if (screenTools.contains(name)) return 2;
      return 1;
    }

    final indexed = calls.asMap().entries.toList();
    indexed.sort((a, b) {
      final ra = rank(a.value.name);
      final rb = rank(b.value.name);
      if (ra != rb) return ra.compareTo(rb);
      return a.key.compareTo(b.key);
    });
    return indexed.map((e) => e.value).toList();
  }

  Future<Map<String, dynamic>> _executeTool(_ToolCall tc) async {
    try {
      switch (tc.name) {
        case 'read_notifications':
          final limit = _asInt(tc.args['limit']) ?? 10;
          final json = await PlatformService.getRecentNotifications(limit: limit.clamp(1, 50));
          final decoded = jsonDecode(json);
          return {'ok': true, 'notifications': decoded};
        case 'reply_notification':
          final key = tc.args['notificationKey']?.toString() ?? '';
          final message = tc.args['message']?.toString() ?? '';
          if (key.isEmpty || message.isEmpty) {
            return {'ok': false, 'error': 'notificationKey and message are required'};
          }
          final ok = await PlatformService.replyToNotification(notificationKey: key, message: message);
          return {'ok': ok};
        case 'make_call':
          final phoneNumber = tc.args['phoneNumber']?.toString() ?? '';
          if (phoneNumber.isEmpty) return {'ok': false, 'error': 'phoneNumber is required'};
          final ok = await PlatformService.makeCall(phoneNumber);
          return {'ok': ok, 'phoneNumber': phoneNumber};
        case 'send_sms':
          final phoneNumber = tc.args['phoneNumber']?.toString() ?? '';
          final message = tc.args['message']?.toString() ?? '';
          if (phoneNumber.isEmpty || message.isEmpty) {
            return {'ok': false, 'error': 'phoneNumber and message are required'};
          }
          final ok = await PlatformService.sendSms(phoneNumber: phoneNumber, message: message);
          return {'ok': ok, 'phoneNumber': phoneNumber};
        case 'open_whatsapp_chat':
          final phoneNumber = tc.args['phoneNumber']?.toString() ?? '';
          final message = tc.args['message']?.toString() ?? '';
          if (phoneNumber.isEmpty) return {'ok': false, 'error': 'phoneNumber is required'};
          final ok = await PlatformService.openWhatsAppChat(phoneNumber: phoneNumber, message: message);
          return {'ok': ok, 'phoneNumber': phoneNumber};
        case 'set_alarm':
          final hour = _asInt(tc.args['hour']);
          final minute = _asInt(tc.args['minute']);
          final message = tc.args['message']?.toString();
          if (hour == null || minute == null) {
            return {'ok': false, 'error': 'hour and minute are required'};
          }
          final ok = await PlatformService.setAlarm(hour: hour, minute: minute, message: message);
          return {'ok': ok, 'hour': hour, 'minute': minute};
        case 'save_note':
          final title = tc.args['title']?.toString() ?? '';
          final content = tc.args['content']?.toString() ?? '';
          if (title.isEmpty || content.isEmpty) {
            return {'ok': false, 'error': 'title and content are required'};
          }
          final ok = await PlatformService.saveNote(title: title, content: content);
          // Also mirror into persistent memory notes
          await _appendMemoryNote(title, content);
          return {'ok': ok};
        case 'read_notes':
          final limit = (_asInt(tc.args['limit']) ?? 20).clamp(1, 100);
          final query = tc.args['query']?.toString().toLowerCase().trim() ?? '';
          final nativeJson = await PlatformService.getNotes();
          final nativeNotes = _decodeJsonList(nativeJson);
          final memoryNotes = await SettingsService.getMemoryNotes();
          final merged = <Map<String, dynamic>>[];
          merged.addAll(nativeNotes);
          merged.addAll(memoryNotes);
          final filtered = merged.where((n) {
            if (query.isEmpty) return true;
            final title = n['title']?.toString().toLowerCase() ?? '';
            final content = n['content']?.toString().toLowerCase() ?? '';
            return title.contains(query) || content.contains(query);
          }).toList();
          final limited = filtered.length > limit ? filtered.sublist(filtered.length - limit) : filtered;
          return {'ok': true, 'notes': limited};
        case 'manage_booking':
          return await _manageBooking(tc.args);
        case 'open_app':
          final packageOrName = tc.args['packageOrName']?.toString() ??
              tc.args['package']?.toString() ??
              tc.args['name']?.toString() ??
              '';
          if (packageOrName.isEmpty) {
            return {'ok': false, 'error': 'packageOrName is required'};
          }
          final ok = await PlatformService.openApp(packageOrName);
          return {'ok': ok, 'packageOrName': packageOrName};
        case 'click_text':
          final target = tc.args['target']?.toString() ?? '';
          if (target.isEmpty) return {'ok': false, 'error': 'target is required'};
          final ok = await PlatformService.clickText(target);
          return {'ok': ok, 'target': target};
        case 'type_text':
          final targetOrFocused = tc.args['targetOrFocused']?.toString();
          final text = tc.args['text']?.toString() ?? '';
          final ok = await PlatformService.typeText(targetOrFocused: targetOrFocused, text: text);
          return {'ok': ok};
        case 'scroll_screen':
          final direction = tc.args['direction']?.toString() ?? 'down';
          final ok = await PlatformService.scrollScreen(direction);
          return {'ok': ok, 'direction': direction};
        case 'press_global':
          final action = tc.args['action']?.toString() ?? '';
          if (action.isEmpty) return {'ok': false, 'error': 'action is required'};
          final ok = await PlatformService.pressGlobal(action);
          return {'ok': ok, 'action': action};
        default:
          return {'ok': false, 'error': 'Unknown tool: ${tc.name}'};
      }
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  Future<void> _appendMemoryNote(String title, String content) async {
    if (!await SettingsService.getMemoryEnabled()) return;
    final notes = await SettingsService.getMemoryNotes();
    notes.add({
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'title': title,
      'content': content,
      'createdAt': DateTime.now().toIso8601String(),
    });
    if (notes.length > 200) {
      notes.removeRange(0, notes.length - 200);
    }
    await SettingsService.setMemoryNotes(notes);
  }

  Future<Map<String, dynamic>> _manageBooking(Map<String, dynamic> args) async {
    final action = args['action']?.toString().toLowerCase().trim() ?? '';
    final bookings = await SettingsService.getMemoryBookings();

    if (action == 'list') {
      final query = args['query']?.toString().toLowerCase().trim() ?? '';
      final filtered = bookings.where((b) {
        if (query.isEmpty) return true;
        final haystack = [
          b['clientName'],
          b['phoneNumber'],
          b['service'],
          b['dateTime'],
          b['status'],
          b['notes'],
        ].map((e) => e?.toString().toLowerCase() ?? '').join(' ');
        return haystack.contains(query);
      }).toList();
      return {'ok': true, 'bookings': filtered};
    }

    if (action == 'create') {
      final booking = {
        'id': 'bk_${DateTime.now().millisecondsSinceEpoch}',
        'clientName': args['clientName']?.toString().trim() ?? '',
        'phoneNumber': args['phoneNumber']?.toString().trim() ?? '',
        'service': args['service']?.toString().trim() ?? '',
        'dateTime': args['dateTime']?.toString().trim() ?? '',
        'status': args['status']?.toString().trim().isNotEmpty == true
            ? args['status'].toString().trim()
            : 'pending',
        'notes': args['notes']?.toString().trim() ?? '',
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      };
      bookings.add(booking);
      await SettingsService.setMemoryBookings(bookings);
      await _upsertMemoryContact(booking['clientName'].toString(), booking['phoneNumber'].toString());
      return {'ok': true, 'booking': booking, 'bookings': bookings};
    }

    if (action == 'update' || action == 'cancel') {
      final bookingId = args['bookingId']?.toString().trim() ?? '';
      final index = bookings.indexWhere((b) => b['id']?.toString() == bookingId);
      if (index < 0) {
        return {'ok': false, 'error': 'Booking not found', 'bookingId': bookingId};
      }
      final existing = Map<String, dynamic>.from(bookings[index]);
      if (action == 'cancel') {
        existing['status'] = 'cancelled';
      } else {
        if (args['clientName'] != null) existing['clientName'] = args['clientName'].toString().trim();
        if (args['phoneNumber'] != null) existing['phoneNumber'] = args['phoneNumber'].toString().trim();
        if (args['service'] != null) existing['service'] = args['service'].toString().trim();
        if (args['dateTime'] != null) existing['dateTime'] = args['dateTime'].toString().trim();
        if (args['status'] != null) existing['status'] = args['status'].toString().trim();
        if (args['notes'] != null) existing['notes'] = args['notes'].toString().trim();
      }
      existing['updatedAt'] = DateTime.now().toIso8601String();
      bookings[index] = existing;
      await SettingsService.setMemoryBookings(bookings);
      await _upsertMemoryContact(
        existing['clientName']?.toString() ?? '',
        existing['phoneNumber']?.toString() ?? '',
      );
      return {'ok': true, 'booking': existing, 'bookings': bookings};
    }

    return {'ok': false, 'error': 'Unsupported booking action: $action'};
  }

  Future<void> _upsertMemoryContact(String name, String phone) async {
    final n = name.trim();
    final p = phone.trim();
    if (n.isEmpty && p.isEmpty) return;
    final contacts = await SettingsService.getMemoryContacts();
    final idx = contacts.indexWhere((c) {
      final cp = c['phoneNumber']?.toString().trim() ?? '';
      final cn = c['name']?.toString().trim().toLowerCase() ?? '';
      if (p.isNotEmpty && cp.isNotEmpty) return cp == p;
      if (n.isNotEmpty && cn.isNotEmpty) return cn == n.toLowerCase();
      return false;
    });
    final entry = {
      'name': n,
      'phoneNumber': p,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    if (idx >= 0) {
      contacts[idx] = {...contacts[idx], ...entry};
    } else {
      contacts.add(entry);
    }
    await SettingsService.setMemoryContacts(contacts);
  }

  List<Map<String, dynamic>> _decodeJsonList(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  String _safeBody(String body) {
    if (body.length <= 1000) return body;
    return '${body.substring(0, 1000)}...';
  }

  String _truncate(String s, int max) {
    if (s.length <= max) return s;
    return '${s.substring(0, max)}...';
  }
}

class _ToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> args;

  _ToolCall({required this.id, required this.name, required this.args});

  Map<String, dynamic> toMessageJson() => {
        'id': id,
        'type': 'function',
        'function': {
          'name': name,
          'arguments': jsonEncode(args),
        },
      };
}
