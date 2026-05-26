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
  List<Map<String, dynamic>> _recentSales = const [];

  String? _clientId;
  String _clientSearch = '';

  final Map<int, TextEditingController> _qtyCsControllers = {};
  final Map<int, TextEditingController> _qtyEmptyControllers = {};
  final TextEditingController _notesController = TextEditingController();

  @override
  void dispose() {
    for (final c in _qtyCsControllers.values) {
      c.dispose();
    }
    for (final c in _qtyEmptyControllers.values) {
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

  String get _currentDayLabel {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String get _currentDeviceDateTimeLabel {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
  }

  String _formatSaleTime(String? value) {
    if (value == null || value.trim().isEmpty) return '';

    final parsed = DateTime.tryParse(value.replaceFirst(' ', 'T'));
    if (parsed == null) return value;

    return '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
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

  Future<void> _openInvoice(Map<String, dynamic> sale) async {
    final saleId = int.tryParse(sale['id']?.toString() ?? '');
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
                : _devise,
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
            produitsCumules: _asDouble(payload?['totalCaissesClient']) > 0 ? _asDouble(payload?['totalCaissesClient']) : null,
            caPeriode: null,
            ristourneTaux: double.tryParse((payload?['ristourneInfo'] is Map<String, dynamic>) ? (payload?['ristourneInfo'] as Map<String, dynamic>)['taux_applique']?.toString() ?? '' : ''),
            ristourneMontant: double.tryParse((payload?['ristourneInfo'] is Map<String, dynamic>) ? (payload?['ristourneInfo'] as Map<String, dynamic>)['montant_ristourne']?.toString() ?? '' : ''),
            ristourneInfoPresent: payload?['ristourneInfo'] is Map<String, dynamic>,
            vendeurNom: vente['created_by_prenom'] == null && vente['created_by_nom'] == null
                ? null
                : '${vente['created_by_prenom'] ?? ''} ${vente['created_by_nom'] ?? ''}'.trim(),
            totalHt: _asDouble(vente['total_ht']),
            totalTva: _asDouble(vente['total_tva']),
            totalTtc: _asDouble(vente['total_ttc']),
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

  String? get _missionId {
    return AuthService.instance.session?.mission?['id']?.toString();
  }

  bool get _isRistourne {
    return (AuthService.instance.session?.mission?['type_mission'] ?? 'vente').toString() == 'ristourne';
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
        _qtyEmptyControllers.putIfAbsent(id, () {
          final c = TextEditingController(text: '0');
          c.addListener(() {
            if (mounted) setState(() {});
          });
          return c;
        });
      }

      List<Map<String, dynamic>> mappedSales = [];
      try {
        final salesResp = await client.getJson('${AppConfig.salesPath}?mission_id=$missionId&date=${Uri.encodeComponent(_currentDayLabel)}');
        final salesList = salesResp is List
            ? salesResp
            : (salesResp is Map<String, dynamic> && salesResp['data'] is List ? salesResp['data'] as List : null);

        for (final s in (salesList ?? const [])) {
          if (s is Map<String, dynamic>) mappedSales.add(s);
        }
      } catch (_) {
        mappedSales = [];
      }

      setState(() {
        _clients = mappedClients;
        _stock = mappedStock;
        _recentSales = mappedSales;
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

  double get _totalEmballagesRecus {
    double total = 0;
    for (final item in _stock) {
      final id = int.tryParse(item['id']?.toString() ?? '');
      if (id == null) continue;

      final qtyCsText = _qtyCsControllers[id]?.text ?? '0';
      final qtyCs = double.tryParse(qtyCsText.replaceAll(',', '.')) ?? 0;
      if (qtyCs <= 0) continue;

      final qtyEmptyText = _qtyEmptyControllers[id]?.text ?? '0';
      final qtyEmptyInput = double.tryParse(qtyEmptyText.replaceAll(',', '.')) ?? 0;
      total += qtyEmptyInput > qtyCs ? qtyCs : qtyEmptyInput;
    }
    return total;
  }

  double get _totalDetteEmballages {
    double total = 0;
    for (final item in _stock) {
      final id = int.tryParse(item['id']?.toString() ?? '');
      if (id == null) continue;

      final qtyCsText = _qtyCsControllers[id]?.text ?? '0';
      final qtyCs = double.tryParse(qtyCsText.replaceAll(',', '.')) ?? 0;
      if (qtyCs <= 0) continue;

      final qtyEmptyText = _qtyEmptyControllers[id]?.text ?? '0';
      final qtyEmptyInput = double.tryParse(qtyEmptyText.replaceAll(',', '.')) ?? 0;
      final qtyEmpty = qtyEmptyInput > qtyCs ? qtyCs : qtyEmptyInput;
      total += qtyCs - qtyEmpty;
    }
    return total;
  }

  double get _totalCaisses {
    double total = 0;
    for (final item in _stock) {
      final id = int.tryParse(item['id']?.toString() ?? '');
      if (id == null) continue;

      final qtyCsText = _qtyCsControllers[id]?.text ?? '0';
      total += double.tryParse(qtyCsText.replaceAll(',', '.')) ?? 0;
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

      final qtyEmptyText = _qtyEmptyControllers[id]?.text ?? '0';
      final qtyEmptyInput = double.tryParse(qtyEmptyText.replaceAll(',', '.')) ?? 0;
      final qtyEmpty = qtyEmptyInput > qtyCs ? qtyCs : qtyEmptyInput;

      final btlParCs = _btlParCaisse(item);
      final qtyBtl = qtyCs * btlParCs;
      final prixCaisseBase = _prixCaisseBase(item);
      final prixCaisseDisplay = _toDisplay(prixCaisseBase);

      produits.add({
        'produit_id': id,
        'quantite': qtyBtl,
        'quantite_caisses': qtyCs,
        'caisses_vides_recues': qtyEmpty,
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
        'date_vente': _currentDeviceDateTimeLabel,
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
      String? clientNumero;
      String? zoneNom;

      String? companyName;
      String? companyAddress;
      String? companyTelephone;
      String? companyLogo;
      String? companyEmail;
      String? companyContact;
      String? companyRccm;
      String? companyIdNat;
      String? companyNif;
      String? companyAccount;

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
            companyLogo = params['logo_url']?.toString() ?? params['logo']?.toString();
            companyEmail = params['email_contact']?.toString();
            companyContact = params['contact']?.toString();
            companyRccm = params['rccm']?.toString();
            companyIdNat = params['id_nat']?.toString();
            companyNif = params['nif']?.toString();
            companyAccount = params['numero_compte']?.toString();
          }

          if (vente is Map<String, dynamic>) {
            clientNom = vente['client_nom']?.toString() ?? clientNom;
            clientTelephone = vente['client_telephone']?.toString();
            clientNumero = vente['client_numero']?.toString();
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
                final caissesVidesRecues = _asDouble(d['caisses_vides_recues']);
                final detteCaisses = caisses - caissesVidesRecues;

                final prixCaisseBase = _asDouble(d['prix_caisse']) > 0
                    ? _asDouble(d['prix_caisse'])
                    : (_asDouble(d['prix_unitaire']) * denom);
                final sousTotalBase = _asDouble(d['sous_total']);

                lignes.add(
                  SaleInvoiceLine(
                    produitNom: d['produit_nom']?.toString() ?? 'Produit',
                    caisses: caisses,
                    caissesVidesRecues: caissesVidesRecues,
                    detteCaisses: detteCaisses < 0 ? 0 : detteCaisses,
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
          final qtyEmpty = _asDouble(item['caisses_vides_recues']);

          lignes.add(
            SaleInvoiceLine(
              produitNom: (item['nom'] ?? 'Produit').toString(),
              caisses: qtyCs,
              caissesVidesRecues: qtyEmpty,
              detteCaisses: qtyCs - qtyEmpty < 0 ? 0 : qtyCs - qtyEmpty,
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
              clientNumero: clientNumero,
              zoneNom: zoneNom,
              devise: _devise,
              companyName: companyName,
              companyAddress: companyAddress,
              companyTelephone: companyTelephone,
              companyLogo: companyLogo,
              companyEmail: companyEmail,
              companyContact: companyContact,
              companyRccm: companyRccm,
              companyIdNat: companyIdNat,
              companyNif: companyNif,
              companyAccount: companyAccount,
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
    final totalCaisses = _totalCaisses;
    final totalEmballagesRecus = _totalEmballagesRecus;
    final totalDetteEmballages = _totalDetteEmballages;

    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Nouvelle vente'),
          actions: [
            if (!_isRistourne)
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
              if (_isRistourne)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: scheme.error),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.block_rounded, size: 48, color: scheme.onErrorContainer),
                      const SizedBox(height: 16),
                      Text(
                        'Mission de ristourne',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: scheme.onErrorContainer,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Les ventes ne sont pas possibles sur une mission de ristourne. Utilisez l\'onglet Ristournes pour gérer les livraisons.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onErrorContainer,
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
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
                        isExpanded: true,
                        key: ValueKey(_clientId),
                        initialValue: _clientId,
                        selectedItemBuilder: (context) {
                          return _filteredClients
                              .map(
                                (c) => Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    (c['nom'] ?? c['name'] ?? 'Client').toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    softWrap: false,
                                  ),
                                ),
                              )
                              .toList();
                        },
                        items: [
                          for (final c in _filteredClients)
                            DropdownMenuItem<String>(
                              value: c['id']?.toString(),
                              child: Text(
                                (c['nom'] ?? c['name'] ?? 'Client').toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                              ),
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
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 520;

                          final totalCard = Container(
                            width: compact ? double.infinity : null,
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
                                const SizedBox(height: 4),
                                Text(
                                  'Caisses totales: ${totalCaisses.toStringAsFixed(1)} cs',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Emballages reçus: ${totalEmballagesRecus.toStringAsFixed(1)} cs  |  Dette: ${totalDetteEmballages.toStringAsFixed(1)} cs',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          );

                          final currencyChip = Chip(label: Text('Devise: $_devise'));

                          if (compact) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                totalCard,
                                const SizedBox(height: 10),
                                Align(alignment: Alignment.centerLeft, child: currencyChip),
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(child: totalCard),
                              const SizedBox(width: 10),
                              currencyChip,
                            ],
                          );
                        },
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
                      child: Builder(
                        builder: (context) {
                          final stockActuelCs = _asDouble(item['stock_actuel_caisses']);
                          final stockActuelAlias = _asDouble(item['stock_actuel']);
                          final btlParCs = _btlParCaisse(item);
                          final stockActuelDisplay = stockActuelCs > 0 ? stockActuelCs : (stockActuelAlias > 0 ? stockActuelAlias : (_asDouble(item['stock_actuel_bouteilles']) / btlParCs));
                          final prixCaisseDisplay = _toDisplay(_prixCaisseBase(item));
                          final id = int.tryParse(item['id']?.toString() ?? '');
                          final qtyCsText = id == null ? '0' : (_qtyCsControllers[id]?.text ?? '0');
                          final qtyCs = _asDouble(qtyCsText.replaceAll(',', '.'));
                          final qtyEmptyText = id == null ? '0' : (_qtyEmptyControllers[id]?.text ?? '0');
                          final qtyEmptyInput = _asDouble(qtyEmptyText.replaceAll(',', '.'));
                          final qtyEmpty = qtyEmptyInput > qtyCs ? qtyCs : qtyEmptyInput;
                          final totalLigne = qtyCs * prixCaisseDisplay;
                          final stockInsuffisant = qtyCs > stockActuelDisplay;
                          final detteEmballages = qtyCs - qtyEmpty;

                          final qtyCsController = () {
                            final id = int.tryParse(item['id']?.toString() ?? '');
                            return id == null ? null : _qtyCsControllers[id];
                          }();
                          final qtyEmptyController = () {
                            final id = int.tryParse(item['id']?.toString() ?? '');
                            return id == null ? null : _qtyEmptyControllers[id];
                          }();

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (item['nom'] ?? 'Produit').toString(),
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Stock mission disponible: ${stockActuelDisplay.toStringAsFixed(1)} cs  |  Prix caisse: ${_fmtAmount(prixCaisseDisplay)}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Caisses saisies: ${qtyCs.toStringAsFixed(1)} cs  |  Total ligne: ${_fmtAmount(totalLigne)}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Emballages reçus: ${qtyEmpty.toStringAsFixed(1)} cs  |  Dette: ${detteEmballages.toStringAsFixed(1)} cs',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              if (stockInsuffisant) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Stock mission insuffisant: ${qtyCs.toStringAsFixed(1)} cs demandées / ${stockActuelDisplay.toStringAsFixed(1)} cs disponibles',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: scheme.error,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ],
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: qtyCsController,
                                      enabled: !_saving,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: const InputDecoration(
                                        labelText: 'Caisses',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextField(
                                      controller: qtyEmptyController,
                                      enabled: !_saving,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: const InputDecoration(
                                        labelText: 'Vides',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              const SizedBox(height: 8),
              Text(
                'Historique des ventes récentes',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_recentSales.isEmpty)
                        Text(
                          'Aucune vente enregistrée aujourd’hui.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        )
                      else
                        for (final sale in _recentSales.take(8))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: scheme.surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: scheme.outlineVariant),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: scheme.primaryContainer,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Icon(Icons.receipt_long, color: scheme.onPrimaryContainer, size: 20),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              (sale['numero_facture'] ?? sale['reference'] ?? 'Vente').toString(),
                                              style: const TextStyle(fontWeight: FontWeight.w700),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${(sale['client_nom'] ?? 'Client').toString()} · Caisses: ${(sale['caisses_vendues'] ?? 0).toString()}',
                                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Heure: ${_formatSaleTime(sale['date_vente']?.toString())}',
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
                                    children: [
                                      Text(
                                        _fmtAmount(_toDisplay(_asDouble(sale['total_ttc']))),
                                        style: const TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                      IconButton.filledTonal(
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => _openInvoice(sale),
                                        icon: const Icon(Icons.print_rounded),
                                        tooltip: 'Imprimer la facture',
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ],
              ],
          ),
        ),
      ),
    );
  }
}
