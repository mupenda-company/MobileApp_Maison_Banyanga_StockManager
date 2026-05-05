import 'package:flutter/material.dart';

class AppThemeController extends ChangeNotifier {
  static final AppThemeController instance = AppThemeController._();

  AppThemeController._();

  Color _primaryColor = const Color(0xFF3B82F6);
  String _companyName = 'Bralima Logistique';
  String? _companyLogo;

  Color get primaryColor => _primaryColor;
  String get companyName => _companyName;
  String? get companyLogo => _companyLogo;

  void updateFromSettings(Map<String, dynamic>? settings) {
    if (settings == null) return;

    final colorValue = settings['couleur_primaire']?.toString();
    final parsedColor = parseHexColor(colorValue);

    final name = settings['nom_entreprise']?.toString();
    final logo = settings['logo']?.toString();

    bool changed = false;

    if (parsedColor != null && parsedColor.value != _primaryColor.value) {
      _primaryColor = parsedColor;
      changed = true;
    }

    if (name != null && name.trim().isNotEmpty && name.trim() != _companyName) {
      _companyName = name.trim();
      changed = true;
    }

    final normalizedLogo = (logo == null || logo.trim().isEmpty)
        ? null
        : logo.trim();
    if (normalizedLogo != _companyLogo) {
      _companyLogo = normalizedLogo;
      changed = true;
    }

    if (changed) {
      notifyListeners();
    }
  }

  ThemeData get theme {
    final scheme = ColorScheme.fromSeed(
      seedColor: _primaryColor,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: MaterialStateProperty.resolveWith((states) {
          final isSelected = states.contains(MaterialState.selected);
          return TextStyle(
            color: isSelected
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
      ),
    );
  }

  static Color? parseHexColor(String? hex) {
    if (hex == null) return null;
    var value = hex.trim();
    if (value.isEmpty) return null;

    if (value.startsWith('#')) {
      value = value.substring(1);
    }

    if (value.length == 3) {
      value = value.split('').map((c) => '$c$c').join();
    }

    if (value.length == 6) {
      value = 'FF$value';
    }

    if (value.length != 8) return null;

    final parsed = int.tryParse(value, radix: 16);
    if (parsed == null) return null;

    return Color(parsed);
  }
}
