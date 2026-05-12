import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:logis_agent/config/app_config.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class SaleInvoiceLine {
  final String produitNom;
  final double caisses;
  final double caissesVidesRecues;
  final double detteCaisses;
  final double prixCaisse;
  final double sousTotal;

  const SaleInvoiceLine({
    required this.produitNom,
    required this.caisses,
    required this.caissesVidesRecues,
    required this.detteCaisses,
    required this.prixCaisse,
    required this.sousTotal,
  });
}

class SaleInvoicePage extends StatefulWidget {
  final String? numeroFacture;
  final int venteId;
  final DateTime date;
  final String clientNom;
  final String? clientTelephone;
  final String? clientNumero;
  final String? zoneNom;
  final String devise;

  final String? companyName;
  final String? companyAddress;
  final String? companyTelephone;
  final String? companyLogo;
  final String? companyEmail;
  final String? companyContact;
  final String? companyRccm;
  final String? companyIdNat;
  final String? companyNif;
  final String? companyAccount;

  final double? produitsCumules;
  final double? caPeriode;
  final double? ristourneTaux;
  final double? ristourneMontant;
  final bool ristourneInfoPresent;

  final String? vendeurNom;

  final double totalHt;
  final double totalTva;
  final double totalTtc;

  final List<SaleInvoiceLine> lignes;
  final bool autoPrint;

  const SaleInvoicePage({
    super.key,
    required this.venteId,
    required this.date,
    required this.clientNom,
    this.clientTelephone,
    this.clientNumero,
    this.zoneNom,
    required this.devise,
    this.companyName,
    this.companyAddress,
    this.companyTelephone,
    this.companyLogo,
    this.companyEmail,
    this.companyContact,
    this.companyRccm,
    this.companyIdNat,
    this.companyNif,
    this.companyAccount,
    this.produitsCumules,
    this.caPeriode,
    this.ristourneTaux,
    this.ristourneMontant,
    this.ristourneInfoPresent = false,
    this.vendeurNom,
    required this.totalHt,
    required this.totalTva,
    required this.totalTtc,
    required this.lignes,
    this.numeroFacture,
    this.autoPrint = true,
  });

  @override
  State<SaleInvoicePage> createState() => _SaleInvoicePageState();
}

class _SaleInvoicePageState extends State<SaleInvoicePage> {
  bool _autoPrintDone = false;

  String? _resolveLogoUrl(String? logo) {
    final l = logo?.trim();
    if (l == null || l.isEmpty) return null;
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

  Future<pw.ImageProvider?> _loadLogoImage(String? logoUrl) async {
    if (logoUrl == null || logoUrl.trim().isEmpty) return null;

    try {
      return await networkImage(logoUrl);
    } catch (_) {
      return null;
    }
  }

  String _fmtAmount(double value) {
    final v = value.isNaN || value.isInfinite ? 0 : value;
    return '${v.toStringAsFixed(2)} ${widget.devise}';
  }

  Future<Uint8List> _buildPdf(PdfPageFormat format) async {
    final doc = pw.Document();

    final title = widget.numeroFacture == null || widget.numeroFacture!.isEmpty
        ? 'FACTURE: ${widget.venteId}'
        : 'FACTURE: ${widget.numeroFacture}';

    final logoImage = widget.companyLogo != null && widget.companyLogo!.trim().isNotEmpty
        ? await _loadLogoImage(_resolveLogoUrl(widget.companyLogo))
        : null;

    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(10),
        build: (context) {
          final company = (widget.companyName == null || widget.companyName!.trim().isEmpty)
              ? 'Bralima Logistique'
              : widget.companyName!.trim();

          final adresse = widget.companyAddress?.trim();
          final telSociete = widget.companyTelephone?.trim();
          final email = widget.companyEmail?.trim();
          final contact = widget.companyContact?.trim();
          final rccm = widget.companyRccm?.trim();
          final idNat = widget.companyIdNat?.trim();
          final nif = widget.companyNif?.trim();
          final compte = widget.companyAccount?.trim();

          final clientTel = widget.clientTelephone?.trim();
          final clientNumero = widget.clientNumero?.trim();
          final zone = widget.zoneNom?.trim();
          final totalCaisses = widget.lignes.fold<double>(0, (sum, line) => sum + line.caisses);
          final totalEmballagesRecus = widget.lignes.fold<double>(0, (sum, line) => sum + line.caissesVidesRecues);
          final totalDetteEmballages = widget.lignes.fold<double>(0, (sum, line) => sum + line.detteCaisses);

          final hasRistourne = (widget.ristourneMontant != null && widget.ristourneMontant!.abs() > 0) ||
              (widget.ristourneTaux != null && widget.ristourneTaux!.abs() > 0);

          return pw.DefaultTextStyle(
            style: const pw.TextStyle(fontSize: 12),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Center(
                  child: pw.Column(
                    children: [
                      if (logoImage != null)
                        pw.Container(
                          width: 58,
                          height: 58,
                          margin: const pw.EdgeInsets.only(bottom: 6),
                          child: pw.ClipRRect(
                            horizontalRadius: 8,
                            verticalRadius: 8,
                            child: pw.Image(logoImage, fit: pw.BoxFit.cover),
                          ),
                        ),
                      pw.Text(company.toUpperCase(), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                      if (adresse != null && adresse.isNotEmpty) pw.Text(adresse, style: const pw.TextStyle(fontSize: 10)),
                      if (telSociete != null && telSociete.isNotEmpty) pw.Text('Tél: $telSociete', style: const pw.TextStyle(fontSize: 10)),
                      if (email != null && email.isNotEmpty) pw.Text('Email: $email', style: const pw.TextStyle(fontSize: 10)),
                      if (contact != null && contact.isNotEmpty) pw.Text('Contact: $contact', style: const pw.TextStyle(fontSize: 10)),
                      if (rccm != null && rccm.isNotEmpty) pw.Text('RCCM: $rccm', style: const pw.TextStyle(fontSize: 10)),
                      if (idNat != null && idNat.isNotEmpty) pw.Text('ID NAT: $idNat', style: const pw.TextStyle(fontSize: 10)),
                      if (nif != null && nif.isNotEmpty) pw.Text('NIF: $nif', style: const pw.TextStyle(fontSize: 10)),
                      if (compte != null && compte.isNotEmpty) pw.Text('Compte: $compte', style: const pw.TextStyle(fontSize: 10)),
                      pw.SizedBox(height: 6),
                      pw.Divider(thickness: 1),
                      pw.SizedBox(height: 4),
                      pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        '${widget.date.day.toString().padLeft(2, '0')}/${widget.date.month.toString().padLeft(2, '0')}/${widget.date.year} ${widget.date.hour.toString().padLeft(2, '0')}:${widget.date.minute.toString().padLeft(2, '0')}',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text('Client: ${widget.clientNom}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
                if (clientTel != null && clientTel.isNotEmpty) pw.Text('Téléphone: $clientTel', style: const pw.TextStyle(fontSize: 11)),
                if (zone != null && zone.isNotEmpty) pw.Text('Zone: $zone', style: const pw.TextStyle(fontSize: 11)),
                if (clientNumero != null && clientNumero.isNotEmpty) pw.Text('N° client: $clientNumero', style: const pw.TextStyle(fontSize: 11)),
                if (widget.produitsCumules != null && widget.produitsCumules! > 0)
                  pw.Text(
                    widget.ristourneInfoPresent
                        ? 'Produits cumulés (période): ${widget.produitsCumules!.toStringAsFixed(1)} cs'
                        : 'Produits cumulés: ${widget.produitsCumules!.toStringAsFixed(1)} cs',
                    style: const pw.TextStyle(fontSize: 11),
                  ),
                if (widget.caPeriode != null && widget.caPeriode! > 0) pw.Text('CA (période): ${_fmtAmount(widget.caPeriode!)}', style: const pw.TextStyle(fontSize: 11)),
                if (hasRistourne)
                  pw.Text(
                    'Ristourne: ${(widget.ristourneTaux ?? 0).toStringAsFixed(2)}% (${_fmtAmount(widget.ristourneMontant ?? 0)})',
                    style: const pw.TextStyle(fontSize: 11),
                  ),
                pw.SizedBox(height: 6),
                pw.Divider(thickness: 1),
                pw.SizedBox(height: 6),
                ...widget.lignes.map(
                  (l) => pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 6),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(l.produitNom, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                        pw.SizedBox(height: 2),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('${l.caisses.toStringAsFixed(1)} cs', style: const pw.TextStyle(fontSize: 11)),
                            pw.Text(_fmtAmount(l.prixCaisse), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                          ],
                        ),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('Vides: ${l.caissesVidesRecues.toStringAsFixed(1)} cs / Dette: ${l.detteCaisses.toStringAsFixed(1)} cs', style: const pw.TextStyle(fontSize: 10)),
                            pw.Text(_fmtAmount(l.sousTotal), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                pw.Divider(thickness: 1),
                pw.SizedBox(height: 6),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Total caisses achetées:', style: const pw.TextStyle(fontSize: 11)),
                    pw.Text('${totalCaisses.toStringAsFixed(1)} cs', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                  ],
                ),
                pw.SizedBox(height: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Emballages reçus:', style: const pw.TextStyle(fontSize: 11)),
                    pw.Text('${totalEmballagesRecus.toStringAsFixed(1)} cs', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                  ],
                ),
                pw.SizedBox(height: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Dette emballages:', style: const pw.TextStyle(fontSize: 11)),
                    pw.Text('${totalDetteEmballages.toStringAsFixed(1)} cs', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                  ],
                ),
                pw.SizedBox(height: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Total HT:', style: const pw.TextStyle(fontSize: 11)),
                    pw.Text(_fmtAmount(widget.totalHt), style: const pw.TextStyle(fontSize: 11)),
                  ],
                ),
                pw.SizedBox(height: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('TVA:', style: const pw.TextStyle(fontSize: 11)),
                    pw.Text(_fmtAmount(widget.totalTva), style: const pw.TextStyle(fontSize: 11)),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Container(
                  padding: const pw.EdgeInsets.only(top: 6),
                  decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 1))),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('TOTAL TTC:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                      pw.Text(_fmtAmount(widget.totalTtc), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Center(child: pw.Text('Merci pour votre confiance !', style: const pw.TextStyle(fontSize: 10))),
                if (widget.vendeurNom != null && widget.vendeurNom!.trim().isNotEmpty)
                  pw.Center(child: pw.Text('Vendeur: ${widget.vendeurNom!.trim()}', style: const pw.TextStyle(fontSize: 10))),
              ],
            ),
          );
        },
      ),
    );

    return doc.save();
  }

  Future<void> _print() async {
    await Printing.layoutPdf(
      onLayout: _buildPdf,
      name: widget.numeroFacture == null || widget.numeroFacture!.isEmpty ? 'facture_${widget.venteId}.pdf' : '${widget.numeroFacture}.pdf',
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_autoPrintDone || !widget.autoPrint) return;
    _autoPrintDone = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _print();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Facture'),
          actions: [
            IconButton(
              icon: const Icon(Icons.print),
              onPressed: _print,
            ),
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: () {
                Navigator.pop(context, true);
              },
            ),
          ],
        ),
        body: PdfPreview(
          canChangePageFormat: false,
          initialPageFormat: PdfPageFormat.a5,
          build: _buildPdf,
        ),
      ),
    );
  }
}
