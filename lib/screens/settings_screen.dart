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

  bool _loading = true;
  bool _saving = false;
  bool _obscureToken = true;

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
    super.dispose();
  }

  Future<void> _load() async {
    final workerUrl = await SettingsService.getWorkerUrl();
    final token = await SettingsService.getAuthToken();
    final modelId = await SettingsService.getModelId();
    if (!mounted) return;
    setState(() {
      _workerUrlController.text = workerUrl;
      _authTokenController.text = token;
      _modelIdController.text = modelId;
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
                        title: 'Cloudflare Worker',
                        subtitle:
                            'Configure the backend endpoint used for agent tool-calling and auto-reply.',
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
                              if (value.isEmpty) return 'Worker URL is required';
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
              text: 'The default model is @hf/nousresearch/hermes-2-pro-mistral-7b. Change it only if your Worker supports it.',
            ),
            SizedBox(height: 8),
            _InfoRow(
              icon: Icons.phonelink_setup_outlined,
              text: 'Grant Accessibility, Notification Listener, and Background permissions for full functionality.',
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
