import 'package:flutter_test/flutter_test.dart';
import 'package:neigry/src/game_catalog.dart';
import 'package:neigry/src/timing.dart';

void main() {
  test('game catalog matches current web catalog', () {
    expect(games.length, 52);
    expect(games.first.id, 'game-01');
    expect(games.last.id, 'game-52');
  });

  test('regular countdown follows soundtrack markers', () {
    const start = 100000;
    expect(regularDisplay(serverNow: start + 6999, runStartedAt: start), 'ГОТОВЬТЕСЬ');
    expect(regularDisplay(serverNow: start + 7000, runStartedAt: start), '3');
    expect(regularDisplay(serverNow: start + 8670, runStartedAt: start), '2');
    expect(regularDisplay(serverNow: start + 10330, runStartedAt: start), '1');
    expect(regularDisplay(serverNow: start + 12000, runStartedAt: start), '60');
  });

  test('final countdown starts at eight seconds', () {
    const start = 500000;
    expect(finalDisplay(serverNow: start + 5104, runStartedAt: start, mode: 'timed', decision: false), '3');
    expect(finalDisplay(serverNow: start + 6000, runStartedAt: start, mode: 'timed', decision: false), '2');
    expect(finalDisplay(serverNow: start + 6900, runStartedAt: start, mode: 'timed', decision: false), '1');
    expect(finalDisplay(serverNow: start + 8000, runStartedAt: start, mode: 'timed', decision: false), '60');
  });

  test('non-timed final counts upward after the start signal', () {
    const start = 700000;
    expect(finalDisplay(serverNow: start + 8000, runStartedAt: start, mode: 'sudden_death', decision: false), '00:00.000');
    expect(finalDisplay(serverNow: start + 20345, runStartedAt: start, mode: 'sudden_death', decision: false), '00:12.345');
  });
}
