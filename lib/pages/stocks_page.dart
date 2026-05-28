import 'dart:math';

import 'package:flutter/material.dart';
import 'package:logis_agent/api/api_client.dart';
import 'package:logis_agent/config/app_config.dart';
import 'package:logis_agent/services/app_refresh_service.dart';
import 'package:logis_agent/services/api_service.dart';
import 'package:logis_agent/services/auth_service.dart';

class StocksPage extends StatefulWidget {
  const StocksPage({super.key});

  @override
  State<StocksPage> createState() => _StocksPageState();
}

class _StocksPageState extends State<StocksPage> {
  bool _loading = false;
  String? _error;
  List<dynamic> _stocks = const [];

  late final VoidCallback _refreshListener;

  Future<void> _load() async {
    if (AppConfig.apiBaseUrl.isEmpty) {
      setState(() {
        _error = 'API_BASE_URL non configuré';
        _stocks = const [];
      });
      return;
    }

    final session = AuthService.instance.session;
    final missionId = session?.mission?['id']?.toString();
    if (missionId == null || missionId.isEmpty) {
      setState(() {
        _error = 'Aucune mission en cours';
        _stocks = const [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = ApiService.instance.createClient();
      final data = await client.getJson('${AppConfig.missionPath}/$missionId/stock');

      final list = data is List
          ? data
          : (data is Map<String, dynamic> && data['data'] is List ? data['data'] as List : null);

      setState(() {
        _stocks = list ?? const [];
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _stocks = const [];
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _stocks = const [];
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

  double _stockCases(Map<String, dynamic> item) {
    final cases = (item['stock_actuel_caisses'] ?? item['stock_caisses_pleine'] ?? item['caisses_pleine'] ?? 0);
    final casesValue = cases is num ? cases.toDouble() : double.tryParse(cases.toString().replaceAll(',', '.')) ?? 0;
    if (casesValue > 0) {
      return casesValue;
    }

    final bottles = (item['stock_actuel_bouteilles'] ?? item['stock_plein'] ?? item['quantite_pleine'] ?? item['stock'] ?? 0);
    final bottlesValue = bottles is num ? bottles.toDouble() : double.tryParse(bottles.toString().replaceAll(',', '.')) ?? 0;
    final bottlesPerCase = double.tryParse((item['bouteilles_par_caisses'] ?? 24).toString().replaceAll(',', '.')) ?? 24;
    if (bottlesPerCase <= 0) {
      return bottlesValue;
    }

    return bottlesValue / bottlesPerCase;
  }

  Widget _stockCard(Map<String, dynamic> item, ColorScheme scheme, {bool isRistourne = false}) {
    final name = (item['nom'] ?? item['name'] ?? item['product'] ?? 'Produit').toString();
    final emplacement = (item['emplacement_nom'] ?? item['location'] ?? item['emplacement'] ?? 'Emplacement').toString();
    final rawQty = _stockCases(item);
    final isLow = rawQty <= 0;

    // For ristourne: calculate initial vs current stock
    final initialCaisses = isRistourne
        ? (double.tryParse('${item['quantite_caisses'] ?? 0}') ?? 0)
        : 0.0;
    final deliveredCaisses = isRistourne
        ? (double.tryParse('${item['quantite_vendue'] ?? 0}') ?? 0) /
          max(1, double.tryParse('${item['bouteilles_par_caisses'] ?? 24}') ?? 24)
        : 0.0;
    final progressPct = isRistourne && initialCaisses > 0
        ? ((initialCaisses - rawQty) / initialCaisses).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isLow ? scheme.errorContainer : scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                isLow ? Icons.inventory_2_outlined : Icons.inventory_2,
                color: isLow ? scheme.onErrorContainer : scheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isLow ? scheme.errorContainer : scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          isLow ? 'Stock bas' : 'Disponible',
                          style: TextStyle(
                            color: isLow ? scheme.onErrorContainer : scheme.onPrimaryContainer,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    emplacement,
                    style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.local_shipping_outlined, size: 16, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Text(
                        '${rawQty.toStringAsFixed(1)} cs',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  if (isRistourne && initialCaisses > 0) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: scheme.tertiaryContainer.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Stock ristourne',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.tertiary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text(
                                'Initial: ${initialCaisses.toStringAsFixed(0)} cs',
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                              Text(
                                'Livré: ${deliveredCaisses.toStringAsFixed(1)} cs',
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'Restant: ${rawQty.toStringAsFixed(1)} cs',
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: isLow ? scheme.error : scheme.tertiary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progressPct,
                              backgroundColor: scheme.outlineVariant.withOpacity(0.3),
                              color: isLow ? scheme.error : scheme.tertiary,
                              minHeight: 6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stocksCount = _stocks.length;
    final totalQuantity = _stocks.fold<double>(0, (sum, item) {
      if (item is Map<String, dynamic>) {
        return sum + _stockCases(item);
      }
      return sum;
    });
    final session = AuthService.instance.session;
    final isRistourne = (session?.mission?['type_mission'] ?? 'vente').toString() == 'ristourne';
    final missionLabel = isRistourne ? 'Stocks de la ristourne' : 'Stocks de la mission';

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
                      child: Icon(Icons.inventory_2_rounded, color: scheme.onPrimary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            missionLabel,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isRistourne
                                ? 'Suivi du stock embarqué pour les livraisons de ristourne.'
                                : 'Suivi du stock embarqué pour les ventes terrain.',
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
                        label: 'Produits',
                        value: stocksCount.toString(),
                        icon: Icons.apps,
                        scheme: scheme,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _summaryTile(
                        label: 'Caisses totales',
                        value: totalQuantity.toStringAsFixed(0),
                        icon: Icons.all_inbox,
                        scheme: scheme,
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
          if (_error == null && _stocks.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    Icon(Icons.inventory_2_outlined, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Aucun stock à afficher.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          for (final item in _stocks)
            if (item is Map<String, dynamic>) _stockCard(item, scheme, isRistourne: isRistourne),
        ],
      ),
    );
  }
}
