import 'package:flutter/material.dart';
import 'package:logis_agent/api/api_client.dart';
import 'package:logis_agent/config/app_config.dart';
import 'package:logis_agent/services/api_service.dart';
import 'package:logis_agent/services/auth_service.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class AgentSalesHistoryPage extends StatefulWidget {
  const AgentSalesHistoryPage({super.key});

  @override
  State<AgentSalesHistoryPage> createState() => _AgentSalesHistoryPageState();
}

class _AgentSalesHistoryPageState extends State<AgentSalesHistoryPage> {
  bool _loading = false;
  String? _error;
  List<dynamic> _sales = [];
  final Set<int> _expandedSales = {};
  
  DateTime _dateDebut = DateTime.now();
  DateTime _dateFin = DateTime.now();

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

      final data = await client.getJson('/api/mobile/ventes-par-agent?${query.join('&')}');

      final list = data is List
          ? data
          : (data is Map<String, dynamic> && data['data'] is List ? data['data'] as List : null);

      setState(() {
        _sales = list ?? const [];
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _sales = [];
      });
    } catch (e) {
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
    
    final session = AuthService.instance.session;
    final agentName = session?.agent?.fullName ?? 'Agent';
    
    final totalCaisses = _sales.fold<double>(0, (sum, item) {
      if (item is Map<String, dynamic>) {
        final raw = item['caisses_vendues'];
        return sum + (raw is num ? raw.toDouble() : double.tryParse(raw?.toString() ?? '') ?? 0);
      }
      return sum;
    });

    final totalTtc = _sales.fold<double>(0, (sum, item) {
      if (item is Map<String, dynamic>) {
        final raw = item['total_ttc'];
        return sum + (raw is num ? raw.toDouble() : double.tryParse(raw?.toString() ?? '') ?? 0);
      }
      return sum;
    });

    // Build per-sale blocks with details
    final saleBlocks = <pw.Widget>[];
    for (final item in _sales) {
      if (item is! Map<String, dynamic>) continue;

      final dateStr = DateFormat('dd/MM/yyyy').format(
        DateTime.tryParse((item['date_vente'] ?? '').toString().replaceFirst(' ', 'T')) ?? DateTime.now(),
      );
      final client = (item['client_nom'] ?? 'Client').toString();
      final facture = (item['numero_facture'] ?? item['id'] ?? 'Vente').toString();
      final caisses = (item['caisses_vendues'] ?? 0).toString();
      final ttc = (item['total_ttc'] ?? 0).toString();
      final details = item['details'];

      saleBlocks.add(
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 6),
          decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(width: 0.5, color: PdfColors.grey400)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Sale header row
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Text('$facture - $client', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
                  ),
                  pw.Text(dateStr, style: const pw.TextStyle(fontSize: 11)),
                ],
              ),
              // Product details table
              if (details is List && details.isNotEmpty) ...[
                pw.SizedBox(height: 3),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(3.5),
                    1: const pw.FixedColumnWidth(60),
                    2: const pw.FixedColumnWidth(65),
                    3: const pw.FixedColumnWidth(60),
                    4: const pw.FixedColumnWidth(75),
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Produit', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Caisses', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Bouteilles', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Cs vides', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Sous-total', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
                      ],
                    ),
                    ...details.map((d) {
                      if (d is! Map<String, dynamic>) {
                        return pw.TableRow(children: List.filled(5, pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('', style: const pw.TextStyle(fontSize: 10)))));
                      }
                      return pw.TableRow(
                        children: [
                          pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text((d['produit_nom'] ?? '').toString(), style: const pw.TextStyle(fontSize: 10))),
                          pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${d['quantite_caisses'] ?? 0}', style: const pw.TextStyle(fontSize: 10))),
                          pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${d['quantite'] ?? 0}', style: const pw.TextStyle(fontSize: 10))),
                          pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${d['caisses_vides_recues'] ?? 0}', style: const pw.TextStyle(fontSize: 10))),
                          pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${d['sous_total'] ?? 0}', style: const pw.TextStyle(fontSize: 10))),
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
                  pw.Text('Caisses: $caisses', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                  pw.Text('Total TTC: $ttc', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
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
                  style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 6),
                pw.Text('Agent: $agentName', style: const pw.TextStyle(fontSize: 13)),
                pw.Text(
                  'Du ${DateFormat('dd/MM/yyyy').format(_dateDebut)} au ${DateFormat('dd/MM/yyyy').format(_dateFin)}',
                  style: const pw.TextStyle(fontSize: 11),
                ),
                pw.SizedBox(height: 10),
              ],
            );
          }
          return pw.Column(
            children: [
              pw.Text('Historique des Ventes - $agentName', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
              pw.SizedBox(height: 4),
            ],
          );
        },
        footer: (pw.Context context) {
          return pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Page ${context.pageNumber}/${context.pagesCount}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
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
                pw.Text('Total Caisses:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
                pw.Text(totalCaisses.toStringAsFixed(1), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Total TTC:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
                pw.Text(totalTtc.toStringAsFixed(2), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final totalCaisses = _sales.fold<double>(0, (sum, item) {
      if (item is Map<String, dynamic>) {
        final raw = item['caisses_vendues'];
        return sum + (raw is num ? raw.toDouble() : double.tryParse(raw?.toString() ?? '') ?? 0);
      }
      return sum;
    });

    final totalTtc = _sales.fold<double>(0, (sum, item) {
      if (item is Map<String, dynamic>) {
        final raw = item['total_ttc'];
        return sum + (raw is num ? raw.toDouble() : double.tryParse(raw?.toString() ?? '') ?? 0);
      }
      return sum;
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique des ventes'),
        actions: [
          IconButton(
            onPressed: _sales.isEmpty ? null : _printHistory,
            icon: const Icon(Icons.print),
            tooltip: 'Imprimer l\'historique',
          ),
        ],
      ),
      body: RefreshIndicator(
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
                        child: Icon(Icons.history_rounded, color: scheme.onPrimary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Filtrer par date',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Sélectionnez la période pour afficher les ventes.',
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
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  DateFormat('dd/MM/yyyy').format(_dateDebut),
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  DateFormat('dd/MM/yyyy').format(_dateFin),
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
                  style: TextStyle(color: scheme.error),
                ),
              ),
            if (_error == null && _sales.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Aucune vente à afficher pour cette période.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            const SizedBox(height: 8),
            if (_sales.isNotEmpty) ...[
              Row(
                children: [
                  Expanded(
                    child: _summaryTile(
                      label: 'Ventes',
                      value: _sales.length.toString(),
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
              Expanded(
                child: _summaryTile(
                  label: 'Total TTC',
                  value: totalTtc.toStringAsFixed(2),
                  icon: Icons.attach_money,
                  scheme: scheme,
                ),
              ),
              const SizedBox(height: 12),
            ],
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
                                          child: Icon(Icons.receipt_long, color: scheme.onPrimaryContainer),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                (item['numero_facture'] ?? item['id'] ?? 'Vente').toString(),
                                                style: const TextStyle(fontWeight: FontWeight.w700),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                (item['client_nom'] ?? 'Client').toString(),
                                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Caisses: ${(item['caisses_vendues'] ?? 0).toString()} · ${(item['total_ttc'] ?? 0).toString()}',
                                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
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
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: scheme.secondaryContainer,
                                            borderRadius: BorderRadius.circular(14),
                                          ),
                                          child: Text(
                                            DateFormat('dd/MM/yyyy').format(
                                              DateTime.tryParse((item['date_vente'] ?? '').toString().replaceFirst(' ', 'T')) ?? DateTime.now(),
                                            ),
                                            style: TextStyle(
                                              color: scheme.onSecondaryContainer,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          (item['total_ttc'] ?? 0).toString(),
                                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
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
                                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                ..._buildDetailRows(item, scheme),
                              ],
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
          ],
        ),
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
                  child: Icon(Icons.local_drink, size: 16, color: scheme.onTertiaryContainer),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    produitNom,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
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
}
