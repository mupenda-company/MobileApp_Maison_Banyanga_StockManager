import 'package:flutter/material.dart';
import 'package:logis_agent/config/app_config.dart';
import 'package:logis_agent/pages/clients_page.dart';
import 'package:logis_agent/pages/dashboard_page.dart';
import 'package:logis_agent/pages/login.dart';
import 'package:logis_agent/pages/sales_page.dart';
import 'package:logis_agent/pages/stocks_page.dart';
import 'package:logis_agent/services/auth_service.dart';
import 'package:logis_agent/theme/app_theme_controller.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int _index = 0;

  bool get _isRistourne {
    final session = AuthService.instance.session;
    return (session?.mission?['type_mission'] ?? 'vente').toString() == 'ristourne';
  }

  final _pages = const [
    DashboardPage(),
    SalesPage(),
    StocksPage(),
    ClientsPage(),
  ];

  String get _title {
    switch (_index) {
      case 0:
        return 'Accueil';
      case 1:
        return _isRistourne ? 'Ristournes' : 'Ventes';
      case 2:
        return 'Stocks';
      case 3:
        return 'Clients';
      default:
        return 'Accueil';
    }
  }

  Future<void> _logout() async {
    await AuthService.instance.logout();
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const Login()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              if (AppThemeController.instance.companyLogo != null)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Image.network(
                    '${AppConfig.apiBaseUrl}/uploads/${AppThemeController.instance.companyLogo}',
                    height: 32,
                    width: 32,
                    errorBuilder: (_, __, ___) => const Icon(Icons.storefront, size: 32),
                  ),
                ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppThemeController.instance.companyName,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    _title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          toolbarHeight: 72,
          elevation: 0,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: IconButton.filledTonal(
                onPressed: _logout,
                icon: const Icon(Icons.logout_rounded),
                tooltip: 'Déconnexion',
              ),
            ),
          ],
        ),
        body: IndexedStack(
          index: _index,
          children: _pages,
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) {
            setState(() {
              _index = value;
            });
          },
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Accueil',
            ),
            NavigationDestination(
              icon: _isRistourne ? const Icon(Icons.card_giftcard_outlined) : const Icon(Icons.point_of_sale_outlined),
              selectedIcon: _isRistourne ? const Icon(Icons.card_giftcard) : const Icon(Icons.point_of_sale),
              label: _isRistourne ? 'Ristournes' : 'Ventes',
            ),
            const NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2),
              label: 'Stocks',
            ),
            const NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'Clients',
            ),
          ],
        ),
      ),
    );
  }
}