import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../services/platform_service.dart';
import '../services/settings_service.dart';

class UniversalAutoReplyScreen extends StatefulWidget {
  const UniversalAutoReplyScreen({super.key});

  @override
  State<UniversalAutoReplyScreen> createState() => _UniversalAutoReplyScreenState();
}

class _UniversalAutoReplyScreenState extends State<UniversalAutoReplyScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  bool _masterEnabled = false;
  bool _requireConfirmation = true;
  bool _ignoreGroupChats = true;
  int _cooldownSeconds = 60;
  String _globalRule = '';

  Map<String, String> _appModes = {};
  Map<String, String> _appRules = {};
  Map<String, String> _contactRules = {};
  Map<String, String> _contactModes = {};
  List<String> _allowlist = [];
  List<String> _blocklist = [];

  List<Map<String, String>> _installedApps = [];
  List<Map<String, dynamic>> _history = [];
  Timer? _historyTimer;

  final TextEditingController _globalRuleController = TextEditingController();
  final TextEditingController _appSearchController = TextEditingController();
  final TextEditingController _allowlistController = TextEditingController();
  final TextEditingController _blocklistController = TextEditingController();
  final DateFormat _timeFmt = DateFormat('MM-dd HH:mm:ss');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _historyTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refreshHistory());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _historyTimer?.cancel();
    _globalRuleController.dispose();
    _appSearchController.dispose();
    _allowlistController.dispose();
    _blocklistController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshHistory();
      _reloadInstalledApps();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await SettingsService.reload();
    final master = await SettingsService.getMasterAutoReplyEnabled();
    final requireConf = await SettingsService.getRequireConfirmation();
    final ignoreGroups = await SettingsService.getIgnoreGroupChats();
    final cooldown = await SettingsService.getCooldownSeconds();
    final globalRule = await SettingsService.getGlobalRule();
    final appModes = await SettingsService.getAppModes();
    final appRules = await SettingsService.getAppRules();
    final contactRules = await SettingsService.getContactRules();
    final contactModes = await SettingsService.getContactModes();
    final allowlist = await SettingsService.getAllowlist();
    final blocklist = await SettingsService.getBlocklist();
    final apps = await PlatformService.getInstalledApps();
    final historyJson = await PlatformService.getAutoReplyHistory();

    if (!mounted) return;
    setState(() {
      _masterEnabled = master;
      _requireConfirmation = requireConf;
      _ignoreGroupChats = ignoreGroups;
      _cooldownSeconds = cooldown;
      _globalRule = globalRule;
      _globalRuleController.text = globalRule;
      _appModes = appModes;
      _appRules = appRules;
      _contactRules = contactRules;
      _contactModes = contactModes;
      _allowlist = allowlist;
      _blocklist = blocklist;
      _installedApps = apps;
      _history = _parseHistory(historyJson);
      _loading = false;
    });
  }

  Future<void> _reloadInstalledApps() async {
    final apps = await PlatformService.getInstalledApps();
    if (!mounted) return;
    setState(() => _installedApps = apps);
  }

  Future<void> _refreshHistory() async {
    final historyJson = await PlatformService.getAutoReplyHistory();
    if (!mounted) return;
    setState(() => _history = _parseHistory(historyJson));
  }

  List<Map<String, dynamic>> _parseHistory(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList()
            .reversed
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> _saveToggles() async {
    await SettingsService.setMasterAutoReplyEnabled(_masterEnabled);
    await SettingsService.setRequireConfirmation(_requireConfirmation);
    await SettingsService.setIgnoreGroupChats(_ignoreGroupChats);
    await SettingsService.setCooldownSeconds(_cooldownSeconds);
  }

  Future<void> _saveGlobalRule() async {
    _globalRule = _globalRuleController.text;
    await SettingsService.setGlobalRule(_globalRule);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Global rule saved')),
    );
  }

  Future<void> _setAppMode(String packageName, String mode) async {
    setState(() => _appModes[packageName] = mode);
    await SettingsService.setAppModes(_appModes);
  }

  Future<void> _saveAppRule(String packageName, String rule) async {
    setState(() {
      if (rule.trim().isEmpty) {
        _appRules.remove(packageName);
      } else {
        _appRules[packageName] = rule.trim();
      }
    });
    await SettingsService.setAppRules(_appRules);
  }

  Future<void> _saveContactRule(String contactKey, String rule) async {
    final key = contactKey.trim();
    if (key.isEmpty) return;
    setState(() {
      if (rule.trim().isEmpty) {
        _contactRules.remove(key);
      } else {
        _contactRules[key] = rule.trim();
      }
    });
    await SettingsService.setContactRules(_contactRules);
  }

  Future<void> _removeContactRule(String contactKey) async {
    setState(() => _contactRules.remove(contactKey));
    await SettingsService.setContactRules(_contactRules);
  }

  Future<void> _setContactMode(String contactKey, String mode) async {
    final key = contactKey.trim();
    if (key.isEmpty) return;
    setState(() {
      if (mode == 'off') {
        _contactModes.remove(key);
      } else {
        _contactModes[key] = mode;
      }
    });
    await SettingsService.setContactModes(_contactModes);
  }

  Future<void> _addToAllowlist() async {
    final value = _allowlistController.text.trim();
    if (value.isEmpty) return;
    if (!_allowlist.contains(value)) {
      setState(() => _allowlist.add(value));
      await SettingsService.setAllowlist(_allowlist);
    }
    _allowlistController.clear();
  }

  Future<void> _removeFromAllowlist(String value) async {
    setState(() => _allowlist.remove(value));
    await SettingsService.setAllowlist(_allowlist);
  }

  Future<void> _addToBlocklist() async {
    final value = _blocklistController.text.trim();
    if (value.isEmpty) return;
    if (!_blocklist.contains(value)) {
      setState(() => _blocklist.add(value));
      await SettingsService.setBlocklist(_blocklist);
    }
    _blocklistController.clear();
  }

  Future<void> _removeFromBlocklist(String value) async {
    setState(() => _blocklist.remove(value));
    await SettingsService.setBlocklist(_blocklist);
  }

  Future<void> _clearHistory() async {
    await PlatformService.clearAutoReplyHistory();
    await _refreshHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Universal Auto-Reply & Rules'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildMasterCard(),
                const SizedBox(height: 16),
                _buildGlobalRuleCard(),
                const SizedBox(height: 16),
                _buildContactsCard(),
                const SizedBox(height: 16),
                _buildContactRulesCard(),
                const SizedBox(height: 16),
                _buildAppsCard(),
                const SizedBox(height: 16),
                _buildHistoryCard(),
              ],
            ),
    );
  }

  Widget _buildMasterCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Auto-Reply Controls', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text(
              'Configure how Apex Agent handles incoming notification replies.',
              style: TextStyle(color: ApexAgentApp.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _masterEnabled,
              activeColor: ApexAgentApp.accent,
              title: const Text('Master Auto-Reply'),
              subtitle: const Text('Enable or disable auto-reply globally'),
              onChanged: (v) async {
                setState(() => _masterEnabled = v);
                await _saveToggles();
              },
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _requireConfirmation,
              activeColor: ApexAgentApp.accent,
              title: const Text('Require Approval Before Sending'),
              subtitle: const Text('Show an approval notification with Approve & Send / Dismiss'),
              onChanged: (v) async {
                setState(() => _requireConfirmation = v);
                await _saveToggles();
              },
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _ignoreGroupChats,
              activeColor: ApexAgentApp.accent,
              title: const Text('Ignore Group Chats'),
              subtitle: const Text('Skip auto-replies in group conversations (default: on)'),
              onChanged: (v) async {
                setState(() => _ignoreGroupChats = v);
                await _saveToggles();
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Per-sender cooldown',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${_cooldownSeconds}s',
                  style: const TextStyle(color: ApexAgentApp.accent, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            Slider(
              value: _cooldownSeconds.toDouble(),
              min: 0,
              max: 300,
              divisions: 30,
              label: '${_cooldownSeconds}s',
              activeColor: ApexAgentApp.accent,
              onChanged: (v) => setState(() => _cooldownSeconds = v.round()),
              onChangeEnd: (_) => _saveToggles(),
            ),
            const Text(
              'Prevents repeated auto-replies to the same sender within the cooldown window.',
              style: TextStyle(color: ApexAgentApp.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlobalRuleCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Global Custom Rule', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text(
              'Applied to all auto-replies. App/contact rules are added on top of this.',
              style: TextStyle(color: ApexAgentApp.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _globalRuleController,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'e.g., Be polite, keep replies short, and mention I am busy if needed.',
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _saveGlobalRule,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save Global Rule'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Contact Allowlist / Blocklist / Off',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text(
              'Add sender names or identifiers. Allowlist restricts auto-replies to listed contacts when non-empty. Blocklist always blocks. Use contact modes below for per-contact allow/block/off.',
              style: TextStyle(color: ApexAgentApp.muted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            _buildChipEditor(
              label: 'Allowlist',
              controller: _allowlistController,
              values: _allowlist,
              onAdd: _addToAllowlist,
              onRemove: _removeFromAllowlist,
              color: ApexAgentApp.accent,
            ),
            const SizedBox(height: 16),
            _buildChipEditor(
              label: 'Blocklist',
              controller: _blocklistController,
              values: _blocklist,
              onAdd: _addToBlocklist,
              onRemove: _removeFromBlocklist,
              color: ApexAgentApp.danger,
            ),
            const SizedBox(height: 16),
            _buildContactModeEditor(),
          ],
        ),
      ),
    );
  }

  Widget _buildChipEditor({
    required String label,
    required TextEditingController controller,
    required List<String> values,
    required VoidCallback onAdd,
    required void Function(String) onRemove,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(hintText: 'Add $label entry'),
                onSubmitted: (_) => onAdd(),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: onAdd, child: const Text('Add')),
          ],
        ),
        const SizedBox(height: 8),
        if (values.isEmpty)
          const Text('No entries', style: TextStyle(color: ApexAgentApp.muted, fontSize: 12))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: values
                .map(
                  (v) => InputChip(
                    label: Text(v),
                    onDeleted: () => onRemove(v),
                    deleteIconColor: color,
                    side: BorderSide(color: color.withOpacity(0.4)),
                    backgroundColor: color.withOpacity(0.08),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  Widget _buildContactModeEditor() {
    final entries = _contactModes.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Per-contact modes', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            OutlinedButton.icon(
              onPressed: _showAddContactModeDialog,
              icon: const Icon(Icons.person_add_alt_1, size: 18),
              label: const Text('Add contact'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          const Text(
            'No per-contact modes set. Use Add contact to set allow/block/off for a specific sender.',
            style: TextStyle(color: ApexAgentApp.muted, fontSize: 12),
          )
        else
          ...entries.map((e) => _buildContactModeRow(e.key, e.value)),
      ],
    );
  }

  Widget _buildContactModeRow(String key, String mode) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ApexAgentApp.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF263241)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(key, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          DropdownButton<String>(
            value: mode,
            dropdownColor: ApexAgentApp.surfaceAlt,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 'allow', child: Text('Allow')),
              DropdownMenuItem(value: 'block', child: Text('Block')),
              DropdownMenuItem(value: 'off', child: Text('Off')),
            ],
            onChanged: (v) {
              if (v == null) return;
              _setContactMode(key, v);
            },
          ),
          IconButton(
            tooltip: 'Remove',
            onPressed: () => _setContactMode(key, 'off'),
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddContactModeDialog() async {
    final controller = TextEditingController();
    String mode = 'allow';
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: ApexAgentApp.surface,
            title: const Text('Add contact mode'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Sender name or package|sender',
                    hintText: 'e.g., Alice or com.whatsapp|Alice',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: mode,
                  dropdownColor: ApexAgentApp.surfaceAlt,
                  items: const [
                    DropdownMenuItem(value: 'allow', child: Text('Allow')),
                    DropdownMenuItem(value: 'block', child: Text('Block')),
                    DropdownMenuItem(value: 'off', child: Text('Off')),
                  ],
                  onChanged: (v) => setDialogState(() => mode = v ?? 'allow'),
                  decoration: const InputDecoration(labelText: 'Mode'),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
            ],
          );
        });
      },
    );
    if (result == true) {
      final key = controller.text.trim();
      if (key.isNotEmpty) {
        await _setContactMode(key, mode);
      }
    }
  }

  Widget _buildContactRulesCard() {
    final entries = _contactRules.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Per-contact Custom Rules',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                OutlinedButton.icon(
                  onPressed: _showAddContactRuleDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add rule'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Custom rules for specific senders. Key can be a sender name or package|sender.',
              style: TextStyle(color: ApexAgentApp.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              const Text('No per-contact rules', style: TextStyle(color: ApexAgentApp.muted, fontSize: 12))
            else
              ...entries.map((e) => _buildRuleTile(
                    title: e.key,
                    rule: e.value,
                    onEdit: () => _showEditRuleDialog(
                      title: 'Edit contact rule',
                      keyLabel: 'Contact key',
                      initialKey: e.key,
                      initialRule: e.value,
                      keyReadOnly: true,
                      onSave: (k, r) => _saveContactRule(k, r),
                    ),
                    onDelete: () => _removeContactRule(e.key),
                  )),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddContactRuleDialog() async {
    await _showEditRuleDialog(
      title: 'Add contact rule',
      keyLabel: 'Sender name or package|sender',
      initialKey: '',
      initialRule: '',
      keyReadOnly: false,
      onSave: (k, r) => _saveContactRule(k, r),
    );
  }

  Widget _buildAppsCard() {
    final query = _appSearchController.text.trim().lowercase();
    final filtered = _installedApps.where((app) {
      if (query.isEmpty) return true;
      final name = (app['appName'] ?? '').toLowerCase();
      final pkg = (app['packageName'] ?? '').toLowerCase();
      return name.contains(query) || pkg.contains(query);
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Installed Apps', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  tooltip: 'Reload apps',
                  onPressed: _reloadInstalledApps,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Choose auto_reply, alert_only, or off per app. Tap the rule icon to set a per-app custom rule.',
              style: TextStyle(color: ApexAgentApp.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _appSearchController,
              decoration: const InputDecoration(
                hintText: 'Search installed apps...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            if (_installedApps.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'No installed apps found or permission unavailable.',
                  style: TextStyle(color: ApexAgentApp.muted),
                ),
              )
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 420),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final app = filtered[index];
                    final pkg = app['packageName'] ?? '';
                    final name = app['appName'] ?? pkg;
                    final mode = _appModes[pkg] ?? 'off';
                    final hasRule = (_appRules[pkg] ?? '').trim().isNotEmpty;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(
                                  pkg,
                                  style: const TextStyle(color: ApexAgentApp.muted, fontSize: 11),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Per-app custom rule',
                            onPressed: () => _showEditRuleDialog(
                              title: 'Rule for $name',
                              keyLabel: 'Package',
                              initialKey: pkg,
                              initialRule: _appRules[pkg] ?? '',
                              keyReadOnly: true,
                              onSave: (k, r) => _saveAppRule(k, r),
                            ),
                            icon: Icon(
                              Icons.rule,
                              color: hasRule ? ApexAgentApp.accent : ApexAgentApp.muted,
                            ),
                          ),
                          const SizedBox(width: 4),
                          DropdownButton<String>(
                            value: mode,
                            dropdownColor: ApexAgentApp.surfaceAlt,
                            underline: const SizedBox.shrink(),
                            items: const [
                              DropdownMenuItem(value: 'auto_reply', child: Text('Auto-reply')),
                              DropdownMenuItem(value: 'alert_only', child: Text('Alert only')),
                              DropdownMenuItem(value: 'off', child: Text('Off')),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              _setAppMode(pkg, v);
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRuleTile({
    required String title,
    required String rule,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ApexAgentApp.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF263241)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(rule, style: const TextStyle(color: ApexAgentApp.muted, fontSize: 13)),
              ],
            ),
          ),
          IconButton(onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 18)),
          IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline, size: 18)),
        ],
      ),
    );
  }

  Future<void> _showEditRuleDialog({
    required String title,
    required String keyLabel,
    required String initialKey,
    required String initialRule,
    required bool keyReadOnly,
    required Future<void> Function(String key, String rule) onSave,
  }) async {
    final keyController = TextEditingController(text: initialKey);
    final ruleController = TextEditingController(text: initialRule);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: ApexAgentApp.surface,
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: keyController,
                  readOnly: keyReadOnly,
                  decoration: InputDecoration(labelText: keyLabel),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ruleController,
                  minLines: 2,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Custom rule',
                    hintText: 'Describe how the agent should reply...',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        );
      },
    );
    if (saved == true) {
      final key = keyController.text.trim();
      final rule = ruleController.text;
      if (key.isNotEmpty) {
        await onSave(key, rule);
        if (mounted) setState(() {});
      }
    }
  }

  Widget _buildHistoryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Live History Log', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  tooltip: 'Refresh history',
                  onPressed: _refreshHistory,
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  tooltip: 'Clear history',
                  onPressed: _history.isEmpty ? null : _clearHistory,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Recent auto-reply decisions and actions.',
              style: TextStyle(color: ApexAgentApp.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            if (_history.isEmpty)
              const Text('No history yet.', style: TextStyle(color: ApexAgentApp.muted))
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _history.length > 100 ? 100 : _history.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = _history[index];
                    return _buildHistoryEntry(entry);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryEntry(Map<String, dynamic> entry) {
    final type = entry['type']?.toString() ?? 'event';
    final appName = entry['appName']?.toString() ?? entry['packageName']?.toString() ?? '';
    final sender = entry['senderName']?.toString() ?? '';
    final message = entry['message']?.toString() ?? '';
    final reply = entry['reply']?.toString() ?? '';
    final error = entry['error']?.toString() ?? '';
    final ts = int.tryParse(entry['timestamp']?.toString() ?? '');
    final timeStr = ts != null ? _timeFmt.format(DateTime.fromMillisecondsSinceEpoch(ts)) : '';

    final color = _historyColor(type);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
                        type.replaceAll('_', ' ').toUpperCase(),
                        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ),
                    Text(timeStr, style: const TextStyle(color: ApexAgentApp.muted, fontSize: 11)),
                  ],
                ),
                if (appName.isNotEmpty || sender.isNotEmpty)
                  Text(
                    [appName, sender].where((s) => s.isNotEmpty).join(' • '),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                if (message.isNotEmpty)
                  Text(
                    'In: $message',
                    style: const TextStyle(color: ApexAgentApp.muted, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (reply.isNotEmpty)
                  Text(
                    'Reply: $reply',
                    style: const TextStyle(color: ApexAgentApp.text, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (error.isNotEmpty)
                  Text(
                    'Error: $error',
                    style: const TextStyle(color: ApexAgentApp.danger, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _historyColor(String type) {
    switch (type) {
      case 'sent':
      case 'approved_sent':
        return ApexAgentApp.accent;
      case 'pending_approval':
        return ApexAgentApp.warn;
      case 'skipped':
      case 'alert_only':
      case 'cooldown':
      case 'anti_loop':
      case 'blocked_contact':
      case 'dismissed':
        return const Color(0xFF7CC4FF);
      case 'worker_error':
      case 'send_failed':
      case 'parse_error':
      case 'config_missing':
        return ApexAgentApp.danger;
      default:
        return ApexAgentApp.muted;
    }
  }
}
