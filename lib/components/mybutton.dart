import 'package:flutter/material.dart';

class Mybutton extends StatelessWidget {
  final Function()? onTap;
  final bool isLoading;
  final String label;
  final bool enabled;

  const Mybutton({
    super.key,
    required this.onTap,
    this.isLoading = false,
    this.label = 'Se Connecter',
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final canTap = enabled && !isLoading;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: FilledButton(
          onPressed: canTap ? onTap : null,
          style: FilledButton.styleFrom(
            backgroundColor: canTap ? scheme.primary : scheme.primary.withAlpha(140),
            foregroundColor: scheme.onPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: isLoading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(scheme.onPrimary),
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
        ),
      ),
    );
  }
}