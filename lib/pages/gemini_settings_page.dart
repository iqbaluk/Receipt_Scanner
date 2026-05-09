part of '../main.dart';

class GeminiSettingsPage extends StatefulWidget {
  const GeminiSettingsPage({super.key});

  @override
  State<GeminiSettingsPage> createState() => _GeminiSettingsPageState();
}

class _GeminiSettingsPageState extends State<GeminiSettingsPage> {
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  bool _obscureKey = true;
  bool _usingEnvFallback = false;

  @override
  void initState() {
    super.initState();
    _modelController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadSettings();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _loading = true);
    final settings = await GeminiService.loadSettings();
    final savedKey = await GeminiService.savedApiKey();
    if (!mounted) return;
    setState(() {
      _apiKeyController.text = savedKey ?? '';
      _modelController.text = settings.model;
      _usingEnvFallback = settings.usesEnvKey && !settings.hasSavedApiKey;
      _loading = false;
    });
  }

  Future<void> _saveSettings() async {
    setState(() => _saving = true);
    try {
      await GeminiService.saveSettings(
        apiKey: _apiKeyController.text,
        model: _modelController.text,
      );
      if (!mounted) return;
      await _loadSettings();
      if (!mounted) return;
      _showMessage(
        _apiKeyController.text.trim().isEmpty
            ? 'Gemini settings saved. Using .env API key if available.'
            : 'Gemini settings saved.',
      );
    } catch (e) {
      if (!mounted) return;
      _showMessage(e.toString().replaceFirst('Invalid argument(s): ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testSettings() async {
    setState(() => _testing = true);
    final result = await GeminiService.checkSettings(
      apiKey: _apiKeyController.text,
      model: _modelController.text,
    );
    if (!mounted) return;
    setState(() => _testing = false);
    if (!result.success) {
      _showMessage(result.errorMessage ?? 'Gemini check failed.');
      return;
    }

    final workingModel = result.workingModel;
    if (workingModel == null) {
      _showMessage('Gemini connection works.');
      return;
    }

    if (result.usedFallback) {
      setState(() => _modelController.text = workingModel);
      _showMessage(
          'Selected model failed. $workingModel works and is ready to save.');
    } else {
      _showMessage('Gemini connection works with $workingModel.');
    }
  }

  Future<void> _resetToEnv() async {
    setState(() => _saving = true);
    try {
      await GeminiService.resetSettings();
      if (!mounted) return;
      await _loadSettings();
      if (!mounted) return;
      _showMessage('Gemini settings reset to .env fallback.');
    } catch (e) {
      if (!mounted) return;
      _showMessage('Could not reset Gemini settings: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _useModel(String model) {
    _modelController.text = model;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gemini settings'),
        backgroundColor: colorScheme.primaryContainer,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Provider: Gemini',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _apiKeyController,
                            obscureText: _obscureKey,
                            keyboardType: TextInputType.visiblePassword,
                            decoration: InputDecoration(
                              labelText: 'Client Gemini API key',
                              helperText: _usingEnvFallback
                                  ? 'No client key saved. The app is using the .env key.'
                                  : 'Leave empty to use the .env key on this device.',
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                tooltip: _obscureKey ? 'Show key' : 'Hide key',
                                onPressed: () {
                                  setState(() => _obscureKey = !_obscureKey);
                                },
                                icon: Icon(
                                  _obscureKey
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _modelController,
                            decoration: const InputDecoration(
                              labelText: 'Gemini model',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('gemini-2.5-flash'),
                                selected: _modelController.text.trim() ==
                                    'gemini-2.5-flash',
                                onSelected: (_) =>
                                    _useModel('gemini-2.5-flash'),
                              ),
                              ChoiceChip(
                                label: const Text('gemini-1.5-flash'),
                                selected: _modelController.text.trim() ==
                                    'gemini-1.5-flash',
                                onSelected: (_) =>
                                    _useModel('gemini-1.5-flash'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _saving ? null : _saveSettings,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: const Text('Save settings'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _testing ? null : _testSettings,
                    icon: _testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check),
                    label: const Text('Check Gemini settings'),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: _saving ? null : _resetToEnv,
                    icon: const Icon(Icons.restore),
                    label: const Text('Reset to .env'),
                  ),
                ],
              ),
      ),
    );
  }
}
