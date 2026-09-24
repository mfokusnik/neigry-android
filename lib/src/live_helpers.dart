import 'game_catalog.dart';
import 'timing.dart';

Map<String, dynamic> asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<Map<String, dynamic>> asMapList(dynamic value) {
  if (value is! List) return <Map<String, dynamic>>[];
  return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

String str(dynamic value, [String fallback = '']) => value?.toString() ?? fallback;

int integer(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

bool boolean(dynamic value, [bool fallback = false]) {
  if (value is bool) return value;
  return fallback;
}

Map<String, dynamic> liveState(Map<String, dynamic>? live) =>
    asMap(live?['state']);

Map<String, dynamic> liveSeason(Map<String, dynamic>? live) =>
    asMap(liveState(live)['season']);

List<Map<String, dynamic>> seasonTeams(Map<String, dynamic> season) =>
    asMapList(season['teams']);

List<String> seasonGameOrder(Map<String, dynamic> season) {
  final raw = season['gameOrder'];
  if (raw is! List) return <String>[];
  return raw.map((e) => e.toString()).where(gameById.containsKey).toList();
}

Map<String, dynamic>? teamById(Map<String, dynamic> season, String? id) {
  if (id == null) return null;
  for (final team in seasonTeams(season)) {
    if (str(team['id']) == id) return team;
  }
  return null;
}

Map<String, dynamic>? resultFor(
  Map<String, dynamic> season,
  String gameId,
  String teamId,
) {
  final results = asMap(season['results']);
  final byTeam = asMap(results[gameId]);
  final result = byTeam[teamId];
  return result is Map ? Map<String, dynamic>.from(result) : null;
}

bool isFinalGame(Map<String, dynamic> season, String? gameId) {
  final order = seasonGameOrder(season);
  return gameId != null && order.isNotEmpty && order.last == gameId;
}

List<String> qualifierGameIds(Map<String, dynamic> season) {
  final order = seasonGameOrder(season);
  if (str(season['status']) == 'finished' && season['final'] == null) return order;
  if (order.isEmpty) return order;
  return order.sublist(0, order.length - 1);
}

bool gameComplete(Map<String, dynamic> season, String gameId) {
  if (isFinalGame(season, gameId) && !(str(season['status']) == 'finished' && season['final'] == null)) {
    return str(asMap(season['final'])['winnerTeamId']).isNotEmpty;
  }
  final teams = seasonTeams(season);
  return teams.isNotEmpty && teams.every((team) => resultFor(season, gameId, str(team['id'])) != null);
}

bool qualifiersComplete(Map<String, dynamic> season) =>
    qualifierGameIds(season).every((gameId) => gameComplete(season, gameId));

bool pendingDoneBlocksRun(Map<String, dynamic>? pending, int runStartedAt) {
  if (pending == null || runStartedAt <= 0) return false;
  return integer(pending['runStartedAt']) == runStartedAt;
}

String? winnerForGame(Map<String, dynamic> season, String gameId) {
  final teams = seasonTeams(season);
  if (teams.length < 2) return null;
  final a = resultFor(season, gameId, str(teams[0]['id']));
  final b = resultFor(season, gameId, str(teams[1]['id']));
  if (a == null || b == null) return null;

  final aSuccess = str(a['status']) == 'success';
  final bSuccess = str(b['status']) == 'success';
  if (aSuccess != bSuccess) return aSuccess ? str(teams[0]['id']) : str(teams[1]['id']);
  if (!aSuccess) return null;

  final aElapsed = integer(a['elapsedMs'], gameDurationMs);
  final bElapsed = integer(b['elapsedMs'], gameDurationMs);
  if (aElapsed == bElapsed) return null;
  return aElapsed < bElapsed ? str(teams[0]['id']) : str(teams[1]['id']);
}

int scoreFor(Map<String, dynamic> season, String teamId) {
  var score = 0;
  for (final gameId in qualifierGameIds(season)) {
    if (winnerForGame(season, gameId) == teamId) score += 1;
  }
  return score;
}

String finalMode(Map<String, dynamic> season) {
  final raw = str(asMap(season['finalSetup'])['mode'], 'timed');
  return const {'headstart', 'timed', 'sudden_death'}.contains(raw) ? raw : 'timed';
}

String finalRuleLabel(Map<String, dynamic> season) {
  final teams = seasonTeams(season);
  if (teams.length < 2) return 'Финальное испытание';
  final mode = finalMode(season);
  if (mode == 'timed') return 'Одна минута · кто справился первым — победил';
  if (mode == 'sudden_death') return 'До победителя · обе команды начинают одновременно';

  final aId = str(teams[0]['id']);
  final bId = str(teams[1]['id']);
  final aScore = scoreFor(season, aId);
  final bScore = scoreFor(season, bId);
  if (aScore == bScore) return 'Фора на старте · команды начинают одновременно';
  final leader = aScore > bScore ? teams[0] : teams[1];
  final other = aScore > bScore ? teams[1] : teams[0];
  final perPoint = integer(asMap(season['finalSetup'])['headstartPerPoint'], 5).clamp(1, 30);
  final seconds = (aScore - bScore).abs() * perPoint;
  return '${str(leader['name'])} начинают первыми · ${str(other['name'])} через $seconds сек.';
}

int finalTeamStartAt(Map<String, dynamic> state, String teamId) {
  final runStartedAt = integer(state['runStartedAt']);
  final leaderId = str(state['finalLeaderTeamId']);
  final advantageMs = integer(state['finalAdvantageMs']);
  final season = asMap(state['season']);
  final extra = finalMode(season) == 'headstart' && leaderId.isNotEmpty && teamId != leaderId
      ? advantageMs
      : 0;
  return runStartedAt + finalStartOffsetMs + extra;
}

class LiveClock {
  final Stopwatch _monotonic = Stopwatch()..start();
  double _anchorPerfMs = 0;
  double _anchorServerMs = 0;
  double _lastRttMs = 0;

  double get perfNowMs => _monotonic.elapsedMicroseconds / 1000.0;

  int get nowMs {
    if (_anchorServerMs <= 0) return DateTime.now().millisecondsSinceEpoch;
    return (_anchorServerMs + (perfNowMs - _anchorPerfMs)).round();
  }

  int get lastRttMs => _lastRttMs.round();

  void updateFromLive(Map<String, dynamic> live) {
    if (_anchorServerMs > 0) return;
    final remote = integer(live['serverNow']);
    if (remote <= 0) return;
    _anchorPerfMs = perfNowMs;
    _anchorServerMs = remote.toDouble();
  }

  void updateFromSyncAck(Map<String, dynamic> message) {
    final remote = integer(message['serverNow']);
    final sentRaw = message['sentPerf'];
    final sentPerf = sentRaw is num ? sentRaw.toDouble() : double.tryParse(sentRaw?.toString() ?? '');
    if (remote <= 0 || sentPerf == null) return;
    final end = perfNowMs;
    final rtt = (end - sentPerf).clamp(0.0, 60000.0);
    _lastRttMs = rtt;
    _anchorPerfMs = end;
    _anchorServerMs = remote + rtt / 2.0;
  }
}
