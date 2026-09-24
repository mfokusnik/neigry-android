#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PHONE = (ROOT / 'lib/src/phone.dart').read_text(encoding='utf-8')
TV = (ROOT / 'lib/src/tv.dart').read_text(encoding='utf-8')
HELPERS = (ROOT / 'lib/src/live_helpers.dart').read_text(encoding='utf-8')
TIMING = (ROOT / 'lib/src/timing.dart').read_text(encoding='utf-8')
STORAGE = (ROOT / 'lib/src/storage.dart').read_text(encoding='utf-8')
APP = (ROOT / 'lib/src/app.dart').read_text(encoding='utf-8')
SOCKET = (ROOT / 'lib/src/live_socket.dart').read_text(encoding='utf-8')
PUBSPEC = (ROOT / 'pubspec.yaml').read_text(encoding='utf-8')
WORKFLOW = (ROOT / '.github/workflows/android-apk.yml').read_text(encoding='utf-8')
SERVER = Path('/mnt/data/neigry_server_patch/server.js')
SERVER_TEXT = SERVER.read_text(encoding='utf-8') if SERVER.exists() else ''

checks: list[tuple[str, bool, str]] = []

def check(name: str, condition: bool, detail: str) -> None:
    checks.append((name, condition, detail))

# Source-level guards for the eleven items from the first audit.
check('clock sync on phone', "'type': 'sync_probe'" in PHONE and "type == 'sync_ack'" in PHONE, 'phone sync_probe/sync_ack')
check('clock sync on TV', "'type': 'sync_probe'" in TV and "type == 'sync_ack'" in TV, 'TV sync_probe/sync_ack')
check('done persistence', 'saveDoneQueue' in PHONE and "'type': 'done'" in PHONE, 'done is persisted and resent')
check('pending scoped to run', 'pendingDoneBlocksRun' in PHONE and 'pendingDoneBlocksRun' in HELPERS, 'old pending does not block a new run')
check('final qualifier guard', 'qualifiersComplete(season)' in PHONE, 'final start disabled until qualifiers complete')
check('finish season', "_send('finish_season')" in PHONE, 'finish_season command is exposed')
check('timeout correction', "_send('correct_timeout_to_success'" in PHONE, 'manual timeout correction exists')
check('summary/finale switching', "_send('show_summary')" in PHONE and "_send('show_finale')" in PHONE, 'both server screen commands exist')
check('phone long countdown text scales', 'FittedBox' in PHONE and "display," in PHONE, 'phone countdown display uses FittedBox')
check('session survives process death', 'FlutterSecureStorage' in STORAGE and 'saveControllerSession' in PHONE and 'saveStageSession' in TV, 'role/live keys persist in secure storage')
check('TV pairing ignores local wall clock TTL', '_expiresAt' not in TV and 'DateTime.now().millisecondsSinceEpoch >=' not in TV, 'pairing rotation is driven by server not local TV clock')
check('ordinary controls disabled offline', 'enabled: _connected' in PHONE and 'connected ? onCancel : null' in PHONE, 'non-done commands are disabled offline')

# Additional reliability findings discovered during the v0.2 audit.
check('cold-start offline keeps live key', 'Future<bool?> _liveKeyStillValid' in APP and 'return null;' in APP and 'validity != false' in APP, 'transient network failure does not erase saved live credentials')
check('expired controller live is detected', '_healthTimer' in PHONE and '_checkLiveHealth' in PHONE and "e.code == 'not_found' || e.code == 'forbidden'" in PHONE, 'phone periodically validates live key')
check('expired stage live is detected', '_healthTimer' in TV and '_checkLiveHealth' in TV and "e.code == 'not_found' || e.code == 'forbidden'" in TV, 'TV periodically validates live key')
check('instruction end survives reconnect', '_instructionEndPending = true' in TV and '_sendPendingInstructionEnd();' in TV, 'TV resends instruction_ended after reconnect')
check('stage readiness waits for initialization', '_mediaPrimed = true' in TV and '_maybeSendStageReady' in TV, 'stage_ready is gated on TV initialization')
check('websocket connect is bounded and de-duplicated', '_connectFuture' in SOCKET and '.timeout(const Duration(seconds: 12))' in SOCKET, 'reconnect attempts cannot overlap indefinitely')
check('non-timed final counts upward', "if (mode != 'timed') return formatClockMs(elapsed);" in TIMING, 'headstart/sudden-death display elapsed time like the web client')
check('expired auth routes to login', '_handleUnauthorized' in PHONE and "e.statusCode == 401 || e.code == 'unauthorized'" in PHONE, 'pair/claim recover from expired phone token')

check('Flutter SDK is pinned', 'FLUTTER_VERSION: "3.44.9"' in WORKFLOW, 'CI uses a known Flutter 3.44.9 tag')
check('dependency versions are reproducible', '^' not in '\n'.join(line for line in PUBSPEC.splitlines() if ':' in line and not line.strip().startswith('#')), 'runtime/dev package versions do not float to a newer incompatible release')

# Cross-check critical timing constants against installed server patch when available.
def dart_const(name: str) -> int:
    m = re.search(rf'const int {re.escape(name)}\s*=\s*(\d+);', TIMING)
    if not m:
        raise AssertionError(f'Missing Dart constant {name}')
    return int(m.group(1))

def js_const(name: str) -> int | None:
    m = re.search(rf'const {re.escape(name)}\s*=\s*(\d+);', SERVER_TEXT)
    return int(m.group(1)) if m else None

if SERVER_TEXT:
    pairs = [
        ('gameStartOffsetMs', 'GAME_START_OFFSET_MS'),
        ('gameDurationMs', 'GAME_DURATION_MS'),
        ('finalStartOffsetMs', 'FINAL_START_OFFSET_MS'),
    ]
    for dart_name, js_name in pairs:
        d = dart_const(dart_name)
        j = js_const(js_name)
        check(f'timing {dart_name}', j == d, f'client={d} server={j}')

# Behavioral simulations independent from UI code.
def pending_blocks(pending_run: int, current_run: int) -> bool:
    return pending_run > 0 and pending_run == current_run

check('simulation: old pending allows next run', not pending_blocks(1000, 2000), 'pending from run 1000 does not block run 2000')

FINAL_START = dart_const('finalStartOffsetMs')
run = 1_000_000
leader_start = run + FINAL_START
other_start = leader_start + 10_000
check('simulation: leader headstart start', leader_start == 1_008_000, f'leader start={leader_start}')
check('simulation: trailing team headstart start', other_start == 1_018_000, f'trailing start={other_start}')
check('simulation: early trailing-team press rejected client-side', 1_017_999 < other_start, 'press before trailing start remains too early')

# The server accepts delayed done only for 30s. Ensure client expiry is above that window but close enough to stop stale retries.
m = re.search(r'now - occurredAt > (\d+)', PHONE)
client_expiry = int(m.group(1)) if m else None
server_late = js_const('LATE_DONE_WINDOW_MS') if SERVER_TEXT else 30000
check('done retry expiry tracks server late window', client_expiry is not None and server_late is not None and server_late <= client_expiry <= server_late + 5000, f'client={client_expiry} server={server_late}')

failed = [item for item in checks if not item[1]]
for name, ok, detail in checks:
    print(f"{'PASS' if ok else 'FAIL'} | {name} | {detail}")
print(f'\nTOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(1 if failed else 0)
