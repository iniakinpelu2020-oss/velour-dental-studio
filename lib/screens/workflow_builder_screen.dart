import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/agent_models.dart';
import '../services/agent_service.dart';
import '../services/platform_service.dart';
import '../services/settings_service.dart';

class WorkflowBuilderScreen extends StatefulWidget {
  const WorkflowBuilderScreen({super.key});

  @override
  State<WorkflowBuilderScreen> createState() => _WorkflowBuilderScreenState();
}

class _WorkflowBuilderScreenState extends State<WorkflowBuilderScreen> {
  List<Map<String, dynamic>> _workflows = [];
  String? _selectedWorkflowId;
  bool _loading = true;
  bool _running = false;
  final List<String> _runLog = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final workflows = await SettingsService.getWorkflows();
    if (!mounted) return;
    setState(() {
      _workflows = workflows;
      if (_workflows.isEmpty) {
        _workflows = [_defaultReceptionistWorkflow()];
      }
      _selectedWorkflowId ??= _workflows.first['id']?.toString();
      _loading = false;
    });
    await _save();
  }

  Map<String, dynamic> _defaultReceptionistWorkflow() {
    return {
      'id': 'wf_receptionist_default',
      'name': 'Receptionist / Booking & Follow-up',
      'enabled': true,
      'steps': [
        _step('trigger', 'New booking request', {'trigger': 'manual_or_message', 'details': 'Capture incoming booking request'}),
        _step('condition', 'Has client name and phone?', {'condition': 'client_name_and_phone_present', 'onFalse': 'ask_for_missing_details'}),
        _step('background', 'Save booking to memory', {'action': 'manage_booking', 'status': 'pending'}),
        _step('phone_sms', 'Send confirmation SMS/WhatsApp', {'action': 'send_sms_or_whatsapp', 'template': 'Hi {clientName}, your {service} booking is confirmed for {dateTime}.'}),
        _step('background', 'Schedule post-visit follow-up note', {'action': 'save_note', 'title': 'Post-visit follow-up', 'content': 'Follow up with {clientName} at {phoneNumber} after {service}.'}),
        _step('agent', 'Run receptionist agent', {'command': 'Receptionist / Booking & Follow-up mode: capture client name and phone number, confirm booking, send reminder, and plan post-visit follow-up.'}),
      ],
    };
  }

  Map<String, dynamic> _step(String type, String title, Map<String, dynamic> config) {
    return {
      'id': 'step_${DateTime.now().microsecondsSinceEpoch}_${title.hashCode}',
      'type': type,
      'title': title,
      'enabled': true,
      'config': config,
    };
  }

  Map<String, dynamic>? get _selectedWorkflow {
    for (final wf in _workflows) {
      if (wf['id']?.toString() == _selectedWorkflowId) return wf;
    }
    return _workflows.isNotEmpty ? _workflows.first : null;
  }

  Future<void> _save() async {
    await SettingsService.setWorkflows(_workflows);
  }

  Future<void> _addWorkflow() async {
    final nameController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ApexAgentApp.surface,
        title: const Text('New workflow'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Workflow name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameController.text.trim().isEmpty ? 'New Workflow' : nameController.text.trim();
    final wf = {
      'id': 'wf_${DateTime.now().millisecondsSinceEpoch}',
      'name': name,
      'enabled': true,
      'steps': <Map<String, dynamic>>[
        _step('trigger', 'Manual trigger', {'trigger': 'manual'}),
      ],
    };
    setState(() {
      _workflows.add(wf);
      _selectedWorkflowId = wf['id'].toString();
    });
    await _save();
  }

  Future<void> _deleteWorkflow(Map<String, dynamic> wf) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ApexAgentApp.surface,
        title: const Text('Delete workflow?'),
        content: Text('Delete "${wf['name'] ?? 'Workflow'}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _workflows.removeWhere((w) => w['id'] == wf['id']);
      if (_selectedWorkflowId == wf['id']?.toString()) {
        _selectedWorkflowId = _workflows.isNotEmpty ? _workflows.first['id']?.toString() : null;
      }
    });
    await _save();
  }

  List<Map<String, dynamic>> _stepsOf(Map<String, dynamic> wf) {
    final raw = wf['steps'];
    if (raw is List) {
      return raw.whereType<Map>().map((e) => e.map((k, v) => MapEntry(k.toString(), v))).toList();
    }
    return [];
  }

  Future<void> _updateSelectedWorkflow(Map<String, dynamic> updated) async {
    final idx = _workflows.indexWhere((w) => w['id'] == updated['id']);
    if (idx < 0) return;
    setState(() => _workflows[idx] = updated);
    await _save();
  }

  Future<void> _addStep() async {
    final wf = _selectedWorkflow;
    if (wf == null) return;
    final type = await _pickStepType();
    if (type == null) return;
    final steps = _stepsOf(wf);
    steps.add(_step(type, _defaultTitleForType(type), _defaultConfigForType(type)));
    wf['steps'] = steps;
    await _updateSelectedWorkflow(wf);
  }

  String _defaultTitleForType(String type) {
    switch (type) {
      case 'trigger':
        return 'Trigger';
      case 'condition':
        return 'Condition';
      case 'background':
        return 'Background action';
      case 'phone_sms':
        return 'Phone/SMS action';
      case 'screen':
        return 'Screen/reply action';
      case 'agent':
        return 'Agent command';
      default:
        return 'Step';
    }
  }

  Map<String, dynamic> _defaultConfigForType(String type) {
    switch (type) {
      case 'trigger':
        return {'trigger': 'manual'};
      case 'condition':
        return {'condition': 'always_true', 'notes': ''};
      case 'background':
        return {'action': 'save_note', 'title': 'Workflow note', 'content': ''};
      case 'phone_sms':
        return {'action': 'send_sms', 'phoneNumber': '', 'message': ''};
      case 'screen':
        return {'action': 'reply_notification', 'notificationKey': '', 'message': ''};
      case 'agent':
        return {'command': ''};
      default:
        return {};
    }
  }

  Future<String?> _pickStepType() async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: ApexAgentApp.surface,
        title: const Text('Add step'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'trigger'), child: const Text('Trigger')),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'condition'), child: const Text('Condition')),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'background'), child: const Text('Background action')),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'phone_sms'), child: const Text('Phone/SMS action')),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'screen'), child: const Text('Screen/reply action')),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'agent'), child: const Text('Agent command')),
        ],
      ),
    );
  }

  Future<void> _editStep(Map<String, dynamic> wf, int index) async {
    final steps = _stepsOf(wf);
    if (index < 0 || index >= steps.length) return;
    final step = Map<String, dynamic>.from(steps[index]);
    final config = Map<String, dynamic>.from((step['config'] as Map?)?.map((k, v) => MapEntry(k.toString(), v)) ?? {});
    final titleController = TextEditingController(text: step['title']?.toString() ?? '');
    final configController = TextEditingController(text: const JsonEncoder.withIndent('  ').convert(config));

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ApexAgentApp.surface,
        title: const Text('Edit step'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Step title')),
              const SizedBox(height: 12),
              TextField(
                controller: configController,
                minLines: 6,
                maxLines: 14,
                decoration: const InputDecoration(
                  labelText: 'Config (JSON)',
                  hintText: '{"action":"send_sms","phoneNumber":"+234...","message":"..."}',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved != true) return;

    try {
      final decoded = jsonDecode(configController.text.trim().isEmpty ? '{}' : configController.text);
      final nextConfig = decoded is Map
          ? decoded.map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{};
      step['title'] = titleController.text.trim().isEmpty ? step['title'] : titleController.text.trim();
      step['config'] = nextConfig;
      steps[index] = step;
      wf['steps'] = steps;
      await _updateSelectedWorkflow(wf);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invalid JSON config: $e')));
    }
  }

  Future<void> _deleteStep(Map<String, dynamic> wf, int index) async {
    final steps = _stepsOf(wf);
    if (index < 0 || index >= steps.length) return;
    steps.removeAt(index);
    wf['steps'] = steps;
    await _updateSelectedWorkflow(wf);
  }

  Future<void> _toggleStep(Map<String, dynamic> wf, int index, bool enabled) async {
    final steps = _stepsOf(wf);
    if (index < 0 || index >= steps.length) return;
    final step = Map<String, dynamic>.from(steps[index]);
    step['enabled'] = enabled;
    steps[index] = step;
    wf['steps'] = steps;
    await _updateSelectedWorkflow(wf);
  }

  Future<void> _moveStep(Map<String, dynamic> wf, int oldIndex, int newIndex) async {
    final steps = _stepsOf(wf);
    if (oldIndex < 0 || oldIndex >= steps.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex < 0 || newIndex >= steps.length) return;
    final item = steps.removeAt(oldIndex);
    steps.insert(newIndex, item);
    wf['steps'] = steps;
    await _updateSelectedWorkflow(wf);
  }

  Future<void> _runWorkflow() async {
    final wf = _selectedWorkflow;
    if (wf == null || _running) return;
    final steps = _stepsOf(wf);
    setState(() {
      _running = true;
      _runLog.clear();
      _runLog.add('Running workflow: ${wf['name'] ?? 'Workflow'}');
    });

    try {
      for (int i = 0; i < steps.length; i++) {
        final step = Map<String, dynamic>.from(steps[i]);
        final enabled = step['enabled'] != false;
        final type = step['type']?.toString() ?? 'unknown';
        final title = step['title']?.toString() ?? 'Step ${i + 1}';
        final config = Map<String, dynamic>.from((step['config'] as Map?)?.map((k, v) => MapEntry(k.toString(), v)) ?? {});
        if (!enabled) {
          _appendRunLog('SKIP [$type] $title');
          continue;
        }
        _appendRunLog('START [$type] $title');
        final ok = await _executeStep(type, config);
        _appendRunLog('${ok ? 'OK' : 'FAIL'} [$type] $title');
      }
      _appendRunLog('Workflow completed');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<bool> _executeStep(String type, Map<String, dynamic> config) async {
    try {
      switch (type) {
        case 'trigger':
          return true;
        case 'condition':
          // Simple condition evaluation: always_true by default; otherwise pass.
          final condition = config['condition']?.toString() ?? 'always_true';
          if (condition == 'always_true' || condition.isEmpty) return true;
          return true;
        case 'background':
          return await _executeBackground(config);
        case 'phone_sms':
          return await _executePhoneSms(config);
        case 'screen':
          return await _executeScreen(config);
        case 'agent':
          return await _executeAgent(config);
        default:
          return false;
      }
    } catch (e) {
      _appendRunLog('ERROR: $e');
      return false;
    }
  }

  Future<bool> _executeBackground(Map<String, dynamic> config) async {
    final action = config['action']?.toString() ?? 'save_note';
    if (action == 'save_note') {
      final title = config['title']?.toString() ?? 'Workflow note';
      final content = config['content']?.toString() ?? '';
      return PlatformService.saveNote(title: title, content: content);
    }
    if (action == 'manage_booking') {
      final bookings = await SettingsService.getMemoryBookings();
      bookings.add({
        'id': 'bk_${DateTime.now().millisecondsSinceEpoch}',
        'clientName': config['clientName']?.toString() ?? '',
        'phoneNumber': config['phoneNumber']?.toString() ?? '',
        'service': config['service']?.toString() ?? '',
        'dateTime': config['dateTime']?.toString() ?? '',
        'status': config['status']?.toString() ?? 'pending',
        'notes': config['notes']?.toString() ?? '',
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
      await SettingsService.setMemoryBookings(bookings);
      return true;
    }
    if (action == 'set_alarm') {
      final hour = int.tryParse(config['hour']?.toString() ?? '') ?? 9;
      final minute = int.tryParse(config['minute']?.toString() ?? '') ?? 0;
      final message = config['message']?.toString();
      return PlatformService.setAlarm(hour: hour, minute: minute, message: message);
    }
    return false;
  }

  Future<bool> _executePhoneSms(Map<String, dynamic> config) async {
    final action = config['action']?.toString() ?? 'send_sms';
    final phone = config['phoneNumber']?.toString() ?? '';
    final message = config['message']?.toString() ?? '';
    if (action == 'make_call') {
      return PlatformService.makeCall(phone);
    }
    if (action == 'open_whatsapp_chat' || action == 'send_sms_or_whatsapp') {
      if (action == 'send_sms_or_whatsapp') {
        final smsOk = await PlatformService.sendSms(phoneNumber: phone, message: message);
        if (smsOk) return true;
      }
      return PlatformService.openWhatsAppChat(phoneNumber: phone, message: message);
    }
    return PlatformService.sendSms(phoneNumber: phone, message: message);
  }

  Future<bool> _executeScreen(Map<String, dynamic> config) async {
    final action = config['action']?.toString() ?? 'reply_notification';
    if (action == 'reply_notification') {
      final key = config['notificationKey']?.toString() ?? '';
      final message = config['message']?.toString() ?? '';
      if (key.isEmpty || message.isEmpty) return false;
      return PlatformService.replyToNotification(notificationKey: key, message: message);
    }
    if (action == 'open_app') {
      return PlatformService.openApp(config['packageOrName']?.toString() ?? '');
    }
    if (action == 'click_text') {
      return PlatformService.clickText(config['target']?.toString() ?? '');
    }
    if (action == 'type_text') {
      return PlatformService.typeText(
        targetOrFocused: config['targetOrFocused']?.toString(),
        text: config['text']?.toString() ?? '',
      );
    }
    if (action == 'scroll_screen') {
      return PlatformService.scrollScreen(config['direction']?.toString() ?? 'down');
    }
    if (action == 'press_global') {
      return PlatformService.pressGlobal(config['action']?.toString() ?? 'BACK');
    }
    return false;
  }

  Future<bool> _executeAgent(Map<String, dynamic> config) async {
    final command = config['command']?.toString().trim() ?? '';
    if (command.isEmpty) return false;
    final completer = Completer<bool>();
    bool sawDone = false;
    late AgentService service;
    service = AgentService(
      onLog: (step) {
        _appendRunLog('AGENT: ${step.title}${step.detail.isNotEmpty ? " - ${step.detail}" : ""}');
        if (step.type == AgentStepType.done) sawDone = true;
      },
      onStateChanged: (running) {
        if (!running && !completer.isCompleted) {
          completer.complete(sawDone);
        }
      },
      onConfirmation: (msg) async {
        if (!mounted) return false;
        final res = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: ApexAgentApp.surface,
            title: const Text('Workflow confirmation'),
            content: Text(msg),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Deny')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approve')),
            ],
          ),
        );
        return res ?? false;
      },
    );
    unawaited(service.runCommand(command));
    return completer.future.timeout(const Duration(minutes: 5), onTimeout: () {
      service.stop();
      return false;
    });
  }

  void _appendRunLog(String line) {
    if (!mounted) return;
    setState(() {
      _runLog.add('[${DateTime.now().toIso8601String().substring(11, 19)}] $line');
    });
  }

  @override
  Widget build(BuildContext context) {
    final wf = _selectedWorkflow;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Visual Workflow Builder'),
        actions: [
          IconButton(onPressed: _addWorkflow, icon: const Icon(Icons.add_box_outlined), tooltip: 'New workflow'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: _buildWorkflowSelector(wf),
                ),
                if (wf != null)
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        _buildWorkflowHeader(wf),
                        const SizedBox(height: 12),
                        _buildStepsEditor(wf),
                        const SizedBox(height: 12),
                        _buildRunLogCard(),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildWorkflowSelector(Map<String, dynamic>? wf) {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: wf?['id']?.toString(),
            dropdownColor: ApexAgentApp.surfaceAlt,
            decoration: const InputDecoration(labelText: 'Workflow'),
            items: _workflows
                .map((w) => DropdownMenuItem<String>(
                      value: w['id']?.toString(),
                      child: Text(w['name']?.toString() ?? 'Workflow'),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _selectedWorkflowId = v),
          ),
        ),
        const SizedBox(width: 8),
        if (wf != null)
          IconButton(
            onPressed: () => _deleteWorkflow(wf),
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete workflow',
          ),
      ],
    );
  }

  Widget _buildWorkflowHeader(Map<String, dynamic> wf) {
    final enabled = wf['enabled'] != false;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    wf['name']?.toString() ?? 'Workflow',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                Switch.adaptive(
                  value: enabled,
                  activeColor: ApexAgentApp.accent,
                  onChanged: (v) async {
                    wf['enabled'] = v;
                    await _updateSelectedWorkflow(wf);
                  },
                ),
              ],
            ),
            const Text(
              'Visual step flow: trigger -> condition/background/phone/SMS action -> screen/reply/agent action. Add, reorder, toggle, save, and run multi-step workflows.',
              style: TextStyle(color: ApexAgentApp.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _running ? null : _runWorkflow,
                  icon: _running
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.play_arrow),
                  label: Text(_running ? 'Running...' : 'Run Workflow'),
                ),
                OutlinedButton.icon(onPressed: _addStep, icon: const Icon(Icons.add), label: const Text('Add Step')),
                OutlinedButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('Save Flow')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepsEditor(Map<String, dynamic> wf) {
    final steps = _stepsOf(wf);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Flow Steps', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Drag to reorder. Toggle steps on/off. Edit config to connect actions.', style: TextStyle(color: ApexAgentApp.muted, fontSize: 13)),
            const SizedBox(height: 12),
            if (steps.isEmpty)
              const Text('No steps yet.', style: TextStyle(color: ApexAgentApp.muted))
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: steps.length,
                onReorder: (oldIndex, newIndex) => _moveStep(wf, oldIndex, newIndex),
                itemBuilder: (context, index) {
                  final step = Map<String, dynamic>.from(steps[index]);
                  final enabled = step['enabled'] != false;
                  final type = step['type']?.toString() ?? 'step';
                  final title = step['title']?.toString() ?? 'Step';
                  final config = Map<String, dynamic>.from((step['config'] as Map?)?.map((k, v) => MapEntry(k.toString(), v)) ?? {});
                  return Container(
                    key: ValueKey(step['id']?.toString() ?? 'step_$index'),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: ApexAgentApp.surfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF263241)),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: ReorderableDragStartListener(
                            index: index,
                            child: const Icon(Icons.drag_indicator),
                          ),
                          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(type.toUpperCase(), style: TextStyle(color: _typeColor(type), fontSize: 12, fontWeight: FontWeight.w700)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch.adaptive(
                                value: enabled,
                                activeColor: ApexAgentApp.accent,
                                onChanged: (v) => _toggleStep(wf, index, v),
                              ),
                              IconButton(onPressed: () => _editStep(wf, index), icon: const Icon(Icons.edit_outlined)),
                              IconButton(onPressed: () => _deleteStep(wf, index), icon: const Icon(Icons.delete_outline)),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  const JsonEncoder.withIndent('  ').convert(config),
                                  style: const TextStyle(color: ApexAgentApp.muted, fontSize: 12, fontFamily: 'monospace'),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (index < steps.length - 1)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: Icon(Icons.arrow_downward, color: ApexAgentApp.muted, size: 18),
                          ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRunLogCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: Text('Run Log', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                IconButton(
                  onPressed: _runLog.isEmpty ? null : () => setState(_runLog.clear),
                  icon: const Icon(Icons.clear_all),
                  tooltip: 'Clear log',
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_runLog.isEmpty)
              const Text('No workflow runs yet.', style: TextStyle(color: ApexAgentApp.muted))
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ApexAgentApp.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF263241)),
                ),
                child: SelectableText(
                  _runLog.join('\n'),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: ApexAgentApp.text, height: 1.4),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'trigger':
        return const Color(0xFF7CC4FF);
      case 'condition':
        return ApexAgentApp.warn;
      case 'background':
        return const Color(0xFF7EE787);
      case 'phone_sms':
        return const Color(0xFFB39DFF);
      case 'screen':
        return const Color(0xFFFF8A65);
      case 'agent':
        return ApexAgentApp.accent;
      default:
        return ApexAgentApp.muted;
    }
  }
}
