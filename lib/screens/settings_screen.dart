import 'package:flutter/material.dart';

import '../main.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _workerUrlController = TextEditingController();
  final _authTokenController = TextEditingController();
  final _modelIdController = TextEditingController();
  final _customLlmController = TextEditingController();
  final _businessPhoneController = TextEditingController();
  final _countryCodeController = TextEditingController();
  final _memoryContextController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _obscureToken = true;
  bool _voiceInputEnabled = false;
  bool _speakRepliesEnabled = false;
  bool _memoryEnabled = true;
  double _ttsRate = 0.5;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _workerUrlController.dispose();
    _authTokenController.dispose();
    _modelIdController.dispose();
    _customLlmController.dispose();
    _businessPhoneController.dispose();
    _countryCodeController.dispose();
    _memoryContextController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final workerUrl = await SettingsService.getWorkerUrl();
    final token = await SettingsService.getAuthToken();
    final modelId = await SettingsService.getModelId();
    final customLlm = await SettingsService.getCustomLlmEndpoint();
    final businessPhone = await SettingsService.getBusinessPhoneNumber();
    final countryCode = await SettingsService.getDefaultCountryCode();
    final voiceInput = await SettingsService.getVoiceInputEnabled();
    final speakReplies = await SettingsService.getSpeakRepliesEnabled();
    final ttsRate = await SettingsService.getTtsRate();
    final memoryEnabled = await SettingsService.getMemoryEnabled();
    final memoryContext = await SettingsService.getMemoryContext();
    if (!mounted) return;
    setState(() {
      _workerUrlController.text = workerUrl;
      _authTokenController.text = token;
      _modelIdController.text = modelId;
      _customLlmController.text = customLlm;
      _businessPhoneController.text = businessPhone;
      _countryCodeController.text = countryCode;
      _voiceInputEnabled = voiceInput;
      _speakRepliesEnabled = speakReplies;
      _ttsRate = ttsRate;
      _memoryEnabled = memoryEnabled;
      _memoryContextController.text = memoryContext;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await SettingsService.setWorkerUrl(_workerUrlController.text);
      await SettingsService.setAuthToken(_authTokenController.text);
      await SettingsService.setModelId(_modelIdController.text);
      await SettingsService.setCustomLlmEndpoint(_customLlmController.text);
      await SettingsService.setBusinessPhoneNumber(_businessPhoneController.text);
      await SettingsService.setDefaultCountryCode(_countryCodeController.text);
      await SettingsService.setVoiceInputEnabled(_voiceInputEnabled);
      await SettingsService.setSpeakRepliesEnabled(_speakRepliesEnabled);
      await SettingsService.setTtsRate(_ttsRate);
      await SettingsService.setMemoryEnabled(_memoryEnabled);
      await SettingsService.setMemoryContext(_memoryContextController.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved'),
          backgroundColor: Color(0xFF1B5E20),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clearMemory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ApexAgentApp.surface,
        title: const Text('Clear persistent memory?'),
        content: const Text('This will remove saved notes, bookings, contacts, and memory context from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed != true) return;
    await SettingsService.clearMemory();
    if (!mounted) return;
    setState(() => _memoryContextController.clear());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Persistent memory cleared')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            tooltip: 'Reload',
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
                _buildHeaderCard(),
                const SizedBox(height: 16),
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _buildSectionCard(
                        title: 'Cloudflare Worker / LLM',
                        subtitle:
                            'Configure the backend endpoint used for agent tool-calling and auto-reply. Optionally override with a custom/local LLM endpoint.',
                        children: [
                          TextFormField(
                            controller: _workerUrlController,
                            decoration: const InputDecoration(
                              labelText: 'Worker URL',
                              hintText: 'https://your-worker.your-subdomain.workers.dev',
                              prefixIcon: Icon(Icons.cloud_outlined),
                            ),
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                            validator: (v) {
                              final value = (v ?? '').trim();
                              final custom = _customLlmController.text.trim();
                              if (value.isEmpty && custom.isEmpty) {
                                return 'Worker URL or custom LLM endpoint is required';
                              }
                              if (value.isNotEmpty) {
                                final uri = Uri.tryParse(value);
                                if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
                                  return 'Enter a valid http/https URL';
                                }
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _customLlmController,
                            decoration: const InputDecoration(
                              labelText: 'Custom / Local LLM Endpoint Override (optional)',
                              hintText: 'https://your-local-or-custom-endpoint',
                              prefixIcon: Icon(Icons.dns_outlined),
                            ),
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                            validator: (v) {
                              final value = (v ?? '').trim();
                              if (value.isEmpty) return null;
                              final uri = Uri.tryParse(value);
                              if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
                                return 'Enter a valid http/https URL';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _authTokenController,
                            decoration: InputDecoration(
                              labelText: 'Bearer Secret Token',
                              hintText: 'Your AUTH_TOKEN value',
                              prefixIcon: const Icon(Icons.vpn_key_outlined),
                              suffixIcon: IconButton(
                                onPressed: () => setState(() => _obscureToken = !_obscureToken),
                                icon: Icon(_obscureToken ? Icons.visibility : Icons.visibility_off),
                              ),
                            ),
                            obscureText: _obscureToken,
                            autocorrect: false,
                            validator: (v) {
                              if ((v ?? '').trim().isEmpty) return 'Bearer secret token is required';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _modelIdController,
                            decoration: const InputDecoration(
                              labelText: 'Model ID',
                              hintText: SettingsService.defaultModelId,
                              prefixIcon: Icon(Icons.memory_outlined),
                            ),
                            autocorrect: false,
                            validator: (v) {
                              if ((v ?? '').trim().isEmpty) return 'Model ID is required';
                              return null;
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildSectionCard(
                        title: 'Agent / Business Identity',
                        subtitle:
                            'Used for receptionist/booking flows, SMS/WhatsApp reminders, and follow-ups.',
                        children: [
                          TextFormField(
                            controller: _businessPhoneController,
                            decoration: const InputDecoration(
                              labelText: 'Agent/Business Phone Number',
                              hintText: '+2348012345678',
                              prefixIcon: Icon(Icons.phone_outlined),
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _countryCodeController,
                            decoration: const InputDecoration(
                              labelText: 'Default Country Code',
                              hintText: '+234',
                              prefixIcon: Icon(Icons.flag_outlined),
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildSectionCard(
                        title: 'Voice & TTS Preferences',
                        subtitle: 'Control voice input and spoken agent replies.',
                        children: [
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            value: _voiceInputEnabled,
                            activeColor: ApexAgentApp.accent,
                            title: const Text('Enable Voice Input'),
                            subtitle: const Text('Show microphone input in Agent Chat'),
                            onChanged: (v) => setState(() => _voiceInputEnabled = v),
                          ),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            value: _speakRepliesEnabled,
                            activeColor: ApexAgentApp.accent,
                            title: const Text('Speak Replies (TTS)'),
                            subtitle: const Text('Read agent completion responses aloud'),
                            onChanged: (v) => setState(() => _speakRepliesEnabled = v),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Expanded(child: Text('TTS Speech Rate', style: TextStyle(fontWeight: FontWeight.w600))),
                              Text(_ttsRate.toStringAsFixed(2),
                                  style: const TextStyle(color: ApexAgentApp.accent, fontWeight: FontWeight.w700)),
                            ],
                          ),
                          Slider(
                            value: _ttsRate,
                            min: 0.2,
                            max: 1.0,
                            divisions: 8,
                            label: _ttsRate.toStringAsFixed(2),
                            activeColor: ApexAgentApp.accent,
                            onChanged: (v) => setState(() => _ttsRate = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildSectionCard(
                        title: 'Persistent Memory',
                        subtitle:
                            'Store and reuse context, contacts, bookings, and follow-ups across agent turns.',
                        children: [
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            value: _memoryEnabled,
                            activeColor: ApexAgentApp.accent,
                            title: const Text('Enable Persistent Memory'),
                            subtitle: const Text('Allow agent to use and update local memory/context'),
                            onChanged: (v) => setState(() => _memoryEnabled = v),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _memoryContextController,
                            minLines: 3,
                            maxLines: 6,
                            decoration: const InputDecoration(
                              labelText: 'Memory Context / Business Notes',
                              hintText: 'Business hours, services, booking rules, follow-up policies...',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _clearMemory,
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('Clear Memory'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(_saving ? 'Saving...' : 'Save Settings'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _buildInfoCard(),
              ],
            ),
    );
  }

  Widget _buildHeaderCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: ApexAgentApp.accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.shield_outlined, color: ApexAgentApp.accent),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Apex Agent Configuration',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Settings are stored locally on this device using shared preferences.',
                    style: TextStyle(color: ApexAgentApp.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: ApexAgentApp.muted, fontSize: 13)),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Notes', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            _InfoRow(
              icon: Icons.lock_outline,
              text: 'The Bearer Secret Token must match AUTH_TOKEN configured in your Cloudflare Worker.',
            ),
            SizedBox(height: 8),
            _InfoRow(
              icon: Icons.smart_toy_outlined,
              text: 'Default model is @hf/nousresearch/hermes-2-pro-mistral-7b. Use a custom/local endpoint override only if it accepts the same agent payload.',
            ),
            SizedBox(height: 8),
            _InfoRow(
              icon: Icons.phonelink_setup_outlined,
              text: 'Grant Accessibility, Notification Listener, Background, and Phone/SMS permissions for full functionality.',
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: ApexAgentApp.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: const TextStyle(color: ApexAgentApp.muted, fontSize: 13)),
        ),
      ],
    );
  }
}
