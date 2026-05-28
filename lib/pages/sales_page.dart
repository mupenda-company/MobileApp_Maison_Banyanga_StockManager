import 'dart:math';

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
  List<dynamic> _ristournes = const [];
  bool _todayOnly = false;
  String _missionType = 'vente';

  late final VoidCallback _refreshListener;

  String get _currentDayLabel {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, "0")}-${now.month.toString().padLeft(2, "0")}-${now.day.toString().padLeft(2, "0")}';
  }

  String _formatSaleTime(String? value) {
    if (value == null || value.trim().isEmpty) return '';

    final parsed = DateTime.tryParse(value.replaceFirst(' ', 'T'));
    if (parsed == null) return value;

    return '${parsed.hour.toString().padLeft(2, "0")}:${parsed.minute.toString().padLeft(2, "0")}';
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
    _missionType = session?.mission?['type_mission']?.toString() ?? 'vente';
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

      // Charger les ristournes en premier (pour missions ristourne)
      if (_missionType == 'ristourne') {
        try {
          debugPrint('SalesPage: loading ristournes for mission $missionId');
          final stats = await client.getJson(
            '${AppConfig.missionPath}/$missionId/stats',
          );
          debugPrint('SalesPage: stats response type=${stats.runtimeType}');
          if (stats is Map<String, dynamic>) {
            final r = stats['data'] is Map<String, dynamic>
                ? stats['data'] as Map<String, dynamic>
                : stats;
            final rist = r['ristournes'];
            debugPrint('SalesPage: ristournes type=${rist.runtimeType}, value=$rist');
            setState(() {
              _ristournes = rist is List
                  ? rist
                  : (rist is Map<String, dynamic> && rist['data'] is List
                        ? rist['data'] as List
                        : const []);
            });
            debugPrint('SalesPage: _ristournes.length=${_ristournes.length}');
          }
        } on ApiException catch (e) {
          debugPrint('SalesPage: ristournes API error: ${e.message} (code=${e.statusCode})');
        } catch (e, stack) {
          debugPrint('SalesPage: ristournes load error: $e\n$stack');
        }
      } else {
        debugPrint('SalesPage: missionType=$_missionType, skipping ristournes load');
      }

      // Charger les ventes
      final query = <String>['mission_id=$missionId'];

      if (_todayOnly) {
        query.add('date=${Uri.encodeComponent(_currentDayLabel)}');
      }

      final data = await client.getJson(
        '${AppConfig.salesPath}?${query.join('&')}',
      );

      final list = data is List
          ? data
          : (data is Map<String, dynamic> && data['data'] is List
                ? data['data'] as List
                : null);

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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Vente invalide')));
      }
      return;
    }

    try {
      final client = ApiService.instance.createClient();
      final resp = await client.getJson(
        '${AppConfig.ventePath}/$saleId/facture',
      );
      final payload = resp is Map<String, dynamic>
          ? (resp['data'] is Map<String, dynamic>
                ? resp['data'] as Map<String, dynamic>
                : resp)
          : null;

      final vente = payload?['vente'];
      final params = payload?['params'];
      final lines = <SaleInvoiceLine>[];

      if (vente is Map<String, dynamic>) {
        final details = vente['details'];
        if (details is List) {
          for (final d in details) {
            if (d is! Map<String, dynamic>) continue;
            final btlParCs =
                double.tryParse(
                  d['bouteilles_par_caisses']?.toString() ?? '',
                ) ??
                24;
            final denom = btlParCs <= 0 ? 24 : btlParCs;
            final quantite =
                double.tryParse(d['quantite']?.toString() ?? '') ?? 0;
            if (quantite <= 0) continue;
            final caisses =
                double.tryParse(d['quantite_caisses']?.toString() ?? '') ??
                (quantite / denom);
            final caissesVidesRecues =
                double.tryParse(d['caisses_vides_recues']?.toString() ?? '') ??
                0;
            final prixCaisse =
                double.tryParse(d['prix_caisse']?.toString() ?? '') ??
                ((double.tryParse(d['prix_unitaire']?.toString() ?? '') ?? 0) *
                    denom);
            final sousTotal =
                double.tryParse(d['sous_total']?.toString() ?? '') ?? 0;

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
            date:
                DateTime.tryParse(
                  (vente['date_vente']?.toString() ?? '').replaceFirst(
                    ' ',
                    'T',
                  ),
                ) ??
                DateTime.now(),
            clientNom: vente['client_nom']?.toString() ?? 'Client',
            clientTelephone: vente['client_telephone']?.toString(),
            clientNumero: vente['client_numero']?.toString(),
            zoneNom: vente['zone_nom']?.toString(),
            devise: (params is Map<String, dynamic> && params['devise'] != null)
                ? params['devise'].toString()
                : 'CDF',
            companyName: params is Map<String, dynamic>
                ? params['nom_entreprise']?.toString()
                : null,
            companyAddress: params is Map<String, dynamic>
                ? params['adresse']?.toString()
                : null,
            companyTelephone: params is Map<String, dynamic>
                ? params['telephone']?.toString()
                : null,
            companyLogo: params is Map<String, dynamic>
                ? params['logo_url']?.toString() ?? params['logo']?.toString()
                : null,
            companyEmail: params is Map<String, dynamic>
                ? params['email_contact']?.toString()
                : null,
            companyContact: params is Map<String, dynamic>
                ? params['contact']?.toString()
                : null,
            companyRccm: params is Map<String, dynamic>
                ? params['rccm']?.toString()
                : null,
            companyIdNat: params is Map<String, dynamic>
                ? params['id_nat']?.toString()
                : null,
            companyNif: params is Map<String, dynamic>
                ? params['nif']?.toString()
                : null,
            companyAccount: params is Map<String, dynamic>
                ? params['numero_compte']?.toString()
                : null,
            produitsCumules: double.tryParse(
              payload?['totalCaissesClient']?.toString() ?? '',
            ),
            caPeriode: null,
            ristourneTaux: double.tryParse(
              (payload?['ristourneInfo'] is Map<String, dynamic>)
                  ? (payload?['ristourneInfo']
                                as Map<String, dynamic>)['taux_applique']
                            ?.toString() ??
                        ''
                  : '',
            ),
            ristourneMontant: double.tryParse(
              (payload?['ristourneInfo'] is Map<String, dynamic>)
                  ? (payload?['ristourneInfo']
                                as Map<String, dynamic>)['montant_ristourne']
                            ?.toString() ??
                        ''
                  : '',
            ),
            deductionLocale: double.tryParse(
              (payload?['ristourneInfo'] is Map<String, dynamic>)
                  ? (payload?['ristourneInfo']
                                as Map<String, dynamic>)['deduction_locale']
                            ?.toString() ??
                        ''
                  : '',
            ),
            tauxLocal: (payload?['ristourneInfo'] is Map<String, dynamic>)
                ? int.tryParse(
                    (payload?['ristourneInfo']
                            as Map<String, dynamic>)['taux_local']
                        ?.toString() ??
                    '',
                  )
                : null,
            montantRistourneNet: double.tryParse(
              (payload?['ristourneInfo'] is Map<String, dynamic>)
                  ? (payload?['ristourneInfo']
                                as Map<String, dynamic>)['montant_ristourne_net']
                            ?.toString() ??
                        ''
                  : '',
            ),
            ristourneInfoPresent:
                payload?['ristourneInfo'] is Map<String, dynamic>,
            vendeurNom:
                vente['created_by_prenom'] == null &&
                    vente['created_by_nom'] == null
                ? null
                : '${vente['created_by_prenom'] ?? ''} ${vente['created_by_nom'] ?? ''}'
                      .trim(),
            totalHt: double.tryParse(vente['total_ht']?.toString() ?? '') ?? 0,
            totalTva:
                double.tryParse(vente['total_tva']?.toString() ?? '') ?? 0,
            totalTtc:
                double.tryParse(vente['total_ttc']?.toString() ?? '') ?? 0,
            lignes: lines,
            autoPrint: true,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Impression impossible: $e')));
    }
  }

  Future<void> _payRistourne(dynamic rist) async {
    if (rist == null) return;
    final ristId = rist['ristourne_id'] ?? rist['id'];
    if (ristId == null) return;
    final session = AuthService.instance.session;
    final userId = session?.agent?.id;
    if (userId == null) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Utilisateur non connecté')),
        );
      return;
    }

    try {
      final client = ApiService.instance.createClient();
      await client.postJson('/api/mobile/ristournes/$ristId/payer', {
        'user_id': userId,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ristourne marquée payée')),
        );
        await _load();
      }
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _encaisserRistourne(dynamic rist) async {
    if (rist == null) return;
    final mrId = rist['id']; // mission_ristournes.id
    if (mrId == null) return;

    final caissesPrevues = int.tryParse('${rist['caisses_prevues'] ?? 0}') ?? 0;
    final caissesLivreesCtrl = TextEditingController(
      text: '${rist['caisses_livrees'] ?? 0}',
    );
    final caissesVidesCtrl = TextEditingController(
      text: '${rist['caisses_vides_recues'] ?? 0}',
    );
    final propositionCtrl = TextEditingController(
      text: (rist['proposition_montant'] ?? '').toString(),
    );
    bool complementConfirme = (rist['complement_confirme'] ?? 0) == 1;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Confirmer la livraison'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Client: ${rist['client_nom'] ?? 'Client'} · Produit: ${rist['produit_nom'] ?? '-'}',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Ristourne: ${_fmtMoney(_asDouble(rist['montant_ristourne']))} · Prévu: $caissesPrevues cs',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                  ),
                  const Divider(height: 20),
                  TextField(
                    controller: caissesLivreesCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Caisses livrées',
                      hintText: 'Max: $caissesPrevues cs',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: caissesVidesCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Caisses vides reçues',
                      helperText: 'Nombre de caisses vides rendues par le client',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const Divider(height: 20),
                  SwitchListTile(
                    value: complementConfirme,
                    onChanged: (v) => setDialogState(() => complementConfirme = v),
                    title: const Text('Complément confirmé'),
                    subtitle: const Text('Le client a ajouté de l\'argent pour des caisses entières'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  if (complementConfirme) ...[
                    const SizedBox(height: 6),
                    TextField(
                      controller: propositionCtrl,
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Montant du complément',
                        helperText: 'Montant ajouté par le client au-delà de la ristourne',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Enregistrer'),
              ),
            ],
          ),
        );
      },
    );

    if (result != true) return;

    final caissesLivrees = int.tryParse(caissesLivreesCtrl.text) ?? 0;
    final caissesVides = int.tryParse(caissesVidesCtrl.text) ?? 0;
    final proposition = double.tryParse(propositionCtrl.text.replaceAll(',', '.'));

    try {
      final client = ApiService.instance.createClient();
      final payload = <String, dynamic>{
        'user_id': AuthService.instance.session?.agent?.id,
        'caisses_livrees': caissesLivrees,
        'caisses_vides_recues': caissesVides,
        'complement_confirme': complementConfirme ? 1 : 0,
      };
      if (complementConfirme && proposition != null) {
        payload['proposition_montant'] = proposition;
      }

      await client.postJson(
        '/api/mobile/mission_ristournes/$mrId/encaisser',
        payload,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ristourne livrée et encaissement enregistré')),
        );
        AppRefreshService.instance.notifyDataChanged();
        await _load();
      }
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Widget _ristourneBadge(String statut, ColorScheme scheme) {
    Color bg;
    Color fg;
    String label;
    switch (statut) {
      case 'livree':
        bg = scheme.primaryContainer;
        fg = scheme.onPrimaryContainer;
        label = 'Livrée';
        break;
      case 'non_livree':
        bg = scheme.errorContainer;
        fg = scheme.onErrorContainer;
        label = 'Non livrée';
        break;
      default:
        bg = scheme.tertiaryContainer;
        fg = scheme.onTertiaryContainer;
        label = 'En attente';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.w700)),
    );
  }

  Widget _caseInfoChip(String label, String value, IconData icon, ColorScheme scheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: scheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Text('$label: ', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
        Text('$value cs', style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
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

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _fmtMoney(double value) {
    final session = AuthService.instance.session;
    final devise = session?.settings?['devise']?.toString() ?? 'CDF';
    final deviseBase = session?.settings?['devise_base']?.toString() ?? 'CDF';
    final taux = _asDouble(session?.settings?['taux_change']);
    double display = value;
    if (devise != deviseBase && deviseBase == 'CDF' && devise == 'USD' && taux > 0) {
      display = value / taux;
    } else if (devise != deviseBase && deviseBase == 'USD' && devise == 'CDF' && taux > 0) {
      display = value * taux;
    }
    return '${display.toStringAsFixed(2)} $devise';
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
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
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
        return sum +
            (raw is num
                ? raw.toDouble()
                : double.tryParse(raw?.toString() ?? '') ?? 0);
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
                colors: [
                  scheme.primaryContainer.withOpacity(0.95),
                  scheme.surface,
                ],
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
                      child: Icon(
                        Icons.point_of_sale_rounded,
                        color: scheme.onPrimary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _missionType == 'ristourne'
                                ? 'Mission : Ristourne'
                                : 'Ventes de la mission',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _missionType == 'ristourne'
                                ? 'Cette mission est une ristourne — utilisez la section Ristournes pour gérer les montants.'
                                : 'Vue claire des factures enregistrées sur le terrain.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
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
                if (_missionType == 'vente')
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const CreateSalePage(),
                          ),
                        );
                        if (result == true) {
                          await _load();
                        }
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Nouvelle vente'),
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : () => _load(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Actualiser ristournes'),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Ristournes section (mission ristournes) - always visible for ristourne missions
          if (_missionType == 'ristourne' || _ristournes.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scheme.tertiaryContainer.withOpacity(0.95),
                    scheme.surface,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: scheme.tertiary.withOpacity(0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: scheme.tertiary,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(Icons.card_giftcard_rounded, color: scheme.onTertiary, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ristournes de la mission',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _ristournes.isNotEmpty
                                  ? '${_ristournes.where((r) => (r['statut'] ?? '') == 'livree').length} / ${_ristournes.length} livrée(s)'
                                  : 'Aucune ristourne chargée',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_ristournes.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Builder(builder: (context) {
                      final livrees = _ristournes.where((r) => (r['statut'] ?? '') == 'livree').length;
                      final totalCsPrev = _ristournes.fold<int>(0, (sum, r) => sum + (int.tryParse('${r['caisses_prevues'] ?? 0}') ?? 0));
                      final totalCsLiv = _ristournes.fold<int>(0, (sum, r) => sum + (int.tryParse('${r['caisses_livrees'] ?? 0}') ?? 0));
                      final totalVides = _ristournes.fold<int>(0, (sum, r) => sum + (int.tryParse('${r['caisses_vides_recues'] ?? 0}') ?? 0));
                      double totalMontantRecolte = 0;
                      for (final r in _ristournes) {
                        if (r is! Map<String, dynamic>) continue;
                        final csLiv = int.tryParse('${r['caisses_livrees'] ?? 0}') ?? 0;
                        final montRist = _asDouble(r['montant_ristourne']);
                        final confirme = (r['complement_confirme'] ?? 0) == 1;
                        if (confirme && csLiv > 0) {
                          final btlPerCs = int.tryParse('${r['bouteilles_par_caisses'] ?? 24}') ?? 24;
                          final prixCs = _asDouble(r['prix_vente_caisses']);
                          final prixUnit = _asDouble(r['prix_vente_unitaire']);
                          final prix = prixCs > 0 ? prixCs : prixUnit * (btlPerCs > 0 ? btlPerCs : 24);
                          totalMontantRecolte += max(0, csLiv * prix - montRist);
                        }
                      }
                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: _summaryTile(label: 'Clients servis', value: '$livrees/${_ristournes.length}', icon: Icons.people_outlined, scheme: scheme)),
                              const SizedBox(width: 8),
                              Expanded(child: _summaryTile(label: 'Cs prévues / livrées', value: '$totalCsPrev / $totalCsLiv', icon: Icons.inventory_2_outlined, scheme: scheme)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(child: _summaryTile(label: 'Vides reçues', value: '$totalVides', icon: Icons.replay, scheme: scheme)),
                              const SizedBox(width: 8),
                              Expanded(child: _summaryTile(label: 'Complément récolté', value: _fmtMoney(totalMontantRecolte), icon: Icons.add_card_outlined, scheme: scheme)),
                            ],
                          ),
                        ],
                      );
                    }),
                  ],
                  const SizedBox(height: 8),
                  if (_ristournes.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.inbox_outlined, size: 32, color: scheme.onSurfaceVariant),
                            const SizedBox(height: 8),
                            Text(
                              _loading ? 'Chargement des ristournes...' : 'Aucune ristourne chargée',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    for (final r in _ristournes)
                      if (r is Map<String, dynamic>)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: (r['statut'] ?? '') == 'livree'
                                    ? scheme.primary.withOpacity(0.3)
                                    : (r['statut'] ?? '') == 'non_livree'
                                        ? scheme.error.withOpacity(0.3)
                                        : scheme.outlineVariant,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  '${r['client_nom'] ?? 'Client'}',
                                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (r['numero_client'] != null && r['numero_client'].toString().isNotEmpty) ...[
                                                const SizedBox(width: 4),
                                                Text(
                                                  '(${r['numero_client']})',
                                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                    color: scheme.onSurfaceVariant,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                              const SizedBox(width: 6),
                                              _ristourneBadge(r['statut'] ?? 'en_attente', scheme),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${r['produit_nom'] ?? '-'}',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          _fmtMoney(_asDouble(r['montant_ristourne'])),
                                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                                        ),
                                        if (_asDouble(r['montant_livre']) > 0)
                                          Text(
                                            'Livré: ${_fmtMoney(_asDouble(r['montant_livre']))}',
                                            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.primary),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: scheme.surfaceContainerHighest.withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      _caseInfoChip('Prévu', '${r['caisses_prevues'] ?? 0}', Icons.plagiarism_outlined, scheme),
                                      _caseInfoChip('Livré', '${r['caisses_livrees'] ?? 0}', Icons.local_shipping_outlined, scheme),
                                      _caseInfoChip('Vides', '${r['caisses_vides_recues'] ?? 0}', Icons.replay, scheme),
                                    ],
                                  ),
                                ),
                                if (_asDouble(r['proposition_montant']) > 0) ...[
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: (r['complement_confirme'] ?? 0) == 1
                                          ? scheme.tertiaryContainer.withOpacity(0.5)
                                          : scheme.errorContainer.withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Wrap(
                                      spacing: 4,
                                      runSpacing: 2,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        Icon(
                                          (r['complement_confirme'] ?? 0) == 1 ? Icons.check_circle_outline : Icons.pending_outlined,
                                          size: 14,
                                          color: (r['complement_confirme'] ?? 0) == 1 ? scheme.tertiary : scheme.error,
                                        ),
                                        Text(
                                          'Complément: ${_fmtMoney(_asDouble(r['proposition_montant']))}',
                                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                            color: (r['complement_confirme'] ?? 0) == 1 ? scheme.tertiary : scheme.error,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if ((r['complement_confirme'] ?? 0) == 1)
                                          Text(
                                            '✓',
                                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                              color: scheme.tertiary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                                if ((r['statut'] ?? '') != 'livree') ...[
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton.tonalIcon(
                                      onPressed: () => _encaisserRistourne(r),
                                      icon: const Icon(Icons.local_shipping_outlined, size: 18),
                                      label: const Text('Livrer cette ristourne'),
                                    ),
                                  ),
                                ] else ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(Icons.check_circle, size: 16, color: scheme.primary),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Ristourne livrée',
                                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                          color: scheme.primary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
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
              child: Text(_error!, style: TextStyle(color: scheme.error)),
            ),
          if (_missionType == 'vente' && _error == null && _sales.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Aucune vente à afficher.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 8),
          if (_missionType == 'vente')
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
                                    child: Icon(
                                      Icons.receipt_long,
                                      color: scheme.onPrimaryContainer,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (item['numero_facture'] ??
                                                  item['reference'] ??
                                                  item['id'] ??
                                                  'Vente')
                                              .toString(),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '${(item['client_nom'] ?? item['client'] ?? 'Client').toString()} · ${(item['total_ttc'] ?? item['total'] ?? '').toString()}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: scheme.onSurfaceVariant,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Caisses vendues: ${(item['caisses_vendues'] ?? 0).toString()} · ${_formatSaleTime(item['date_vente']?.toString())}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: scheme.onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: scheme.secondaryContainer,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Text(
                                      (item['date_vente'] ?? '')
                                          .toString()
                                          .split(' ')
                                          .first,
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
