// lib/src/widgets/language_toggle.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:FLEETRA/src/providers/locale_provider.dart';

const Color _card        = Color(0xFF1C2333);
const Color _border      = Color(0xFF30363D);
const Color _orange      = Color(0xFFF58220);
const Color _textMuted   = Color(0xFF8B949E);

class LanguageToggle extends StatelessWidget {
  const LanguageToggle({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LocaleProvider>();
    final isFr     = provider.isFrench;

    return GestureDetector(
      onTap: () => context.read<LocaleProvider>().toggle(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _orange.withOpacity(0.5), width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LangPill(flag: '🇫🇷', code: 'FR', active: isFr),
            const SizedBox(width: 4),
            _LangPill(flag: '🇬🇧', code: 'EN', active: !isFr),
          ],
        ),
      ),
    );
  }
}

class _LangPill extends StatelessWidget {
  final String flag;
  final String code;
  final bool   active;

  const _LangPill({
    required this.flag,
    required this.code,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color:        active ? _orange : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(flag, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 3),
          Text(
            code,
            style: TextStyle(
              fontSize:     10,
              fontWeight:   FontWeight.w700,
              color:        active ? Colors.white : _textMuted,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}