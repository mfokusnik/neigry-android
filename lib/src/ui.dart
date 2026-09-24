import 'package:flutter/material.dart';

const Color ink = Color(0xFF070A0F);
const Color panel = Color(0xFF111821);
const Color panel2 = Color(0xFF18222D);
const Color cyan = Color(0xFF42E8FF);
const Color lime = Color(0xFFB8FF3D);
const Color danger = Color(0xFFFF5B6A);
const Color muted = Color(0xFF8D9AA8);

class NeigryLogo extends StatelessWidget {
  const NeigryLogo({super.key, this.large = false});
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Text(
      'НЕИГРЫ',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: large ? 72 : 36,
        fontWeight: FontWeight.w900,
        letterSpacing: large ? 8 : 4,
        color: Colors.white,
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.ok,
  });

  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: (ok ? lime : danger).withValues(alpha: 0.13),
        border: Border.all(color: (ok ? lime : danger).withValues(alpha: 0.55)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: ok ? lime : danger,
          fontWeight: FontWeight.w800,
          letterSpacing: .4,
        ),
      ),
    );
  }
}

class PanelCard extends StatelessWidget {
  const PanelCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }
}

ButtonStyle primaryButtonStyle({Color color = cyan}) {
  return FilledButton.styleFrom(
    backgroundColor: color,
    foregroundColor: ink,
    disabledBackgroundColor: Colors.white12,
    disabledForegroundColor: Colors.white38,
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
    textStyle: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: .6),
  );
}

String humanError(Object error) {
  final raw = error.toString();
  if (raw.contains('invalid_login')) return 'Неверный логин или пароль.';
  if (raw.contains('pairing_not_found')) return 'Код подключения не найден или уже истёк.';
  if (raw.contains('pairing_already_claimed')) return 'Этот экран уже подключён.';
  if (raw.contains('season_finished')) return 'Этот сезон уже завершён.';
  if (raw.contains('SocketException')) return 'Нет связи с сервером.';
  if (raw.contains('HandshakeException')) return 'Не удалось установить защищённое соединение.';
  return raw.replaceFirst('ApiException: ', '');
}
