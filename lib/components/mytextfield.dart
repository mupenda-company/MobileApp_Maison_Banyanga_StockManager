import 'package:flutter/material.dart';

class Mytextfield extends StatelessWidget {
  final TextEditingController controler;
  final String labelText;
  final bool obscureText;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final String hintText;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  const Mytextfield(
    {
      super.key, 
      required this.labelText,
      required this.controler,
      this.obscureText = false,
      this.keyboardType = TextInputType.text,
      this.textInputAction = TextInputAction.next,
      this.hintText = "",
      this.onSubmitted,
      this.enabled = true,
    }
  );
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: TextField(
        controller: controler,
        obscureText: obscureText,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        enabled: enabled,
        style: TextStyle(color: scheme.onSurface),
        decoration: InputDecoration(
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(
              color: scheme.outlineVariant,
              width: 1.2,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(
              color: scheme.primary,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          labelText: labelText,
          hintText: hintText,
          hintStyle: TextStyle(color: scheme.onSurfaceVariant),
          fillColor: scheme.surfaceContainerHighest,
          filled: true,
        ),
      ),
    );
  }
}
