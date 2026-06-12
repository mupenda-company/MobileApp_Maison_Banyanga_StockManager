import 'package:flutter/material.dart';
import 'package:logis_agent/api/api_client.dart';
import 'package:logis_agent/config/app_config.dart';
import 'package:logis_agent/pages/sale_invoice_page.dart';
import 'package:logis_agent/services/api_service.dart';
import 'package:logis_agent/services/auth_service.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class AgentSalesHistoryPage extends StatefulWidget {
  final bool embedInScaffold;

  const AgentSalesHistoryPage({super.key, this.embedInScaffold = true});

  @override
  State<AgentSalesHistoryPage> createState() => _AgentSalesHistoryPageState();
}

class _AgentSalesHistoryPageState extends State<AgentSalesHistoryPage> {
  bool _loading = false;
  String? _error;
  List<dynamic> _sales = [];
  final Set<int> _expandedSales = {};
  final TextEditingController _clientSearchController = TextEditingController();
  String _clientSearch = '';

  DateTime _dateDebut = DateTime.now();
  DateTime _dateFin = DateTime.now();

  List<dynamic> get _filteredSales {
    final term = _clientSearch.trim().toLowerCase();
    if (term.isEmpty) return _sales;

    return _sales.where((item) {
      if (item is! Map<String, dynamic>) return false;
      final values = [
        item['client_nom'],
        item['client'],
        item['numero_client'],
        item['client_telephone'],
        item['numero_facture'],
        item['id'],
      ].map((value) => value?.toString().toLowerCase() ?? '');

      return values.any((value) => value.contains(term));
    }).toList();
  }

  Future<void> _load() async {
    if (AppConfig.apiBaseUrl.isEmpty) {
      setState(() {
        _error = 'API_BASE_URL non configuré';
        _sales = [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = ApiService.instance.createClient();
      final session = AuthService.instance.session;
      final agentId = session?.agent?.id;

      final query = <String>[
        'date_debut=${DateFormat('yyyy-MM-dd').format(_dateDebut)}',
        'date_fin=${DateFormat('yyyy-MM-dd').format(_dateFin)}',
      ];

      if (agentId != null && agentId.isNotEmpty) {
        query.add('agent_id=$agentId');
      }

      final data = await client.getJson(
        '/api/mobile/ventes-par-agent?${query.join('&')}',
      );

      final list = data is List
          ? data
          : (data is Map<String, dynamic> && data['data'] is List
                ? data['data'] as List
                : null);

      if (!mounted) return;
      setState(() {
        _sales = list ?? const [];
        _expandedSales.clear();
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _sales = [];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _sales = [];
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _selectDateDebut() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateDebut,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _dateDebut) {
      setState(() {
        _dateDebut = picked;
      });
      await _load();
    }
  }

  Future<void> _selectDateFin() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateFin,
      firstDate: _dateDebut,
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _dateFin) {
      setState(() {
        _dateFin = picked;
      });
      await _load();
    }
  }

  Future<void> _printHistory() async {
    final pdf = pw.Document();
    final printableSales = _filteredSales;

    final session = AuthService.instance.session;
    final agentName = session?.agent?.fullName ?? 'Agent';

    final totalCaisses = printableSales.fold<double>(0, (sum, item) {
      if (item is Map<String, dynamic>) {
        final raw = item['caisses_vendues'];
        return sum +
            (raw is num
                ? raw.toDouble()
                : double.tryParse(raw?.toString() ?? '') ?? 0);
      }
      return sum;
    });

    final totalTtc = printableSales.fold<double>(0, (sum, item) {
      if (item is Map<String, dynamic>) {
        final raw = item['total_ttc'];
        return sum +
            (raw is num
                ? raw.toDouble()
                : double.tryParse(raw?.toString() ?? '') ?? 0);
      }
      return sum;
    });

    // Build per-sale blocks with details
    final saleBlocks = <pw.Widget>[];
    for (final item in printableSales) {
      if (item is! Map<String, dynamic>) continue;

      final dateStr = DateFormat('dd/MM/yyyy').format(
        DateTime.tryParse(
              (item['date_vente'] ?? '').toString().replaceFirst(' ', 'T'),
            ) ??
            DateTime.now(),
      );
      final client = (item['client_nom'] ?? 'Client').toString();
      final facture = (item['numero_facture'] ?? item['id'] ?? 'Vente')
          .toString();
      final caisses = (item['caisses_vendues'] ?? 0).toString();
      final ttc = (item['total_ttc'] ?? 0).toString();
      final details = item['details'];

      saleBlocks.add(
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 6),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(width: 0.5, color: PdfColors.grey400),
            ),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Sale header row
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      '$facture - $client',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  pw.Text(
                    dateStr,
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              // Product details table
              if (details is List && details.isNotEmpty) ...[
                pw.SizedBox(height: 3),
                pw.Table(
                  border: pw.TableBorder.all(
                    color: PdfColors.grey300,
                    width: 0.5,
                  ),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(3.5),
                    1: const pw.FixedColumnWidth(60),
                    2: const pw.FixedColumnWidth(65),
                    3: const pw.FixedColumnWidth(60),
                    4: const pw.FixedColumnWidth(75),
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.grey200,
                      ),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(
                            'Produit',
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(
                            'Caisses',
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(
                            'Bouteilles',
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(
                            'Cs vides',
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(
                            'Sous-total',
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    ...details.map((d) {
                      if (d is! Map<String, dynamic>) {
                        return pw.TableRow(
                          children: List.filled(
                            5,
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(5),
                              child: pw.Text(
                                '',
                                style: pw.TextStyle(
                                  fontSize: 12,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                      return pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text(
                              (d['produit_nom'] ?? '').toString(),
                              style: pw.TextStyle(
                                fontSize: 12,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text(
                              '${d['quantite_caisses'] ?? 0}',
                              style: pw.TextStyle(
                                fontSize: 12,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text(
                              '${d['quantite'] ?? 0}',
                              style: pw.TextStyle(
                                fontSize: 12,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text(
                              '${d['caisses_vides_recues'] ?? 0}',
                              style: pw.TextStyle(
                                fontSize: 12,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text(
                              '${d['sous_total'] ?? 0}',
                              style: pw.TextStyle(
                                fontSize: 12,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ],
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Caisses: $caisses',
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey800,
                    ),
                  ),
                  pw.Text(
                    'Total TTC: $ttc',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        header: (pw.Context context) {
          if (context.pageNumber == 1) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Historique des Ventes',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Agent: $agentName',
                  style: pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'Du ${DateFormat('dd/MM/yyyy').format(_dateDebut)} au ${DateFormat('dd/MM/yyyy').format(_dateFin)}',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),
              ],
            );
          }
          return pw.Column(
            children: [
              pw.Text(
                'Historique des Ventes - $agentName',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
              ),
              pw.SizedBox(height: 4),
            ],
          );
        },
        footer: (pw.Context context) {
          return pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Page ${context.pageNumber}/${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
              ),
            ],
          );
        },
        build: (pw.Context context) {
          return [
            ...saleBlocks,
            pw.SizedBox(height: 10),
            pw.Divider(),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Total Caisses:',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                pw.Text(
                  totalCaisses.toStringAsFixed(1),
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Total TTC:',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                pw.Text(
                  totalTtc.toStringAsFixed(2),
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
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
            ristourneTaux: double.tryParse(
              payload?['ristourneInfo'] is Map<String, dynamic>
                  ? (payload?['ristourneInfo']
                                as Map<String, dynamic>)['taux_applique']
                            ?.toString() ??
                        ''
                  : '',
            ),
            ristourneMontant: double.tryParse(
              payload?['ristourneInfo'] is Map<String, dynamic>
                  ? (payload?['ristourneInfo']
                                as Map<String, dynamic>)['montant_ristourne']
                            ?.toString() ??
                        ''
                  : '',
            ),
            deductionLocale: double.tryParse(
              payload?['ristourneInfo'] is Map<String, dynamic>
                  ? (payload?['ristourneInfo']
                                as Map<String, dynamic>)['deduction_locale']
                            ?.toString() ??
                        ''
                  : '',
            ),
            tauxLocal: payload?['ristourneInfo'] is Map<String, dynamic>
                ? int.tryParse(
                    (payload?['ristourneInfo']
                                as Map<String, dynamic>)['taux_local']
                            ?.toString() ??
                        '',
                  )
                : null,
            montantRistourneNet: double.tryParse(
              payload?['ristourneInfo'] is Map<String, dynamic>
                  ? (payload?['ristourneInfo']
                                as Map<
                                  String,
                                  dynamic
                                >)['montant_ristourne_net']
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _clientSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visibleSales = _filteredSales;

    final totalCaisses = visibleSales.fold<double>(0, (sum, item) {
      if (item is Map<String, dynamic>) {
        final raw = item['caisses_vendues'];
        return sum +
            (raw is num
                ? raw.toDouble()
                : double.tryParse(raw?.toString() ?? '') ?? 0);
      }
      return sum;
    });

    final totalTtc = visibleSales.fold<double>(0, (sum, item) {
      if (item is Map<String, dynamic>) {
        final raw = item['total_ttc'];
        return sum +
            (raw is num
                ? raw.toDouble()
                : double.tryParse(raw?.toString() ?? '') ?? 0);
      }
      return sum;
    });

    final content = RefreshIndicator(
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
                        Icons.history_rounded,
                        color: scheme.onPrimary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Historique des ventes',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Filtrez par date ou recherchez directement un client.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: visibleSales.isEmpty ? null : _printHistory,
                      icon: const Icon(Icons.print_rounded),
                      tooltip: 'Imprimer',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _clientSearchController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: 'Rechercher un client',
                    hintText: 'Nom, téléphone, numéro client ou facture',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _clientSearch.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              setState(() {
                                _clientSearch = '';
                                _clientSearchController.clear();
                              });
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _clientSearch = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _selectDateDebut,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Date début',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                DateFormat('dd/MM/yyyy').format(_dateDebut),
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: _selectDateFin,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Date fin',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                DateFormat('dd/MM/yyyy').format(_dateFin),
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
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
                style: TextStyle(
                  color: scheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (_error == null && visibleSales.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Aucune vente à afficher pour cette période ou ce client.',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const SizedBox(height: 8),
          if (visibleSales.isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: _summaryTile(
                    label: 'Ventes',
                    value: visibleSales.length.toString(),
                    icon: Icons.receipt_long,
                    scheme: scheme,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _summaryTile(
                    label: 'Caisses',
                    value: totalCaisses.toStringAsFixed(1),
                    icon: Icons.inventory_2,
                    scheme: scheme,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _summaryTile(
              label: 'Total TTC',
              value: totalTtc.toStringAsFixed(2),
              icon: Icons.attach_money,
              scheme: scheme,
            ),
            const SizedBox(height: 12),
          ],
          for (final item in visibleSales)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _saleCard(item, scheme),
            ),
        ],
      ),
    );

    if (!widget.embedInScaffold) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique des ventes'),
        actions: [
          IconButton(
            onPressed: visibleSales.isEmpty ? null : _printHistory,
            icon: const Icon(Icons.print),
            tooltip: 'Imprimer l\'historique',
          ),
        ],
      ),
      body: content,
    );
  }

  Widget _saleCard(dynamic item, ColorScheme scheme) {
    return Container(
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
                  InkWell(
                    onTap: () {
                      setState(() {
                        final venteId = item['id'] as int? ?? 0;
                        if (_expandedSales.contains(venteId)) {
                          _expandedSales.remove(venteId);
                        } else {
                          _expandedSales.add(venteId);
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (item['numero_facture'] ??
                                            item['id'] ??
                                            'Vente')
                                        .toString(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 17,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    (item['client_nom'] ?? 'Client').toString(),
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Caisses: ${(item['caisses_vendues'] ?? 0).toString()} · ${(item['total_ttc'] ?? 0).toString()}',
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              _expandedSales.contains(item['id'] as int? ?? 0)
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              color: scheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                DateFormat('dd/MM/yyyy').format(
                                  DateTime.tryParse(
                                        (item['date_vente'] ?? '')
                                            .toString()
                                            .replaceFirst(' ', 'T'),
                                      ) ??
                                      DateTime.now(),
                                ),
                                style: TextStyle(
                                  color: scheme.onSecondaryContainer,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  (item['total_ttc'] ?? 0).toString(),
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(width: 8),
                                IconButton.filledTonal(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _openInvoice(item),
                                  icon: const Icon(Icons.print_rounded),
                                  tooltip: 'Imprimer la facture',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_expandedSales.contains(item['id'] as int? ?? 0)) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    Text(
                      'Détails produits',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ..._buildDetailRows(item, scheme),
                  ],
                ],
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  List<Widget> _buildDetailRows(Map<String, dynamic> item, ColorScheme scheme) {
    final details = item['details'];
    if (details is! List || details.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            'Aucun détail disponible',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
        ),
      ];
    }

    return details.map<Widget>((d) {
      if (d is! Map<String, dynamic>) return const SizedBox.shrink();
      final produitNom = (d['produit_nom'] ?? 'Produit').toString();
      final caisses = d['quantite_caisses'] ?? 0;
      final bouteilles = d['quantite'] ?? 0;
      final caissesVidesRecues = d['caisses_vides_recues'] ?? 0;
      final prixUnitaire = d['prix_unitaire'] ?? 0;
      final prixCaisse = d['prix_caisse'] ?? 0;
      final sousTotal = d['sous_total'] ?? 0;

      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withOpacity(0.4),
          borderRadius: BorderRadius.circular(12),
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
                    color: scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.local_drink,
                    size: 16,
                    color: scheme.onTertiaryContainer,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    produitNom,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                Text(
                  '$sousTotal',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _detailChip('Caisses', '$caisses', scheme),
                _detailChip('Bouteilles', '$bouteilles', scheme),
                if (caissesVidesRecues > 0)
                  _detailChip('Cs vides reçues', '$caissesVidesRecues', scheme),
                _detailChip('Prix/cs', '$prixCaisse', scheme),
                _detailChip('Prix/ut', '$prixUnitaire', scheme),
              ],
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _detailChip(String label, String value, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
      ),
    );
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
}
