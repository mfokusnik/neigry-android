const int gameStartOffsetMs = 12000;
const int gameDurationMs = 60000;
const int finalStartOffsetMs = 8000;

String regularDisplay({
  required int serverNow,
  required int runStartedAt,
}) {
  final delta = serverNow - runStartedAt;
  if (delta < 0) return 'ГОТОВЬТЕСЬ';
  if (delta < 7000) return 'ГОТОВЬТЕСЬ';
  if (delta < 8670) return '3';
  if (delta < 10330) return '2';
  if (delta < gameStartOffsetMs) return '1';
  final elapsed = delta - gameStartOffsetMs;
  final remain = gameDurationMs - elapsed;
  if (remain <= 0) return '0';
  return ((remain + 999) ~/ 1000).toString();
}

String finalDisplay({
  required int serverNow,
  required int runStartedAt,
  required String mode,
  required bool decision,
}) {
  if (decision) return 'ВРЕМЯ!';
  final delta = serverNow - runStartedAt;
  if (delta < 0) return 'ГОТОВЬТЕСЬ';
  if (delta < 5104) return 'ГОТОВЬТЕСЬ';
  if (delta < 6000) return '3';
  if (delta < 6900) return '2';
  if (delta < finalStartOffsetMs) return '1';
  final elapsed = delta - finalStartOffsetMs;
  if (mode != 'timed') return formatClockMs(elapsed);
  final remain = gameDurationMs - elapsed;
  if (remain <= 0) return '0';
  return ((remain + 999) ~/ 1000).toString();
}

String formatClockMs(int value) {
  final ms = value < 0 ? 0 : value;
  final minutes = ms ~/ 60000;
  final seconds = (ms % 60000) ~/ 1000;
  final millis = ms % 1000;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${millis.toString().padLeft(3, '0')}';
}

String formatElapsedMs(int value) {
  final ms = value < 0 ? 0 : value;
  final seconds = ms / 1000.0;
  return '${seconds.toStringAsFixed(3)} сек';
}
