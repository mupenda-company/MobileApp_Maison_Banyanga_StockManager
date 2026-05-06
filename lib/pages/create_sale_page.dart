import 'package:flutter/material.dart';
import 'package:logis_agent/api/api_client.dart';
import 'package:logis_agent/config/app_config.dart';
import 'package:logis_agent/pages/sale_invoice_page.dart';
import 'package:logis_agent/services/api_service.dart';
import 'package:logis_agent/services/app_refresh_service.dart';
import 'package:logis_agent/services/auth_service.dart';

class CreateSalePage extends StatefulWidget {
  const CreateSalePage({super.key});

  @override
  State<CreateSalePage> createState() => _CreateSalePageState();
}

class _CreateSalePageState extends State<CreateSalePage> {
  bool _loading = false;
  bool _saving = false;
  String? _error;

  List<Map<String, dynamic>> _clients = const [];
  List<Map<String, dynamic>> _stock = const [];

  String? _clientId;
  String _clientSearch = '';

  final Map<int, TextEditingController> _qtyCsControllers = {};
  final TextEditingController _notesController = TextEditingController();

  @override
  void dispose() {
    for (final c in _qtyCsControllers.values) {
      c.dispose();
    }
    _notesController.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _settings => AuthService.instance.session?.settings;

  String get _devise {
    final d = _settings?['devise']?.toString();
    return (d == null || d.isEmpty) ? 'CDF' : d;
  }

  String get _deviseBase {
    final d = _settings?['devise_base']?.toString();
    return (d == null || d.isEmpty) ? 'CDF' : d;
  }

  double get _tauxChange {
    final v = _settings?['taux_change'];
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 2800;
  }

  double _toDisplay(double amountBase) {
    if (_devise == _deviseBase) return amountBase;
    if (_deviseBase == 'CDF' && _devise == 'USD') return amountBase / _tauxChange;
    if (_deviseBase == 'USD' && _devise == 'CDF') return amountBase * _tauxChange;
    return amountBase;
  }

  String _fmtAmount(double value) {
    final v = value.isNaN || value.isInfinite ? 0 : value;
    return '${v.toStringAsFixed(2)} $_devise';
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _btlParCaisse(Map<String, dynamic> item) {
    final v = item['bouteilles_par_caisses'];
    final d = _asDouble(v);
    return d <= 0 ? 24 : d;
  }

  double _prixCaisseBase(Map<String, dynamic> item) {
    final btlParCs = _btlParCaisse(item);
    final prixCaisse = _asDouble(item['prix_vente_caisses']);
    if (prixCaisse > 0) {
      return prixCaisse;
    }

    final prixUnitaire = _asDouble(item['prix_vente_unitaire']);
    return prixUnitaire * btlParCs;
  }

  String? get _missionId {
    return AuthService.instance.session?.mission?['id']?.toString();
  }

  String? get _userId {
    return AuthService.instance.session?.agent?.id?.toString();
  }

  List<Map<String, dynamic>> get _filteredClients {
    final term = _clientSearch.trim().toLowerCase();
    final clients = _clients;

    if (term.isEmpty) {
      return clients;
    }

    final filtered = clients.where((client) {
      final haystack = [
        client['nom'],
        client['telephone'],
        client['zone_nom'],
        client['email'],
        client['adresse'],
      ].where((value) => value != null).map((value) => value.toString()).join(' ').toLowerCase();
      return haystack.contains(term);
    }).toList();

    final selected = clients.where((client) => client['id']?.toString() == _clientId).cast<Map<String, dynamic>>().toList();
    if (selected.isNotEmpty && !filtered.any((client) => client['id']?.toString() == _clientId)) {
      filtered.insert(0, selected.first);
    }

    return filtered;
  }

  Future<void> _load() async {
    if (AppConfig.apiBaseUrl.isEmpty) {
      setState(() {
        _error = 'API_BASE_URL non configuré';
      });
      return;
    }

    final missionId = _missionId;
    if (missionId == null || missionId.isEmpty) {
      setState(() {
        _error = 'Aucune mission en cours';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = ApiService.instance.createClient();

      final clientsResp = await client.getJson(AppConfig.clientsPath);
      final clientsList = clientsResp is List
          ? clientsResp
          : (clientsResp is Map<String, dynamic> && clientsResp['data'] is List ? clientsResp['data'] as List : null);

      final stockResp = await client.getJson('${AppConfig.missionPath}/$missionId/stock');
      final stockList = stockResp is List
          ? stockResp
          : (stockResp is Map<String, dynamic> && stockResp['data'] is List ? stockResp['data'] as List : null);

      final mappedClients = <Map<String, dynamic>>[];
      for (final c in (clientsList ?? const [])) {
        if (c is Map<String, dynamic>) mappedClients.add(c);
      }

      final mappedStock = <Map<String, dynamic>>[];
      for (final s in (stockList ?? const [])) {
        if (s is Map<String, dynamic>) mappedStock.add(s);
      }

      for (final item in mappedStock) {
        final id = int.tryParse(item['id']?.toString() ?? '');
        if (id == null) continue;
        _qtyCsControllers.putIfAbsent(id, () {
          final c = TextEditingController(text: '0');
          c.addListener(() {
            if (mounted) setState(() {});
          });
          return c;
        });
      }

      setState(() {
        _clients = mappedClients;
        _stock = mappedStock;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  double get _totalBase {
    double total = 0;
    for (final item in _stock) {
      final id = int.tryParse(item['id']?.toString() ?? '');
      if (id == null) continue;

      final qtyCsText = _qtyCsControllers[id]?.text ?? '0';
      final qtyCs = double.tryParse(qtyCsText.replaceAll(',', '.')) ?? 0;
      if (qtyCs <= 0) continue;

      final prixCaisseBase = _prixCaisseBase(item);
      total += qtyCs * prixCaisseBase;
    }
    return total;
  }

  Future<void> _save() async {
    if (_saving) return;

    final missionId = _missionId;
    final userId = _userId;

    if (missionId == null || missionId.isEmpty) {
      setState(() {
        _error = 'Aucune mission en cours';
      });
      return;
    }

    if (userId == null || userId.isEmpty) {
      setState(() {
        _error = 'Utilisateur non identifié';
      });
      return;
    }

    if (_clientId == null || _clientId!.isEmpty) {
      setState(() {
        _error = 'Veuillez sélectionner un client';
      });
      return;
    }

    final produits = <Map<String, dynamic>>[];
    for (final item in _stock) {
      final id = int.tryParse(item['id']?.toString() ?? '');
      if (id == null) continue;

      final qtyCsText = _qtyCsControllers[id]?.text ?? '0';
      final qtyCs = double.tryParse(qtyCsText.replaceAll(',', '.')) ?? 0;
      if (qtyCs <= 0) continue;

      final btlParCs = _btlParCaisse(item);
      final qtyBtl = qtyCs * btlParCs;
      final prixCaisseBase = _prixCaisseBase(item);
      final prixCaisseDisplay = _toDisplay(prixCaisseBase);

      produits.add({
        'produit_id': id,
        'quantite': qtyBtl,
        'quantite_caisses': qtyCs,
        'prix_caisse': prixCaisseDisplay,
        'prix_unitaire': prixCaisseDisplay / btlParCs,
      });
    }

    if (produits.isEmpty) {
      setState(() {
        _error = 'Veuillez saisir au moins un produit';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final client = ApiService.instance.createClient();

      final resp = await client.postJson(AppConfig.ventePath, {
        'client_id': int.tryParse(_clientId!) ?? _clientId,
        'mission_id': int.tryParse(missionId) ?? missionId,
        'user_id': int.tryParse(userId) ?? userId,
        'devise': _devise,
        'notes': _notesController.text.trim(),
        'produits': produits,
      });

      Map<String, dynamic>? payload;
      if (resp is Map<String, dynamic>) {
        final data = resp['data'];
        if (data is Map<String, dynamic>) {
          payload = data;
        } else {
          payload = resp;
        }
      }

      final venteId = int.tryParse(payload?['vente_id']?.toString() ?? '') ?? 0;
      final numeroFacture = payload?['numero_facture']?.toString();

      final totalHtBase = _asDouble(payload?['total_ht']);
      final totalTvaBase = _asDouble(payload?['total_tva']);
      final totalTtcBase = _asDouble(payload?['total_ttc']);

      String clientNom = 'Client';
      String? clientTelephone;
      String? zoneNom;

      String? companyName;
      String? companyAddress;
      String? companyTelephone;

      double? produitsCumules;
      double? caPeriode;
      double? ristourneTaux;
      double? ristourneMontant;
      String? vendeurNom;
      bool ristourneInfoPresent = false;

      var dateFacture = DateTime.now();
      final lignes = <SaleInvoiceLine>[];

      if (venteId > 0) {
        try {
          final factureResp = await client.getJson('${AppConfig.ventePath}/$venteId/facture');
          final facturePayload = factureResp is Map<String, dynamic>
              ? (factureResp['data'] is Map<String, dynamic> ? factureResp['data'] as Map<String, dynamic> : factureResp)
              : null;

          final vente = facturePayload?['vente'];
          final params = facturePayload?['params'];

          if (params is Map<String, dynamic>) {
            companyName = params['nom_entreprise']?.toString();
            companyAddress = params['adresse']?.toString();
            companyTelephone = params['telephone']?.toString();
          }

          if (vente is Map<String, dynamic>) {
            clientNom = vente['client_nom']?.toString() ?? clientNom;
            clientTelephone = vente['client_telephone']?.toString();
            zoneNom = vente['zone_nom']?.toString();

            final cbn = '${vente['created_by_prenom'] ?? ''} ${vente['created_by_nom'] ?? ''}'.trim();
            vendeurNom = cbn.isEmpty ? null : cbn;

            final dateStr = vente['date_vente']?.toString();
            if (dateStr != null && dateStr.isNotEmpty) {
              final parsed = DateTime.tryParse(dateStr.replaceFirst(' ', 'T'));
              if (parsed != null) dateFacture = parsed;
            }

            final details = vente['details'];
            if (details is List) {
              for (final d in details) {
                if (d is! Map<String, dynamic>) continue;
                final quantite = _asDouble(d['quantite']);
                if (quantite <= 0) continue;

                final btlParCs = _asDouble(d['bouteilles_par_caisses']);
                final denom = btlParCs <= 0 ? 24 : btlParCs;
                final caisses = _asDouble(d['quantite_caisses']) > 0 ? _asDouble(d['quantite_caisses']) : (quantite / denom);

                final prixCaisseBase = _asDouble(d['prix_caisse']) > 0
                    ? _asDouble(d['prix_caisse'])
                    : (_asDouble(d['prix_unitaire']) * denom);
                final sousTotalBase = _asDouble(d['sous_total']);

                lignes.add(
                  SaleInvoiceLine(
                    produitNom: d['produit_nom']?.toString() ?? 'Produit',
                    caisses: caisses,
                    prixCaisse: _toDisplay(prixCaisseBase),
                    sousTotal: _toDisplay(sousTotalBase),
                  ),
                );
              }
            }
          }

          final totalCaissesClientBase = _asDouble(facturePayload?['totalCaissesClient']);
          if (totalCaissesClientBase > 0) {
            produitsCumules = totalCaissesClientBase;
          }

          final rist = facturePayload?['ristourneInfo'];
          if (rist is Map<String, dynamic>) {
            ristourneInfoPresent = true;
            final totalCs = _asDouble(rist['total_caisses']);
            if (totalCs > 0) {
              produitsCumules = totalCs;
            }

            final caTotalBase = _asDouble(rist['ca_total']);
            if (caTotalBase > 0) {
              caPeriode = _toDisplay(caTotalBase);
            }

            final taux = _asDouble(rist['taux_applique']);
            if (taux > 0) {
              ristourneTaux = taux;
            }

            final montantBase = _asDouble(rist['montant_ristourne']);
            if (montantBase != 0) {
              ristourneMontant = _toDisplay(montantBase);
            }
          }
        } catch (_) {
          // Fallback si endpoint facture non dispo
        }
      }

      if (lignes.isEmpty) {
        clientNom = _clients
                .firstWhere(
                  (c) => c['id']?.toString() == _clientId,
                  orElse: () => const <String, dynamic>{},
                )['nom']
                ?.toString() ??
            clientNom;

        for (final item in _stock) {
          final id = int.tryParse(item['id']?.toString() ?? '');
          if (id == null) continue;

          final qtyCsText = _qtyCsControllers[id]?.text ?? '0';
          final qtyCs = double.tryParse(qtyCsText.replaceAll(',', '.')) ?? 0;
          if (qtyCs <= 0) continue;

          final btlParCs = _btlParCaisse(item);
          final puBase = _asDouble(item['prix_vente_unitaire']);
          final prixCaisseBase = puBase * btlParCs;
          final sousTotalBase = (qtyCs * btlParCs) * puBase;

          lignes.add(
            SaleInvoiceLine(
              produitNom: (item['nom'] ?? 'Produit').toString(),
              caisses: qtyCs,
              prixCaisse: _toDisplay(prixCaisseBase),
              sousTotal: _toDisplay(sousTotalBase),
            ),
          );
        }
      }

      if (!mounted) return;

      if (venteId > 0) {
        AppRefreshService.instance.notifyDataChanged();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => SaleInvoicePage(
              venteId: venteId,
              numeroFacture: numeroFacture,
              date: dateFacture,
              clientNom: clientNom,
              clientTelephone: clientTelephone,
              zoneNom: zoneNom,
              devise: _devise,
              companyName: companyName,
              companyAddress: companyAddress,
              companyTelephone: companyTelephone,
              produitsCumules: produitsCumules,
              caPeriode: caPeriode,
              ristourneTaux: ristourneTaux,
              ristourneMontant: ristourneMontant,
              ristourneInfoPresent: ristourneInfoPresent,
              vendeurNom: vendeurNom,
              totalHt: _toDisplay(totalHtBase),
              totalTva: _toDisplay(totalTvaBase),
              totalTtc: _toDisplay(totalTtcBase),
              lignes: lignes,
            ),
          ),
        );
      } else {
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final totalDisplay = _toDisplay(_totalBase);

    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Nouvelle vente'),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Enregistrer'),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_loading) const LinearProgressIndicator(minHeight: 2),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      TextField(
                        enabled: !_saving,
                        onChanged: (value) {
                          setState(() {
                            _clientSearch = value;
                          });
                        },
                        decoration: InputDecoration(
                          labelText: 'Rechercher un client',
                          hintText: 'Nom, téléphone, zone...',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _clientSearch.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear_rounded),
                                  onPressed: () {
                                    setState(() {
                                      _clientSearch = '';
                                    });
                                  },
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey(_clientId),
                        initialValue: _clientId,
                        items: [
                          for (final c in _filteredClients)
                            DropdownMenuItem<String>(
                              value: c['id']?.toString(),
                              child: Text((c['nom'] ?? c['name'] ?? 'Client').toString()),
                            ),
                        ],
                        onChanged: _saving
                            ? null
                            : (value) {
                                setState(() {
                                  _clientId = value;
                                });
                              },
                        decoration: const InputDecoration(
                          labelText: 'Client',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _notesController,
                        enabled: !_saving,
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Notes',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Total (approx.)', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                                  const SizedBox(height: 6),
                                  Text(
                                    _fmtAmount(totalDisplay),
                                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Chip(
                            label: Text('Devise: $_devise'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Produits',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (final item in _stock)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (item['nom'] ?? 'Produit').toString(),
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Builder(
                                  builder: (context) {
                                    final stockActuelBtl = _asDouble(item['stock_actuel']);
                                    final btlParCs = _btlParCaisse(item);
                                    final stockActuelCs = stockActuelBtl / btlParCs;
                                    final prixCaisseDisplay = _toDisplay(_prixCaisseBase(item));

                                    return Text(
                                      'Stock: ${stockActuelCs.toStringAsFixed(1)} cs  |  Prix caisse: ${_fmtAmount(prixCaisseDisplay)}',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 110,
                            child: TextField(
                              controller: () {
                                final id = int.tryParse(item['id']?.toString() ?? '');
                                return id == null ? null : _qtyCsControllers[id];
                              }(),
                              enabled: !_saving,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Cs',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}
