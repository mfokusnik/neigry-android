import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'api.dart';
import 'config.dart';
import 'game_catalog.dart';
import 'live_helpers.dart';
import 'live_socket.dart';
import 'storage.dart';
import 'timing.dart';
import 'ui.dart';

class TvPairingPage extends StatefulWidget {
  const TvPairingPage({super.key, required this.api});
  final ApiClient api;

  @override
  State<TvPairingPage> createState() => _TvPairingPageState();
}

class _TvPairingPageState extends State<TvPairingPage> {
  String? _pairingId;
  String? _code;
  String? _secret;
  String? _error;
  bool _busy = false;
  Timer? _pollTimer;
  bool _handoffToStage = false;

  @override
  void initState() {
    super.initState();
    _enterTvMode();
    _createPairing();
  }

  Future<void> _enterTvMode() async {
    await WakelockPlus.enable();
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _leaveTvMode() async {
    await WakelockPlus.disable();
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> _createPairing() async {
    if (_busy) return;
    _pollTimer?.cancel();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.api.createPairing();
      if (!mounted) return;
      setState(() {
        _pairingId = str(data['pairingId']);
        _code = str(data['code']);
        _secret = str(data['secret']);
      });
      _pollTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) => _poll());
    } catch (e) {
      if (mounted) setState(() => _error = humanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _poll() async {
    final id = _pairingId;
    final secret = _secret;
    if (id == null || secret == null || id.isEmpty || secret.isEmpty) return;
    try {
      final data = await widget.api.pairingStatus(id, secret);
      if (str(data['status']) != 'paired') return;
      final live = asMap(data['live']);
      final code = str(live['code']);
      final stageKey = str(live['stageKey']);
      if (code.isEmpty || stageKey.isEmpty || !mounted) return;
      _pollTimer?.cancel();
      await SessionStore.instance.saveStageSession(code: code, key: stageKey);
      await SessionStore.instance.saveDeviceRole('tv');
      if (!mounted) return;
      _handoffToStage = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => StagePage(
            api: widget.api,
            liveCode: code,
            stageKey: stageKey,
          ),
        ),
      );
    } catch (e) {
      if (e is ApiException && e.code == 'pairing_not_found') {
        await _createPairing();
        return;
      }
      if (mounted) setState(() => _error = humanError(e));
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    if (!_handoffToStage) unawaited(_leaveTvMode());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final code = _code;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(36),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const NeigryLogo(large: true),
                  const SizedBox(height: 18),
                  const Text(
                    'ПОДКЛЮЧИТЕ ТЕЛЕФОН',
                    style: TextStyle(color: cyan, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 2),
                  ),
                  const SizedBox(height: 34),
                  if (code == null)
                    const CircularProgressIndicator()
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 46, vertical: 28),
                      decoration: BoxDecoration(
                        color: panel,
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: cyan.withValues(alpha: .5), width: 2),
                      ),
                      child: Text(
                        '${code.substring(0, 3)} ${code.substring(3)}',
                        style: const TextStyle(
                          fontSize: 86,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  const SizedBox(height: 28),
                  const Text(
                    'На телефоне: НЕИГРЫ → ТЕЛЕФОН → войти → ввести этот код.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted, fontSize: 20),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 22),
                    Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: danger, fontSize: 18)),
                    const SizedBox(height: 12),
                    FilledButton.tonal(onPressed: _createPairing, child: const Text('ПОЛУЧИТЬ НОВЫЙ КОД')),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StagePage extends StatefulWidget {
  const StagePage({
    super.key,
    required this.api,
    required this.liveCode,
    required this.stageKey,
  });

  final ApiClient api;
  final String liveCode;
  final String stageKey;

  @override
  State<StagePage> createState() => _StagePageState();
}

class _StagePageState extends State<StagePage> {
  late final LiveSocket _socket;
  final LiveClock _clock = LiveClock();
  final AudioPlayer _audio = AudioPlayer();
  StreamSubscription<Map<String, dynamic>>? _messageSub;
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<PlayerState>? _audioStateSub;
  Timer? _reconnectTimer;
  Timer? _tickTimer;
  Timer? _syncTimer;
  Timer? _healthTimer;
  Timer? _audioStartTimer;
  Map<String, dynamic>? _live;
  bool _connected = false;
  bool _disposed = false;
  bool _ending = false;
  bool _handoffToPairing = false;
  bool _mediaPrimed = false;
  bool _instructionEndPending = false;
  String? _error;
  String? _audioKey;
  bool _audioIsFinalRun = false;
  VideoPlayerController? _video;
  String? _videoGameId;
  bool _videoEndedSent = false;

  @override
  void initState() {
    super.initState();
    _socket = LiveSocket(AppConfig.wsUrl(
      code: widget.liveCode,
      role: 'stage',
      key: widget.stageKey,
    ));
    _messageSub = _socket.messages.listen(_onMessage);
    _connectionSub = _socket.connection.listen((connected) {
      if (_disposed) return;
      setState(() => _connected = connected);
      if (connected) {
        _maybeSendStageReady();
        _sendPendingInstructionEnd();
        _sync();
        _syncTimer?.cancel();
        _syncTimer = Timer.periodic(const Duration(seconds: 2), (_) => _sync());
      } else {
        _syncTimer?.cancel();
        _scheduleReconnect();
      }
    });
    _audioStateSub = _audio.playerStateStream.listen(_onAudioState);
    _tickTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted && _live != null) setState(() {});
    });
    _healthTimer = Timer.periodic(const Duration(seconds: 10), (_) => unawaited(_checkLiveHealth()));
    unawaited(_prepareStage());
  }

  Future<void> _prepareStage() async {
    await _enterStageMode();
    try {
      await _audio.setLoopMode(LoopMode.off);
      await _audio.setUrl(AppConfig.mediaUrl('/media/challenge-rock.mp3'));
      await _audio.stop();
      await _audio.setUrl(AppConfig.mediaUrl('/media/final-challenge.wav'));
      await _audio.stop();
    } catch (_) {
      // A cold or temporarily offline TV can still connect; playback retries on the actual run.
    }
    if (_disposed) return;
    _mediaPrimed = true;
    await _connect();
  }

  void _maybeSendStageReady() {
    if (_connected && _mediaPrimed) {
      _socket.send({'type': 'stage_ready'});
    }
  }

  void _sendPendingInstructionEnd() {
    if (_connected && _instructionEndPending) {
      _socket.send({'type': 'instruction_ended'});
    }
  }

  Future<void> _checkLiveHealth() async {
    if (_disposed || _ending) return;
    try {
      await widget.api.live(widget.liveCode, liveKey: widget.stageKey);
    } on ApiException catch (e) {
      if (e.code == 'not_found' || e.code == 'forbidden') {
        await _returnToPairing();
      }
    } catch (_) {
      // Network outages are handled by WebSocket reconnect; do not discard a valid session.
    }
  }

  Future<void> _enterStageMode() async {
    await WakelockPlus.enable();
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _leaveStageMode() async {
    await WakelockPlus.disable();
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> _connect() async {
    if (_disposed) return;
    try {
      await _socket.connect();
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = humanError(e));
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), _connect);
  }

  void _sync() {
    if (!_connected) return;
    _socket.send({
      'type': 'sync_probe',
      'id': 'sync-tv-${DateTime.now().microsecondsSinceEpoch}',
      'sentPerf': _clock.perfNowMs,
    });
  }

  void _onMessage(Map<String, dynamic> message) {
    final type = str(message['type']);
    if (type == 'sync_ack') {
      _clock.updateFromSyncAck(message);
      return;
    }
    if (type != 'hello' && type != 'state') return;
    _clock.updateFromLive(message);
    final state = liveState(message);
    if (str(state['phase']) != 'instruction') _instructionEndPending = false;
    if (mounted) {
      setState(() {
        _live = message;
        _error = null;
      });
    }
    unawaited(_syncMedia());
  }

  Future<void> _returnToPairing() async {
    if (_ending || _disposed) return;
    _ending = true;
    _handoffToPairing = true;
    await SessionStore.instance.clearStageSession();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => TvPairingPage(api: widget.api)),
    );
  }

  Future<void> _syncMedia() async {
    final live = _live;
    if (live == null || _disposed) return;
    final state = liveState(live);
    final season = liveSeason(live);
    final phase = str(state['phase']);

    if (phase == 'instruction') {
      await _audio.stop();
      _audioStartTimer?.cancel();
      final gameId = str(state['instructionGameId']);
      if (gameId.isNotEmpty) await _playInstruction(gameId);
      return;
    }

    await _disposeVideoIfNeeded();

    if (phase == 'countdown' || phase == 'playing') {
      await _ensureRunAudio(
        key: 'regular:${integer(state['runStartedAt'])}',
        url: AppConfig.mediaUrl('/media/challenge-rock.mp3'),
        runStartedAt: integer(state['runStartedAt']),
        finalRun: false,
      );
      return;
    }

    if (phase == 'final_countdown' || phase == 'final_playing' || phase == 'final_decision') {
      await _ensureRunAudio(
        key: 'final:${integer(state['runStartedAt'])}',
        url: AppConfig.mediaUrl('/media/final-challenge.wav'),
        runStartedAt: integer(state['runStartedAt']),
        finalRun: true,
      );
      return;
    }

    if (phase == 'result_feedback') {
      final key = 'feedback:${integer(state['feedbackStartedAt'])}:${str(state['status'])}';
      if (_audioKey != key) {
        _audioKey = key;
        _audioIsFinalRun = false;
        _audioStartTimer?.cancel();
        await _audio.stop();
        await _audio.setLoopMode(LoopMode.off);
        await _audio.setUrl(AppConfig.mediaUrl(
          str(state['status']) == 'success' ? '/media/result-success.wav' : '/media/result-fail.wav',
        ));
        if (!_disposed && _audioKey == key) unawaited(_audio.play());
      }
      return;
    }

    if (phase == 'season_finale' || phase == 'season_finished') {
      final key = 'victory:${integer(state['finaleStartedAt'])}';
      if (_audioKey != key) {
        _audioKey = key;
        _audioIsFinalRun = false;
        _audioStartTimer?.cancel();
        await _audio.stop();
        await _audio.setLoopMode(LoopMode.off);
        await _audio.setUrl(AppConfig.mediaUrl('/media/victory.mp3'));
        if (!_disposed && _audioKey == key) unawaited(_audio.play());
      }
      return;
    }

    if (phase == 'idle' || phase == 'duel' || phase == 'season_summary') {
      _audioStartTimer?.cancel();
      if (_audioKey != null) {
        _audioKey = null;
        _audioIsFinalRun = false;
        await _audio.stop();
      }
    }

    // Keep analyzer aware that season participates in final playback decisions.
    if (season.isEmpty) return;
  }

  Future<void> _ensureRunAudio({
    required String key,
    required String url,
    required int runStartedAt,
    required bool finalRun,
  }) async {
    if (runStartedAt <= 0 || _audioKey == key) return;
    _audioKey = key;
    _audioIsFinalRun = finalRun;
    _audioStartTimer?.cancel();
    await _audio.stop();
    await _audio.setLoopMode(LoopMode.off);
    final duration = await _audio.setUrl(url);
    if (_disposed || _audioKey != key) return;

    Future<void> startAtCurrentOffset() async {
      if (_disposed || _audioKey != key) return;
      final delta = _clock.nowMs - runStartedAt;
      final int? maxMs = duration == null
          ? null
          : (duration.inMilliseconds - 200).clamp(0, duration.inMilliseconds).toInt();
      final int targetMs = delta <= 0
          ? 0
          : maxMs == null
              ? delta
              : delta.clamp(0, maxMs).toInt();
      await _audio.seek(Duration(milliseconds: targetMs));
      if (!_disposed && _audioKey == key) unawaited(_audio.play());
    }

    final delay = runStartedAt - _clock.nowMs;
    if (delay > 20) {
      _audioStartTimer = Timer(Duration(milliseconds: delay), () => unawaited(startAtCurrentOffset()));
    } else {
      await startAtCurrentOffset();
    }
  }

  void _onAudioState(PlayerState playerState) {
    if (playerState.processingState != ProcessingState.completed || !_audioIsFinalRun || _disposed) return;
    final state = liveState(_live);
    final season = liveSeason(_live);
    final phase = str(state['phase']);
    if (phase != 'final_playing' || finalMode(season) == 'timed') return;
    final key = _audioKey;
    unawaited(() async {
      try {
        await _audio.setLoopMode(LoopMode.one);
        await _audio.setUrl(AppConfig.mediaUrl('/media/final-rock-loop.mp3'));
        if (!_disposed && _audioKey == key) unawaited(_audio.play());
      } catch (e) {
        if (mounted) setState(() => _error = 'Не удалось продолжить музыку финала.');
      }
    }());
  }

  Future<void> _playInstruction(String gameId) async {
    if (_videoGameId == gameId && _video != null) return;
    await _disposeVideo();
    _videoGameId = gameId;
    _videoEndedSent = false;
    final info = gameInfo(gameId);
    final path = info?.videoPath ?? '/media/games/$gameId.mp4';
    final controller = VideoPlayerController.networkUrl(Uri.parse(AppConfig.mediaUrl(path)));
    _video = controller;
    controller.addListener(_videoListener);
    try {
      await controller.initialize();
      await controller.setVolume(1);
      await controller.play();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = 'Не удалось запустить видео-инструкцию.');
    }
  }

  void _videoListener() {
    final controller = _video;
    if (controller == null || _videoEndedSent || !controller.value.isInitialized) return;
    final duration = controller.value.duration;
    final position = controller.value.position;
    if (duration > Duration.zero && position >= duration - const Duration(milliseconds: 180)) {
      _videoEndedSent = true;
      _instructionEndPending = true;
      _sendPendingInstructionEnd();
    }
  }

  Future<void> _disposeVideoIfNeeded() async {
    if (_video == null) return;
    await _disposeVideo();
  }

  Future<void> _disposeVideo() async {
    final controller = _video;
    _video = null;
    _videoGameId = null;
    _videoEndedSent = false;
    if (controller != null) {
      controller.removeListener(_videoListener);
      try {
        await controller.pause();
      } catch (_) {}
      await controller.dispose();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _tickTimer?.cancel();
    _syncTimer?.cancel();
    _healthTimer?.cancel();
    _audioStartTimer?.cancel();
    _messageSub?.cancel();
    _connectionSub?.cancel();
    _audioStateSub?.cancel();
    _socket.dispose();
    _audio.dispose();
    final video = _video;
    _video = null;
    video?.dispose();
    if (!_handoffToPairing) unawaited(_leaveStageMode());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = _live;
    if (live == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const NeigryLogo(large: true),
              const SizedBox(height: 28),
              const CircularProgressIndicator(),
              const SizedBox(height: 18),
              Text(_error ?? 'Подключение к игровой сессии...', style: const TextStyle(color: muted, fontSize: 20)),
            ],
          ),
        ),
      );
    }

    final state = liveState(live);
    final season = liveSeason(live);
    final phase = str(state['phase']);
    final game = gameInfo(str(state['selectedGameId']));
    final team = teamById(season, str(state['selectedTeamId']));

    Widget content;
    if (phase == 'instruction') {
      content = _instructionView(state);
    } else if (phase == 'countdown' || phase == 'playing') {
      content = _regularRunView(state, season, game, team);
    } else if (phase == 'final_countdown' || phase == 'final_playing' || phase == 'final_decision') {
      content = _finalRunView(state, season, game);
    } else if (phase == 'result_feedback') {
      content = _feedbackView(state, season);
    } else if (phase == 'duel') {
      content = _duelView(state, season);
    } else if (phase == 'season_summary') {
      content = _summaryView(season);
    } else if (phase == 'season_finale' || phase == 'season_finished') {
      content = _finaleView(season);
    } else {
      content = _idleView(state, season, game, team);
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          content,
          Positioned(
            right: 18,
            top: 14,
            child: StatusPill(label: _connected ? 'ONLINE' : 'RECONNECT', ok: _connected),
          ),
          if (_error != null)
            Positioned(
              left: 24,
              right: 24,
              bottom: 18,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(color: danger.withValues(alpha: .9), borderRadius: BorderRadius.circular(12)),
                child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _instructionView(Map<String, dynamic> state) {
    final game = gameInfo(str(state['instructionGameId']));
    final video = _video;
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (video != null && video.value.isInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: video.value.aspectRatio == 0 ? 16 / 9 : video.value.aspectRatio,
                child: VideoPlayer(video),
              ),
            )
          else
            const Center(child: CircularProgressIndicator()),
          Positioned(
            left: 24,
            bottom: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
              child: Text(
                game == null ? 'КАК ИГРАЕМ?' : '${game.number.toString().padLeft(2, '0')} · ${game.title}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _idleView(
    Map<String, dynamic> state,
    Map<String, dynamic> season,
    GameInfo? game,
    Map<String, dynamic>? team,
  ) {
    final finalGame = isFinalGame(season, str(state['selectedGameId']));
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(54),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(str(season['title'], 'НЕИГРЫ').toUpperCase(), style: const TextStyle(color: muted, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 2)),
            const SizedBox(height: 20),
            Text(
              game == null ? 'ГОТОВЫ' : game.title.toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 66, fontWeight: FontWeight.w900, height: 1.02),
            ),
            const SizedBox(height: 22),
            Text(
              finalGame ? finalRuleLabel(season) : (team == null ? 'ВЫБЕРИТЕ КОМАНДУ НА ПУЛЬТЕ' : str(team['name']).toUpperCase()),
              textAlign: TextAlign.center,
              style: TextStyle(color: finalGame ? cyan : lime, fontSize: 30, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  Widget _regularRunView(
    Map<String, dynamic> state,
    Map<String, dynamic> season,
    GameInfo? game,
    Map<String, dynamic>? team,
  ) {
    final display = regularDisplay(serverNow: _clock.nowMs, runStartedAt: integer(state['runStartedAt']));
    final playing = str(state['phase']) == 'playing';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${str(season['title'])}${team == null ? '' : ' · ${str(team['name'])}'}',
              style: const TextStyle(color: muted, fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            if (game != null) Text(game.title.toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
            const SizedBox(height: 20),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                display,
                style: TextStyle(
                  fontSize: display.length <= 2 ? 230 : 100,
                  fontWeight: FontWeight.w900,
                  height: .92,
                  color: playing ? lime : cyan,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _finalRunView(Map<String, dynamic> state, Map<String, dynamic> season, GameInfo? game) {
    final phase = str(state['phase']);
    final display = finalDisplay(
      serverNow: _clock.nowMs,
      runStartedAt: integer(state['runStartedAt']),
      mode: finalMode(season),
      decision: phase == 'final_decision',
    );
    final teams = seasonTeams(season);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('ФИНАЛЬНОЕ ИСПЫТАНИЕ', style: TextStyle(color: cyan, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 2)),
            if (game != null) ...[
              const SizedBox(height: 8),
              Text(game.title.toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
            ],
            const SizedBox(height: 10),
            Text(finalRuleLabel(season), textAlign: TextAlign.center, style: const TextStyle(color: muted, fontSize: 19)),
            const SizedBox(height: 18),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(display, style: const TextStyle(fontSize: 140, fontWeight: FontWeight.w900, color: lime, height: .9)),
            ),
            const SizedBox(height: 22),
            Row(
              children: teams.map((team) {
                final id = str(team['id']);
                final waitMs = finalTeamStartAt(state, id) - _clock.nowMs;
                final pre = phase == 'final_countdown';
                final label = phase == 'final_decision'
                    ? 'КТО ПОБЕДИЛ?'
                    : pre
                        ? 'ГОТОВЫ'
                        : waitMs <= 0
                            ? 'В ИГРЕ'
                            : '${((waitMs + 999) ~/ 1000)}';
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    decoration: BoxDecoration(
                      color: panel,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: waitMs <= 0 && !pre ? lime.withValues(alpha: .7) : Colors.white12, width: 2),
                    ),
                    child: Column(
                      children: [
                        Text(str(team['name']).toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 6),
                        Text(label, style: TextStyle(color: waitMs <= 0 && !pre ? lime : cyan, fontSize: 22, fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _feedbackView(Map<String, dynamic> state, Map<String, dynamic> season) {
    final success = str(state['status']) == 'success';
    final team = teamById(season, str(state['selectedTeamId']));
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(50),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(success ? Icons.check_circle_rounded : Icons.close_rounded, size: 140, color: success ? lime : danger),
            const SizedBox(height: 18),
            Text(
              success ? 'ИСПЫТАНИЕ\nПРОЙДЕНО' : 'ИСПЫТАНИЕ\nПРОВАЛЕНО',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 72, fontWeight: FontWeight.w900, height: .95, color: success ? lime : danger),
            ),
            if (team != null) ...[
              const SizedBox(height: 22),
              Text(str(team['name']).toUpperCase(), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _duelView(Map<String, dynamic> state, Map<String, dynamic> season) {
    final gameId = str(state['duelGameId']);
    final game = gameInfo(gameId);
    final teams = seasonTeams(season);
    final winnerId = gameId.isEmpty ? null : winnerForGame(season, gameId);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(50),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('ИТОГ ИСПЫТАНИЯ', style: TextStyle(color: cyan, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 2)),
            const SizedBox(height: 8),
            Text((game?.title ?? gameId).toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900)),
            const SizedBox(height: 28),
            Row(
              children: teams.map((team) {
                final id = str(team['id']);
                final result = resultFor(season, gameId, id);
                final success = str(result?['status']) == 'success';
                final winner = winnerId == id;
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: panel,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: winner ? lime : Colors.white12, width: winner ? 3 : 1),
                    ),
                    child: Column(
                      children: [
                        if (winner) const Icon(Icons.emoji_events_rounded, color: lime, size: 44),
                        Text(str(team['name']).toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 10),
                        Text(
                          success ? formatElapsedMs(integer(result?['elapsedMs'])) : 'НЕ ВЫПОЛНЕНО',
                          style: TextStyle(color: success ? Colors.white : danger, fontSize: 22, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryView(Map<String, dynamic> season) {
    final teams = seasonTeams(season);
    final qualifiers = qualifierGameIds(season);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 54, vertical: 34),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('ИТОГОВАЯ ТАБЛИЦА', style: TextStyle(color: cyan, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 2)),
            const SizedBox(height: 28),
            Row(
              children: teams.map((team) {
                final teamId = str(team['id']);
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    decoration: BoxDecoration(
                      color: panel,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white12, width: 2),
                    ),
                    child: Column(
                      children: [
                        Text(str(team['name']).toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 12),
                        Text('${scoreFor(season, teamId)}', style: const TextStyle(fontSize: 82, fontWeight: FontWeight.w900, color: lime, height: .9)),
                        const SizedBox(height: 8),
                        const Text('ОЧКОВ', style: TextStyle(color: muted, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 28),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 260),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: qualifiers.length,
                itemBuilder: (context, index) {
                  final gameId = qualifiers[index];
                  final game = gameInfo(gameId);
                  final winnerId = winnerForGame(season, gameId);
                  final winner = teamById(season, winnerId);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        SizedBox(width: 48, child: Text('${index + 1}', style: const TextStyle(color: muted, fontWeight: FontWeight.w800))),
                        Expanded(child: Text(game?.title ?? gameId, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                        Text(winner == null ? '—' : str(winner['name']), style: TextStyle(color: winner == null ? muted : lime, fontSize: 18, fontWeight: FontWeight.w900)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _finaleView(Map<String, dynamic> season) {
    final finalData = asMap(season['final']);
    final winner = teamById(season, str(finalData['winnerTeamId']));
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(50),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.emoji_events_rounded, size: 150, color: lime),
            const SizedBox(height: 16),
            const Text('ПОБЕДИТЕЛИ СЕЗОНА', style: TextStyle(color: cyan, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 2)),
            const SizedBox(height: 14),
            Text(
              (winner == null ? 'ФИНАЛ ЗАВЕРШЁН' : str(winner['name'])).toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 76, fontWeight: FontWeight.w900, color: lime, height: .95),
            ),
          ],
        ),
      ),
    );
  }
}
