import 'package:flutter/material.dart';
import 'package:logis_agent/api/api_client.dart';
import 'package:logis_agent/config/app_config.dart';
import 'package:logis_agent/pages/create_sale_page.dart';
import 'package:logis_agent/services/app_refresh_service.dart';
import 'package:logis_agent/services/api_service.dart';
import 'package:logis_agent/services/auth_service.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _data;

  late final VoidCallback _refreshListener;

  Future<void> _load() async {
    if (AppConfig.apiBaseUrl.isEmpty) {
      setState(() {
        _error = 'API_BASE_URL non configuré';
        _data = null;
      });
      return;
    }

    final session = AuthService.instance.session;
    final missionId = session?.mission?['id']?.toString();
    if (missionId == null || missionId.isEmpty) {
      setState(() {
        _error = 'Aucune mission en cours';
        _data = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = ApiService.instance.createClient();
      final resp = await client.getJson('${AppConfig.missionPath}/$missionId/stats');

      Map<String, dynamic>? payload;
      if (resp is Map<String, dynamic>) {
        final data = resp['data'];
        if (data is Map<String, dynamic>) {
          payload = data;
        } else {
          payload = resp;
        }
      }

      setState(() {
        _data = payload;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _data = null;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _data = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _refreshListener = () {
      if (mounted) {
        _load();
      }
    };
    AppRefreshService.instance.addListener(_refreshListener);
    _load();
  }

  @override
  void dispose() {
    AppRefreshService.instance.removeListener(_refreshListener);
    super.dispose();
  }

  Widget _metricCard({
    required String title,
    required String value,
    required IconData icon,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _clientInfoTile({
    required String label,
    required String value,
    required IconData icon,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: 170,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface.withOpacity(0.8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.primary.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 16, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mission = _data?['mission'] is Map<String, dynamic> ? _data!['mission'] as Map<String, dynamic> : null;
    final chargement = _data?['chargement'] is Map<String, dynamic> ? _data!['chargement'] as Map<String, dynamic> : null;
    final clients = _data?['clients'] is Map<String, dynamic> ? _data!['clients'] as Map<String, dynamic> : null;
    final stock = _data?['stock'] is Map<String, dynamic> ? _data!['stock'] as Map<String, dynamic> : null;

    final scheme = Theme.of(context).colorScheme;

    final caissesChargees = (chargement?['caisses_chargees'] ?? 0).toString();
    final caissesRestantes = (chargement?['caisses_restantes'] ?? 0).toString();
    final stockCoherent = chargement?['stock_coherent'] == true;
    final clientsCount = (clients?['clients_count'] ?? 0).toString();
    final dernierClientNom = (clients?['dernier_client_nom'] ?? 'Aucun client').toString();
    final dernierClientTelephone = (clients?['dernier_client_telephone'] ?? '').toString();
    final dernierClientAdresse = (clients?['dernier_client_adresse'] ?? '').toString();
    final caissesVides = (stock?['caisses_vide'] ?? 0).toString();
    final caissesPleine = (stock?['caisses_pleine'] ?? 0).toString();
    final caissesTotales = (stock?['caisses_totales'] ?? 0).toString();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 12),
              child: Text(
                _error!,
                style: TextStyle(color: scheme.error),
              ),
            ),
          if (_error == null && mission != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [scheme.primaryContainer.withOpacity(0.95), scheme.surface],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: scheme.primary.withOpacity(0.08)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Icon(Icons.local_shipping_rounded, color: scheme.onPrimary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (mission['vehicule_immatriculation'] ?? 'Véhicule').toString(),
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Mission ${(mission['numero_mission'] ?? '').toString()}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Zone: ${(mission['zone_nom'] ?? 'N/A').toString()}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            'En cours',
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _metricCard(
                            title: 'Caisses chargées',
                            value: caissesChargees,
                            icon: Icons.local_shipping,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _metricCard(
                            title: 'Caisses restantes',
                            value: caissesRestantes,
                            icon: Icons.inventory_2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          stockCoherent ? Icons.check_circle_outline : Icons.info_outline,
                          size: 16,
                          color: stockCoherent ? scheme.primary : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            stockCoherent
                                ? 'Les caisses restantes correspondent aux caisses pleines: les vides ont bien été retournées.'
                                : 'Les caisses restantes et pleines diffèrent. Vérifie le retour des vides ou l’inventaire mission.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (_error == null && clients != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      scheme.primaryContainer.withOpacity(0.8),
                      scheme.surface,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: scheme.primary.withOpacity(0.08)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Icon(Icons.people_alt_rounded, color: scheme.onPrimary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Résumé des clients',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Aperçu rapide des clients servis pendant cette mission.',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  clientsCount,
                                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: scheme.primary,
                                      ),
                                ),
                                Text(
                                  'servis',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _clientInfoTile(
                        label: 'Dernier client',
                        value: dernierClientNom,
                        icon: Icons.person_outline,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _clientInfoTile(
                            label: 'Téléphone',
                            value: dernierClientTelephone.isNotEmpty ? dernierClientTelephone : 'Non renseigné',
                            icon: Icons.call_outlined,
                          ),
                          _clientInfoTile(
                            label: 'Adresse',
                            value: dernierClientAdresse.isNotEmpty ? dernierClientAdresse : 'Non renseignée',
                            icon: Icons.location_on_outlined,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_error == null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const CreateSalePage()),
                    );
                    if (result == true) {
                      await _load();
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Nouvelle vente'),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _metricCard(title: 'Caisses pleines', value: caissesPleine, icon: Icons.inventory),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _metricCard(title: 'Caisses vides', value: caissesVides, icon: Icons.all_inbox),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total physique',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  Text(
                    caissesTotales,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
