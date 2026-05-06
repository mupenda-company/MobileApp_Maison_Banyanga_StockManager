import 'package:flutter/material.dart';
import 'package:logis_agent/api/api_client.dart';
import 'package:logis_agent/config/app_config.dart';
import 'package:logis_agent/pages/home.dart';
import 'package:logis_agent/services/api_service.dart';
import 'package:logis_agent/services/auth_service.dart';
import 'package:logis_agent/theme/app_theme_controller.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final _formKey = GlobalKey<FormState>();
  final username = TextEditingController();
  final password = TextEditingController();

  bool _isLoading = false;
  String? _error;
  bool _brandingLoading = false;
  String? _brandingLogo;

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadBranding();
  }

  Future<void> _loadBranding() async {
    if (AppConfig.apiBaseUrl.isEmpty) return;

    setState(() {
      _brandingLoading = true;
    });

    try {
      final client = ApiService.instance.createClient();
      final resp = await client.getJson('/api/mobile/branding');

      Map<String, dynamic>? payload;
      if (resp is Map<String, dynamic>) {
        final data = resp['data'];
        payload = data is Map<String, dynamic> ? data : resp;
      }

      if (payload != null) {
        AppThemeController.instance.updateFromSettings(payload);
        final logo = payload['logo_url']?.toString() ?? payload['logo']?.toString();
        if (logo != null && logo.trim().isNotEmpty) {
          _brandingLogo = logo.trim();
        }
      }
    } on ApiException {
      // Ignore branding errors
    } catch (_) {
      // Ignore branding errors
    } finally {
      if (mounted) {
        setState(() {
          _brandingLoading = false;
        });
      }
    }
  }

  String? _resolveLogoUrl(String logo) {
    final l = logo.trim();
    if (l.isEmpty) return null;
    if (l.startsWith('http://') || l.startsWith('https://')) return l;

    final base = AppConfig.apiBaseUrl;
    if (base.isEmpty) return null;

    final normalizedBase = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    var relative = l.startsWith('/') ? l.substring(1) : l;

    if (relative.startsWith('public/uploads/')) {
      relative = relative.substring('public/'.length);
    } else if (relative.startsWith('public/')) {
      relative = relative.substring('public/'.length);
    } else if (!relative.startsWith('uploads/')) {
      relative = 'uploads/$relative';
    }

    return '$normalizedBase/$relative';
  }

  Future<void> login() async {
    final u = username.text.trim();
    final p = password.text;

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await AuthService.instance.login(username: u, password: p);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const Home()),
      );
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final companyName = AppThemeController.instance.companyName;
    final logoUrl = _brandingLogo == null ? null : _resolveLogoUrl(_brandingLogo!);

    return SafeArea(
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                scheme.primary.withAlpha(25),
                scheme.surface,
              ],
            ),
          ),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  children: [
                    if (_brandingLoading)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    if (logoUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(
                          logoUrl,
                          width: 92,
                          height: 92,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Icon(Icons.storefront, size: 72, color: scheme.primary),
                        ),
                      )
                    else
                      Icon(Icons.storefront, size: 72, color: scheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      companyName,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Connecte-toi pour continuer",
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              if (AppConfig.apiBaseUrl.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(
                                    'API_BASE_URL non configuré',
                                    style: TextStyle(color: scheme.error),
                                  ),
                                ),
                              TextFormField(
                                controller: username,
                                enabled: !_isLoading,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Utilisateur',
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                                validator: (value) {
                                  final v = value?.trim() ?? '';
                                  if (v.isEmpty) return 'Veuillez entrer votre utilisateur';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: password,
                                enabled: !_isLoading,
                                obscureText: true,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) {
                                  if (!_isLoading) login();
                                },
                                decoration: const InputDecoration(
                                  labelText: 'Mot de passe',
                                  prefixIcon: Icon(Icons.lock_outline),
                                ),
                                validator: (value) {
                                  final v = value ?? '';
                                  if (v.isEmpty) return 'Veuillez entrer votre mot de passe';
                                  return null;
                                },
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    _error!,
                                    style: TextStyle(color: scheme.error),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 18),
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: FilledButton(
                                  onPressed: _isLoading ? null : login,
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Text('Se connecter'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
