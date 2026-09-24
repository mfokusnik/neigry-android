import 'package:flutter_test/flutter_test.dart';
import 'package:neigry/src/live_helpers.dart';
import 'package:neigry/src/timing.dart';

Map<String, dynamic> _season({
  Map<String, dynamic>? results,
  Map<String, dynamic>? finalData,
  String status = 'active',
  String finalMode = 'timed',
}) {
  return <String, dynamic>{
    'status': status,
    'teams': [
      {'id': 'a', 'name': 'А'},
      {'id': 'b', 'name': 'Б'},
    ],
    'gameOrder': ['game-01', 'game-02', 'game-03'],
    'results': results ?? <String, dynamic>{},
    'final': finalData,
    'finalSetup': {'mode': finalMode, 'headstartPerPoint': 5},
  };
}

Map<String, dynamic> _success(String teamId, int elapsedMs) => {
      'teamId': teamId,
      'status': 'success',
      'elapsedMs': elapsedMs,
    };

void main() {
  test('qualifiers require both teams on every non-final game', () {
    final partial = _season(results: {
      'game-01': {
        'a': _success('a', 10000),
        'b': _success('b', 12000),
      },
      'game-02': {
        'a': _success('a', 9000),
      },
    });
    expect(qualifiersComplete(partial), isFalse);

    final complete = _season(results: {
      'game-01': {
        'a': _success('a', 10000),
        'b': _success('b', 12000),
      },
      'game-02': {
        'a': _success('a', 9000),
        'b': _success('b', 15000),
      },
    });
    expect(qualifiersComplete(complete), isTrue);
  });

  test('pending done blocks only the run it belongs to', () {
    final pending = {
      'eventId': 'evt-1',
      'runStartedAt': 100000,
      'occurredAt': 120000,
    };
    expect(pendingDoneBlocksRun(pending, 100000), isTrue);
    expect(pendingDoneBlocksRun(pending, 200000), isFalse);
    expect(pendingDoneBlocksRun(null, 100000), isFalse);
  });

  test('headstart delays only the non-leader team', () {
    final season = _season(
      finalMode: 'headstart',
      results: {
        'game-01': {
          'a': _success('a', 9000),
          'b': _success('b', 12000),
        },
        'game-02': {
          'a': _success('a', 10000),
          'b': {'teamId': 'b', 'status': 'timeout', 'elapsedMs': gameDurationMs},
        },
      },
    );
    final state = {
      'runStartedAt': 500000,
      'finalLeaderTeamId': 'a',
      'finalAdvantageMs': 10000,
      'season': season,
    };
    expect(finalTeamStartAt(state, 'a'), 500000 + finalStartOffsetMs);
    expect(finalTeamStartAt(state, 'b'), 500000 + finalStartOffsetMs + 10000);
  });

  test('score excludes dedicated final game', () {
    final season = _season(results: {
      'game-01': {
        'a': _success('a', 9000),
        'b': _success('b', 12000),
      },
      'game-02': {
        'a': {'teamId': 'a', 'status': 'timeout', 'elapsedMs': gameDurationMs},
        'b': _success('b', 11000),
      },
    });
    expect(scoreFor(season, 'a'), 1);
    expect(scoreFor(season, 'b'), 1);
  });
}
