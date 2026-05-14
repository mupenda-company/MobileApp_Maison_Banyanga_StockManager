import 'package:flutter/material.dart';
import 'package:logis_agent/api/api_client.dart';
import 'package:logis_agent/config/app_config.dart';
import 'package:logis_agent/pages/create_sale_page.dart';
import 'package:logis_agent/pages/sale_invoice_page.dart';
import 'package:logis_agent/services/app_refresh_service.dart';
import 'package:logis_agent/services/api_service.dart';
import 'package:logis_agent/services/auth_service.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  bool _loading = false;
  String? _error;
  List<dynamic> _sales = const [];
  bool _todayOnly = false;

  late final VoidCallback _refreshListener;

  String get _currentDayLabel {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String _formatSaleTime(String? value) {
    if (value == null || value.trim().isEmpty) return '';

    final parsed = DateTime.tryParse(value.replaceFirst(' ', 'T'));
    if (parsed == null) return value;

    return '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _load() async {
    if (AppConfig.apiBaseUrl.isEmpty) {
      setState(() {
        _error = 'API_BASE_URL non configuré';
        _sales = const [];
      });
      return;
    }

    final session = AuthService.instance.session;
    final missionId = session?.mission?['id']?.toString();
    if (missionId == null || missionId.isEmpty) {
      setState(() {
        _error = 'Aucune mission en cours';
        _sales = const [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = ApiService.instance.createClient();
      final query = <String>['mission_id=$missionId'];

      if (_todayOnly) {
        query.add('date=${Uri.encodeComponent(_currentDayLabel)}');
      }

      final data = await client.getJson('${AppConfig.salesPath}?${query.join('&')}');

      final list = data is List
          ? data
          : (data is Map<String, dynamic> && data['data'] is List ? data['data'] as List : null);

      setState(() {
        _sales = list ?? const [];
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _sales = const [];
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _sales = const [];
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _openInvoice(dynamic item) async {
    if (item is! Map<String, dynamic>) return;

    final saleId = int.tryParse(item['id']?.toString() ?? '');
    if (saleId == null || saleId <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vente invalide')),
        );
      }
      return;
    }

    try {
      final client = ApiService.instance.createClient();
      final resp = await client.getJson('${AppConfig.ventePath}/$saleId/facture');
      final payload = resp is Map<String, dynamic>
          ? (resp['data'] is Map<String, dynamic> ? resp['data'] as Map<String, dynamic> : resp)
          : null;

      final vente = payload?['vente'];
      final params = payload?['params'];
      final lines = <SaleInvoiceLine>[];

      if (vente is Map<String, dynamic>) {
        final details = vente['details'];
        if (details is List) {
          for (final d in details) {
            if (d is! Map<String, dynamic>) continue;
            final btlParCs = double.tryParse(d['bouteilles_par_caisses']?.toString() ?? '') ?? 24;
            final denom = btlParCs <= 0 ? 24 : btlParCs;
            final quantite = double.tryParse(d['quantite']?.toString() ?? '') ?? 0;
            if (quantite <= 0) continue;
            final caisses = double.tryParse(d['quantite_caisses']?.toString() ?? '') ?? (quantite / denom);
            final caissesVidesRecues = double.tryParse(d['caisses_vides_recues']?.toString() ?? '') ?? 0;
            final prixCaisse = double.tryParse(d['prix_caisse']?.toString() ?? '') ??
                ((double.tryParse(d['prix_unitaire']?.toString() ?? '') ?? 0) * denom);
            final sousTotal = double.tryParse(d['sous_total']?.toString() ?? '') ?? 0;

            lines.add(
              SaleInvoiceLine(
                produitNom: d['produit_nom']?.toString() ?? 'Produit',
                caisses: caisses,
                caissesVidesRecues: caissesVidesRecues,
                detteCaisses: (caisses - caissesVidesRecues).clamp(0, caisses),
                prixCaisse: prixCaisse,
                sousTotal: sousTotal,
              ),
            );
          }
        }
      }

      if (vente is! Map<String, dynamic>) {
        throw Exception('Impossible de charger la facture');
      }

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SaleInvoicePage(
            venteId: saleId,
            numeroFacture: vente['numero_facture']?.toString(),
            date: DateTime.tryParse((vente['date_vente']?.toString() ?? '').replaceFirst(' ', 'T')) ?? DateTime.now(),
            clientNom: vente['client_nom']?.toString() ?? 'Client',
            clientTelephone: vente['client_telephone']?.toString(),
            clientNumero: vente['client_numero']?.toString(),
            zoneNom: vente['zone_nom']?.toString(),
            devise: (params is Map<String, dynamic> && params['devise'] != null)
                ? params['devise'].toString()
                : 'CDF',
            companyName: params is Map<String, dynamic> ? params['nom_entreprise']?.toString() : null,
            companyAddress: params is Map<String, dynamic> ? params['adresse']?.toString() : null,
            companyTelephone: params is Map<String, dynamic> ? params['telephone']?.toString() : null,
            companyLogo: params is Map<String, dynamic> ? params['logo_url']?.toString() ?? params['logo']?.toString() : null,
            companyEmail: params is Map<String, dynamic> ? params['email_contact']?.toString() : null,
            companyContact: params is Map<String, dynamic> ? params['contact']?.toString() : null,
            companyRccm: params is Map<String, dynamic> ? params['rccm']?.toString() : null,
            companyIdNat: params is Map<String, dynamic> ? params['id_nat']?.toString() : null,
            companyNif: params is Map<String, dynamic> ? params['nif']?.toString() : null,
            companyAccount: params is Map<String, dynamic> ? params['numero_compte']?.toString() : null,
            produitsCumules: double.tryParse(payload?['totalCaissesClient']?.toString() ?? ''),
            caPeriode: null,
            ristourneTaux: double.tryParse((payload?['ristourneInfo'] is Map<String, dynamic>) ? (payload?['ristourneInfo'] as Map<String, dynamic>)['taux_applique']?.toString() ?? '' : ''),
            ristourneMontant: double.tryParse((payload?['ristourneInfo'] is Map<String, dynamic>) ? (payload?['ristourneInfo'] as Map<String, dynamic>)['montant_ristourne']?.toString() ?? '' : ''),
            ristourneInfoPresent: payload?['ristourneInfo'] is Map<String, dynamic>,
            vendeurNom: vente['created_by_prenom'] == null && vente['created_by_nom'] == null
                ? null
                : '${vente['created_by_prenom'] ?? ''} ${vente['created_by_nom'] ?? ''}'.trim(),
            totalHt: double.tryParse(vente['total_ht']?.toString() ?? '') ?? 0,
            totalTva: double.tryParse(vente['total_tva']?.toString() ?? '') ?? 0,
            totalTtc: double.tryParse(vente['total_ttc']?.toString() ?? '') ?? 0,
            lignes: lines,
            autoPrint: true,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impression impossible: $e')),
      );
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

  Widget _summaryTile({
    required String label,
    required String value,
    required IconData icon,
    required ColorScheme scheme,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: scheme.onPrimaryContainer, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final salesCount = _sales.length;
    final totalCaisses = _sales.fold<double>(0, (sum, item) {
      if (item is Map<String, dynamic>) {
        final raw = item['caisses_vendues'];
        return sum + (raw is num ? raw.toDouble() : double.tryParse(raw?.toString() ?? '') ?? 0);
      }
      return sum;
    });

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
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
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(Icons.point_of_sale_rounded, color: scheme.onPrimary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ventes de la mission',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Vue claire des factures enregistrées sur le terrain.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _summaryTile(
                        label: 'Ventes',
                        value: salesCount.toString(),
                        icon: Icons.receipt_long,
                        scheme: scheme,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _summaryTile(
                        label: 'Caisses vendues',
                        value: totalCaisses.toStringAsFixed(1),
                        icon: Icons.inventory_2,
                        scheme: scheme,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: true,
                      label: Text('Aujourd’hui'),
                      icon: Icon(Icons.today),
                    ),
                    ButtonSegment<bool>(
                      value: false,
                      label: Text('Tout'),
                      icon: Icon(Icons.history),
                    ),
                  ],
                  selected: {_todayOnly},
                  onSelectionChanged: _loading
                      ? null
                      : (selection) async {
                          setState(() {
                            _todayOnly = selection.first;
                          });
                          await _load();
                        },
                ),
                const SizedBox(height: 12),
                SizedBox(
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
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: scheme.error),
              ),
            ),
          if (_error == null && _sales.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Aucune vente à afficher.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 8),
          for (final item in _sales)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: item is Map<String, dynamic>
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    color: scheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(Icons.receipt_long, color: scheme.onPrimaryContainer),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (item['numero_facture'] ?? item['reference'] ?? item['id'] ?? 'Vente').toString(),
                                        style: const TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '${(item['client_nom'] ?? item['client'] ?? 'Client').toString()} · ${(item['total_ttc'] ?? item['total'] ?? '').toString()}',
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Caisses vendues: ${(item['caisses_vendues'] ?? 0).toString()} · ${_formatSaleTime(item['date_vente']?.toString())}',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: scheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Text(
                                    (item['date_vente'] ?? '').toString().split(' ').first,
                                    style: TextStyle(
                                      color: scheme.onSecondaryContainer,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                IconButton.filledTonal(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _openInvoice(item),
                                  icon: const Icon(Icons.print_rounded),
                                  tooltip: 'Imprimer la facture',
                                ),
                              ],
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
