import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/agent_models.dart';
import '../services/agent_service.dart';
import '../services/platform_service.dart';

class AgentChatScreen extends StatefulWidget {
  const AgentChatScreen({super.key});

  @override
  State<AgentChatScreen> createState() => _AgentChatScreenState();
}

class _AgentChatScreenState extends State<AgentChatScreen> with WidgetsBindingObserver {
  final TextEditingController _commandController = TextEditingController();
  final ScrollController _logScrollController = ScrollController();
  final List<AgentStep> _steps = [];
  final DateFormat _timeFmt = DateFormat('HH:mm:ss');

  late final AgentService _agentService;
  Timer? _statusTimer;

  bool _accessibilityEnabled = false;
  bool _notificationListenerEnabled = false;
  bool _backgroundRunning = false;
  bool _isRunning = false;
  int _screenActionCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _agentService = AgentService(
      onLog: _onLog,
      onStateChanged: _onStateChanged,
      onConfirmation: _onConfirmation,
    );
    _refreshStatus();
    _statusTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refreshStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusTimer?.cancel();
    _commandController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
    }
  }

  Future<void> _refreshStatus() async {
    final status = await PlatformService.getDeviceStatus();
    if (!mounted) return;
    setState(() {
      _accessibilityEnabled = status['accessibilityEnabled'] ?? false;
      _notificationListenerEnabled = status['notificationListenerEnabled'] ?? false;
      _backgroundRunning = status['backgroundServiceRunning'] ?? false;
    });
  }

  void _onLog(AgentStep step) {
    if (!mounted) return;
    setState(() {
      _steps.add(step);
      if (step.isScreenAction && step.type == AgentStepType.toolResult) {
        _screenActionCount++;
      }
    });
    _scrollToBottom();
  }

  void _onStateChanged(bool running) {
    if (!mounted) return;
    setState(() {
      _isRunning = running;
      if (running) {
        _screenActionCount = 0;
      }
    });
    _refreshStatus();
  }

  Future<bool> _onConfirmation(String message) async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: ApexAgentApp.surface,
          title: const Text('Agent confirmation required'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Deny'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Approve'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_logScrollController.hasClients) return;
      _logScrollController.animateTo(
        _logScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendCommand() async {
    final cmd = _commandController.text.trim();
    if (cmd.isEmpty || _isRunning) return;
    _commandController.clear();
    FocusScope.of(context).unfocus();
    await _agentService.runCommand(cmd);
  }

  Future<void> _handleAccessibilityTap() async {
    await PlatformService.openAccessibilitySettings();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _refreshStatus();
  }

  Future<void> _handleNotificationsTap() async {
    await PlatformService.openNotificationListenerSettings();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _refreshStatus();
  }

  Future<void> _handleBackgroundTap() async {
    if (_backgroundRunning) {
      await PlatformService.stopBackgroundService();
    } else {
      await PlatformService.startBackgroundService();
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _refreshStatus();
  }

  void _clearLog() {
    setState(() {
      _steps.clear();
      _screenActionCount = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent Chat & Live Execution'),
        actions: [
          IconButton(
            tooltip: 'Refresh status',
            onPressed: _refreshStatus,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Clear log',
            onPressed: _steps.isEmpty ? null : _clearLog,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: _buildStatusPills(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildRoutingBanner(),
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildLog()),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildStatusPills() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _StatusPill(
          label: 'Accessibility',
          enabled: _accessibilityEnabled,
          icon: Icons.accessibility_new,
          onTap: _handleAccessibilityTap,
        ),
        _StatusPill(
          label: 'Notifications',
          enabled: _notificationListenerEnabled,
          icon: Icons.notifications_active_outlined,
          onTap: _handleNotificationsTap,
        ),
        _StatusPill(
          label: 'Background',
          enabled: _backgroundRunning,
          icon: Icons.miscellaneous_services_outlined,
          onTap: _handleBackgroundTap,
        ),
      ],
    );
  }

  Widget _buildRoutingBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ApexAgentApp.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1F2A37)),
      ),
      child: Row(
        children: [
          const Icon(Icons.alt_route, size: 18, color: ApexAgentApp.accent),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Silent-first routing • Screen actions capped at 10 steps',
              style: TextStyle(fontSize: 12, color: ApexAgentApp.muted),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _screenActionCount >= 10
                  ? ApexAgentApp.danger.withOpacity(0.15)
                  : ApexAgentApp.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$_screenActionCount/10',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _screenActionCount >= 10 ? ApexAgentApp.danger : ApexAgentApp.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLog() {
    if (_steps.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.terminal, size: 48, color: ApexAgentApp.muted),
              SizedBox(height: 12),
              Text(
                'No agent activity yet',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text(
                'Enter a command below. The agent will prefer silent background tools before screen UI tools.',
                textAlign: TextAlign.center,
                style: TextStyle(color: ApexAgentApp.muted),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _logScrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      itemCount: _steps.length,
      itemBuilder: (context, index) {
        final step = _steps[index];
        return _StepTile(step: step, timeFmt: _timeFmt);
      },
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: const BoxDecoration(
        color: Color(0xFF0D131B),
        border: Border(top: BorderSide(color: Color(0xFF1F2A37))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isRunning)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _agentService.stop,
                  icon: const Icon(Icons.stop_circle_outlined, color: ApexAgentApp.danger),
                  label: const Text(
                    'STOP AGENT',
                    style: TextStyle(color: ApexAgentApp.danger, fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: ApexAgentApp.danger),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commandController,
                  enabled: !_isRunning,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendCommand(),
                  decoration: InputDecoration(
                    hintText: _isRunning ? 'Agent is running...' : 'Tell Apex what to do...',
                    prefixIcon: const Icon(Icons.bolt_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 52,
                width: 52,
                child: ElevatedButton(
                  onPressed: _isRunning ? null : _sendCommand,
                  style: ElevatedButton.styleFrom(padding: EdgeInsets.zero),
                  child: _isRunning
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.send),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.enabled,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? ApexAgentApp.accent : ApexAgentApp.warn;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
            ),
            const SizedBox(width: 6),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.step, required this.timeFmt});

  final AgentStep step;
  final DateFormat timeFmt;

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(step.type);
    final icon = _iconFor(step.type);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ApexAgentApp.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1F2A37)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        step.title,
                        style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 13),
                      ),
                    ),
                    if (step.isScreenAction)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: ApexAgentApp.warn.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'SCREEN',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: ApexAgentApp.warn,
                          ),
                        ),
                      ),
                    Text(
                      timeFmt.format(step.timestamp),
                      style: const TextStyle(fontSize: 11, color: ApexAgentApp.muted),
                    ),
                  ],
                ),
                if (step.detail.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  SelectableText(
                    step.detail,
                    style: const TextStyle(fontSize: 13, color: ApexAgentApp.text, height: 1.35),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _colorFor(AgentStepType type) {
    switch (type) {
      case AgentStepType.info:
        return const Color(0xFF7CC4FF);
      case AgentStepType.user:
        return ApexAgentApp.accent;
      case AgentStepType.assistant:
        return const Color(0xFFB39DFF);
      case AgentStepType.toolCall:
        return ApexAgentApp.warn;
      case AgentStepType.toolResult:
        return const Color(0xFF7EE787);
      case AgentStepType.error:
        return ApexAgentApp.danger;
      case AgentStepType.done:
        return ApexAgentApp.accent;
    }
  }

  IconData _iconFor(AgentStepType type) {
    switch (type) {
      case AgentStepType.info:
        return Icons.info_outline;
      case AgentStepType.user:
        return Icons.person_outline;
      case AgentStepType.assistant:
        return Icons.smart_toy_outlined;
      case AgentStepType.toolCall:
        return Icons.build_outlined;
      case AgentStepType.toolResult:
        return Icons.check_circle_outline;
      case AgentStepType.error:
        return Icons.error_outline;
      case AgentStepType.done:
        return Icons.flag_outlined;
    }
  }
}
