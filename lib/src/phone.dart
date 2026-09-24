import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'config.dart';
import 'game_catalog.dart';
import 'live_helpers.dart';
import 'live_socket.dart';
import 'storage.dart';
import 'timing.dart';
import 'ui.dart';

class PhoneLoginPage extends StatefulWidget {
  const PhoneLoginPage({super.key, required this.api});
  final ApiClient api;

  @override
  State<PhoneLoginPage> createState() => _PhoneLoginPageState();
}

class _PhoneLoginPageState extends State<PhoneLoginPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_busy) return;
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Введите логин и пароль.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.login(username, password);
      final token = widget.api.token;
      if (token != null && token.isNotEmpty) {
        await SessionStore.instance.saveAuthToken(token);
        await SessionStore.instance.saveDeviceRole('phone');
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => PhonePairPage(api: widget.api)),
      );
    } catch (e) {
      if (mounted) setState(() => _error = humanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const NeigryLogo(),
                  const SizedBox(height: 10),
                  const Text(
                    'Пульт ведущего',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted, fontSize: 18),
                  ),
                  const SizedBox(height: 34),
                  TextField(
                    controller: _username,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Логин'),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    onSubmitted: (_) => _login(),
                    decoration: const InputDecoration(labelText: 'Пароль'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(_error!, style: const TextStyle(color: danger)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _login,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(_busy ? 'ВХОД...' : 'ВОЙТИ'),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'На телевизоре логин и пароль не нужны. Авторизация выполняется только здесь.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PhonePairPage extends StatefulWidget {
  const PhonePairPage({super.key, required this.api});
  final ApiClient api;

  @override
  State<PhonePairPage> createState() => _PhonePairPageState();
}

class _PhonePairPageState extends State<PhonePairPage> {
  final _code = TextEditingController();
  bool _loading = true;
  bool _claiming = false;
  String? _error;
  Map<String, dynamic>? _store;
  String? _seasonId;

  List<Map<String, dynamic>> get _seasons {
    final store = _store;
    if (store == null) return <Map<String, dynamic>>[];
    return asMapList(store['seasons'])
        .where((s) => str(s['status']) != 'finished' && seasonGameOrder(s).isNotEmpty)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _loadStore();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }


  Future<void> _handleUnauthorized() async {
    widget.api.token = null;
    await SessionStore.instance.clearAuthToken();
    await SessionStore.instance.clearControllerSession();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => PhoneLoginPage(api: widget.api)),
      (route) => route.isFirst,
    );
  }
  Future<void> _loadStore() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.store();
      final store = asMap(data['store']);
      final seasons = asMapList(store['seasons'])
          .where((s) => str(s['status']) != 'finished' && seasonGameOrder(s).isNotEmpty)
          .toList();
      final active = str(store['activeSeasonId']);
      var selected = seasons.any((s) => str(s['id']) == active)
          ? active
          : (seasons.isNotEmpty ? str(seasons.first['id']) : null);
      if (selected != null && selected.isEmpty) selected = null;
      if (mounted) {
        setState(() {
          _store = store;
          _seasonId = selected;
        });
      }
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.code == 'unauthorized') {
        await _handleUnauthorized();
      } else if (mounted) {
        setState(() => _error = humanError(e));
      }
    } catch (e) {
      if (mounted) setState(() => _error = humanError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _claim() async {
    final code = _code.text.replaceAll(RegExp(r'\D'), '');
    if (code.length != 6 || _seasonId == null) {
      setState(() => _error = code.length != 6
          ? 'Введите шестизначный код с телевизора.'
          : 'Нет доступного сезона для запуска.');
      return;
    }
    setState(() {
      _claiming = true;
      _error = null;
    });
    try {
      final result = await widget.api.claimPairing(code: code, seasonId: _seasonId!);
      final liveCode = str(result['code']);
      final controllerKey = str(result['controllerKey']);
      if (liveCode.isEmpty || controllerKey.isEmpty) {
        throw StateError('Сервер не вернул ключ управления.');
      }
      await SessionStore.instance.saveControllerSession(code: liveCode, key: controllerKey);
      await SessionStore.instance.saveDeviceRole('phone');
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ControllerPage(
            api: widget.api,
            liveCode: liveCode,
            controllerKey: controllerKey,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.code == 'unauthorized') {
        await _handleUnauthorized();
      } else if (mounted) {
        setState(() => _error = humanError(e));
      }
    } catch (e) {
      if (mounted) setState(() => _error = humanError(e));
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  Future<void> _logout() async {
    try {
      await widget.api.logout();
    } catch (_) {
      // A locally saved token can already be expired; local logout must still succeed.
    } finally {
      widget.api.token = null;
      await SessionStore.instance.clearAuthToken();
      await SessionStore.instance.clearControllerSession();
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => PhoneLoginPage(api: widget.api)),
      (route) => route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Подключить экран'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(onPressed: _loadStore, icon: const Icon(Icons.refresh_rounded)),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout_rounded)),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const PanelCard(
                          child: Text(
                            '1. Откройте НЕИГРЫ на телевизоре.\n2. Выберите режим «Телевизор».\n3. Введите показанный код ниже.',
                            style: TextStyle(color: muted, height: 1.55),
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _code,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: 8),
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                          decoration: const InputDecoration(
                            labelText: 'Код телевизора',
                            hintText: '123456',
                          ),
                        ),
                        const SizedBox(height: 18),
                        if (_seasons.isEmpty)
                          const PanelCard(
                            child: Text(
                              'Нет незавершённых сезонов с испытаниями. Создайте сезон в текущей веб-версии.',
                              style: TextStyle(color: danger, height: 1.45),
                            ),
                          )
                        else
                          DropdownButtonFormField<String>(
                            initialValue: _seasonId,
                            decoration: const InputDecoration(labelText: 'Сезон'),
                            items: _seasons.map((season) {
                              final order = seasonGameOrder(season);
                              return DropdownMenuItem(
                                value: str(season['id']),
                                child: Text('${str(season['title'], 'Сезон')} · ${order.length} испытаний'),
                              );
                            }).toList(),
                            onChanged: _claiming ? null : (value) => setState(() => _seasonId = value),
                          ),
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Text(_error!, style: const TextStyle(color: danger)),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _claiming || _seasons.isEmpty ? null : _claim,
                          child: Text(_claiming ? 'ПОДКЛЮЧЕНИЕ...' : 'ПОДКЛЮЧИТЬ ТЕЛЕВИЗОР'),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class ControllerPage extends StatefulWidget {
  const ControllerPage({
    super.key,
    required this.api,
    required this.liveCode,
    required this.controllerKey,
  });

  final ApiClient api;
  final String liveCode;
  final String controllerKey;

  @override
  State<ControllerPage> createState() => _ControllerPageState();
}

class _ControllerPageState extends State<ControllerPage> {
  late final LiveSocket _socket;
  final LiveClock _clock = LiveClock();
  StreamSubscription<Map<String, dynamic>>? _messageSub;
  StreamSubscription<bool>? _connectionSub;
  Timer? _reconnectTimer;
  Timer? _tickTimer;
  Timer? _syncTimer;
  Timer? _healthTimer;
  Map<String, dynamic>? _live;
  bool _connected = false;
  bool _disposed = false;
  bool _queueLoaded = false;
  String? _notice;
  late final Future<void> _queueLoadFuture;
  List<Map<String, dynamic>> _pendingDoneQueue = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _socket = LiveSocket(AppConfig.wsUrl(
      code: widget.liveCode,
      role: 'controller',
      key: widget.controllerKey,
    ));
    _messageSub = _socket.messages.listen(_onMessage);
    _connectionSub = _socket.connection.listen((connected) {
      if (_disposed) return;
      setState(() => _connected = connected);
      if (connected) {
        _sync();
        _syncTimer?.cancel();
        _syncTimer = Timer.periodic(const Duration(seconds: 2), (_) => _sync());
      } else {
        _syncTimer?.cancel();
        _scheduleReconnect();
      }
    });
    _tickTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (mounted && _live != null) setState(() {});
    });
    _healthTimer = Timer.periodic(const Duration(seconds: 10), (_) => unawaited(_checkLiveHealth()));
    _queueLoadFuture = _loadPendingQueue();
    _connect();
  }

  Future<void> _loadPendingQueue() async {
    final queue = await SessionStore.instance.readDoneQueue(widget.liveCode);
    if (_disposed) return;
    _pendingDoneQueue = queue;
    _queueLoaded = true;
    if (mounted) setState(() {});
  }

  Future<void> _checkLiveHealth() async {
    if (_disposed) return;
    try {
      await widget.api.live(widget.liveCode, liveKey: widget.controllerKey);
    } on ApiException catch (e) {
      if (e.code == 'not_found' || e.code == 'forbidden') {
        await _returnToPairing();
      }
    } catch (_) {
      // Keep the live key during a network outage; WebSocket reconnect handles recovery.
    }
  }

  Future<void> _returnToPairing() async {
    if (_disposed) return;
    await SessionStore.instance.clearControllerSession();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => PhonePairPage(api: widget.api)),
    );
  }

  Future<void> _connect() async {
    if (_disposed) return;
    try {
      await _socket.connect();
      if (mounted) setState(() => _notice = null);
    } catch (e) {
      if (mounted) setState(() => _notice = humanError(e));
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
      'id': 'sync-app-${DateTime.now().microsecondsSinceEpoch}',
      'sentPerf': _clock.perfNowMs,
    });
  }

  void _onMessage(Map<String, dynamic> message) {
    final type = str(message['type']);
    if (type == 'hello' || type == 'state') {
      _clock.updateFromLive(message);
      if (mounted) {
        setState(() {
          _live = message;
          _notice = null;
        });
      }
      return;
    }
    if (type == 'sync_ack') {
      _clock.updateFromSyncAck(message);
      unawaited(_flushDoneQueue());
      return;
    }
    if (type == 'notice' && str(message['code']) == 'stage_not_ready') {
      if (mounted) setState(() => _notice = 'Телевизор подключён, но экран ещё не готов к воспроизведению.');
      return;
    }
    if (type == 'command_accepted') {
      final id = str(message['eventId']);
      if (id.isNotEmpty) unawaited(_removeQueued(id));
      return;
    }
    if (type == 'command_rejected') {
      final id = str(message['eventId']);
      if (id.isNotEmpty) unawaited(_removeQueued(id));
      final reason = str(message['reason']);
      if (mounted) {
        setState(() {
          _notice = reason == 'not_started'
              ? 'Эта команда ещё не начала финал.'
              : reason == 'late_press'
                  ? 'Нажатие было уже после 00:00.000.'
                  : 'Сервер не принял отложенное нажатие.';
        });
      }
    }
  }

  bool _send(String type, [Map<String, dynamic> extra = const {}]) {
    if (!_connected) return false;
    return _socket.send({'type': type, ...extra});
  }

  Future<void> _saveQueue() =>
      SessionStore.instance.saveDoneQueue(widget.liveCode, _pendingDoneQueue);

  Future<void> _removeQueued(String eventId) async {
    final before = _pendingDoneQueue.length;
    _pendingDoneQueue = _pendingDoneQueue.where((item) => str(item['eventId']) != eventId).toList();
    if (_pendingDoneQueue.length == before) return;
    await _saveQueue();
    if (mounted) setState(() {});
  }

  Future<void> _flushDoneQueue() async {
    if (!_connected || !_queueLoaded || _pendingDoneQueue.isEmpty) return;
    final now = _clock.nowMs;
    var changed = false;
    final keep = <Map<String, dynamic>>[];
    for (final item in _pendingDoneQueue) {
      final occurredAt = integer(item['occurredAt']);
      if (occurredAt > 0 && now - occurredAt > 32000) {
        changed = true;
        continue;
      }
      keep.add(item);
      _socket.send({'type': 'done', ...item});
    }
    if (changed) {
      _pendingDoneQueue = keep;
      await _saveQueue();
      if (mounted) {
        setState(() => _notice = 'Старое отложенное нажатие уже вышло за серверное окно 30 секунд и было удалено.');
      }
    }
  }

  Map<String, dynamic>? _pendingForRun(int runStartedAt) {
    if (runStartedAt <= 0) return null;
    for (final item in _pendingDoneQueue) {
      if (pendingDoneBlocksRun(item, runStartedAt)) return item;
    }
    return null;
  }

  Future<void> _done({String? teamId}) async {
    await _queueLoadFuture;
    if (_disposed) return;
    final state = liveState(_live);
    final season = liveSeason(_live);
    final gameId = str(state['selectedGameId']);
    final actualTeamId = teamId ?? str(state['selectedTeamId']);
    final runStartedAt = integer(state['runStartedAt']);
    if (gameId.isEmpty || actualTeamId.isEmpty || runStartedAt <= 0) return;
    if (_pendingForRun(runStartedAt) != null) return;

    final occurredAt = _clock.nowMs;
    if (isFinalGame(season, gameId) && occurredAt < finalTeamStartAt(state, actualTeamId)) {
      if (mounted) setState(() => _notice = 'Эта команда ещё не стартовала.');
      return;
    }

    final event = <String, dynamic>{
      'eventId': 'evt-app-${DateTime.now().microsecondsSinceEpoch}',
      'occurredAt': occurredAt,
      'runStartedAt': runStartedAt,
      'gameId': gameId,
      'teamId': actualTeamId,
      'syncRtt': _clock.lastRttMs,
    };
    _pendingDoneQueue = [..._pendingDoneQueue, event];
    await _saveQueue();
    if (!mounted) return;
    setState(() {});
    final sent = _socket.send({'type': 'done', ...event});
    if (!sent && mounted) {
      setState(() => _notice = 'Связь пропала: финиш сохранён на телефоне и будет отправлен после восстановления.');
    }
  }

  Future<void> _correctTimeout(Map<String, dynamic> state) async {
    if (!_connected) return;
    final controller = TextEditingController(text: '60');
    final seconds = await showDialog<double>(
      context: context,
      builder: (context) {
        String? error;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Засчитать выполнение?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Укажите фактическое время от 0 до 60 секунд.'),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Секунды', errorText: error),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('ОТМЕНА')),
              FilledButton(
                onPressed: () {
                  final value = double.tryParse(controller.text.trim().replaceAll(',', '.'));
                  if (value == null || value < 0 || value > 60) {
                    setDialogState(() => error = 'Введите число от 0 до 60.');
                    return;
                  }
                  Navigator.pop(context, value);
                },
                child: const Text('ЗАСЧИТАТЬ'),
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();
    if (seconds == null || !mounted) return;
    _send('correct_timeout_to_success', {
      'gameId': str(state['selectedGameId']),
      'teamId': str(state['selectedTeamId']),
      'elapsedMs': (seconds * 1000).round().clamp(0, gameDurationMs),
    });
  }

  Future<void> _finishSeason() async {
    if (!_connected) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Завершить сезон?'),
        content: const Text('Текущие результаты будут зафиксированы. Это действие используется и для досрочного завершения сезона.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ОТМЕНА')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ЗАВЕРШИТЬ')),
        ],
      ),
    );
    if (confirmed == true) _send('finish_season');
  }

  Future<void> _stopSession() async {
    try {
      await widget.api.stopLive(widget.liveCode);
    } catch (_) {
      // The session may already have expired or the saved auth token may no longer be valid.
    }
    await SessionStore.instance.clearControllerSession();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => PhonePairPage(api: widget.api)),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _tickTimer?.cancel();
    _syncTimer?.cancel();
    _healthTimer?.cancel();
    _messageSub?.cancel();
    _connectionSub?.cancel();
    _socket.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = _live;
    if (live == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Пульт · ${widget.liveCode}'), backgroundColor: Colors.transparent),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 18),
              Text(_notice ?? 'Подключение к игре...', style: const TextStyle(color: muted)),
            ],
          ),
        ),
      );
    }

    final state = liveState(live);
    final season = liveSeason(live);
    final presence = asMap(live['presence']);
    final phase = str(state['phase']);
    final gameId = str(state['selectedGameId']);
    final teamId = str(state['selectedTeamId']);
    final game = gameInfo(gameId);
    final team = teamById(season, teamId);
    final finalGame = isFinalGame(season, gameId);
    final finalReady = !finalGame || qualifiersComplete(season);
    final running = const {'countdown', 'playing', 'final_countdown', 'final_playing', 'final_decision'}.contains(phase);
    final runStartedAt = integer(state['runStartedAt']);
    final pending = _pendingForRun(runStartedAt) != null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(str(season['title'], 'НЕИГРЫ')),
        actions: [
          IconButton(
            tooltip: 'Остановить сессию',
            onPressed: _stopSession,
            icon: const Icon(Icons.link_off_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusPill(label: _connected ? 'СЕРВЕР' : 'НЕТ СВЯЗИ', ok: _connected),
                StatusPill(
                  label: boolean(presence['stageConnected']) ? 'TV ПОДКЛЮЧЁН' : 'TV НЕ ПОДКЛЮЧЁН',
                  ok: boolean(presence['stageConnected']),
                ),
                StatusPill(
                  label: boolean(presence['stageReady']) ? 'ЭКРАН ГОТОВ' : 'ЭКРАН НЕ ГОТОВ',
                  ok: boolean(presence['stageReady']),
                ),
              ],
            ),
            if (_notice != null) ...[
              const SizedBox(height: 12),
              Text(_notice!, style: const TextStyle(color: danger, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 16),
            PanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    game == null ? 'Испытание не выбрано' : '${game.number.toString().padLeft(2, '0')} · ${game.title}',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    finalGame
                        ? finalRuleLabel(season)
                        : team == null
                            ? 'Выберите команду'
                            : str(team['name']),
                    style: TextStyle(
                      color: finalGame ? cyan : lime,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (phase == 'idle') ...[
              _GamePicker(
                season: season,
                selectedGameId: gameId,
                enabled: _connected,
                onSelect: (id) => _send('select_game', {'gameId': id}),
              ),
              const SizedBox(height: 14),
              if (!finalGame)
                _TeamPicker(
                  season: season,
                  gameId: gameId,
                  selectedTeamId: teamId,
                  enabled: _connected,
                  onSelect: (id) => _send('select_team', {'teamId': id}),
                ),
              if (!finalGame) const SizedBox(height: 14),
              if (finalGame && !finalReady) ...[
                const PanelCard(
                  child: Text(
                    'Финал станет доступен после того, как обе команды завершат все отборочные испытания.',
                    style: TextStyle(color: danger, fontWeight: FontWeight.w700, height: 1.4),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: _connected && boolean(presence['stageReady']) && gameId.isNotEmpty
                          ? () => _send('instruction')
                          : null,
                      child: const Text('▶ КАК ИГРАЕМ?'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _connected &&
                              boolean(presence['stageReady']) &&
                              gameId.isNotEmpty &&
                              finalReady &&
                              (finalGame || teamId.isNotEmpty)
                          ? () => _send('start')
                          : null,
                      child: const Text('СТАРТ'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: _connected ? _finishSeason : null,
                child: const Text('ЗАВЕРШИТЬ СЕЗОН'),
              ),
            ] else if (phase == 'instruction') ...[
              PanelCard(
                child: Column(
                  children: [
                    const Icon(Icons.ondemand_video_rounded, size: 46, color: cyan),
                    const SizedBox(height: 10),
                    const Text('На телевизоре идёт видео-инструкция.', textAlign: TextAlign.center),
                    const SizedBox(height: 14),
                    FilledButton.tonal(
                      onPressed: _connected ? () => _send('instruction_ended') : null,
                      child: const Text('ПРОПУСТИТЬ РОЛИК'),
                    ),
                  ],
                ),
              ),
            ] else if (running) ...[
              _RunPanel(
                state: state,
                season: season,
                clock: _clock,
                pending: pending,
                connected: _connected,
                onDone: () => unawaited(_done()),
                onDoneFinal: (id) => unawaited(_done(teamId: id)),
                onCancel: () => _send('cancel'),
              ),
            ] else if (phase == 'result_feedback') ...[
              _ResultFeedback(
                state: state,
                season: season,
                connected: _connected,
                onCorrectTimeout: () => unawaited(_correctTimeout(state)),
                onFinishSeason: _finishSeason,
              ),
            ] else if (phase == 'duel') ...[
              _DuelPanel(
                state: state,
                season: season,
                connected: _connected,
                onNext: () => _send('dismiss_duel'),
                onFinishSeason: _finishSeason,
              ),
            ] else if (phase == 'season_finale' || phase == 'season_finished' || phase == 'season_summary') ...[
              _FinalePanel(
                state: state,
                season: season,
                connected: _connected,
                onFinish: _finishSeason,
                onShowFinale: () => _send('show_finale'),
                onShowSummary: () => _send('show_summary'),
              ),
            ] else ...[
              PanelCard(child: Text('Состояние игры: $phase', style: const TextStyle(color: muted))),
            ],
          ],
        ),
      ),
    );
  }
}

class _GamePicker extends StatelessWidget {
  const _GamePicker({
    required this.season,
    required this.selectedGameId,
    required this.enabled,
    required this.onSelect,
  });

  final Map<String, dynamic> season;
  final String selectedGameId;
  final bool enabled;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final order = seasonGameOrder(season);
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ИСПЫТАНИЯ', style: TextStyle(color: muted, fontWeight: FontWeight.w800, letterSpacing: 1)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: order.map((id) {
              final game = gameInfo(id);
              final selected = id == selectedGameId;
              return ChoiceChip(
                selected: selected,
                label: Text(game == null ? id : '${game.number.toString().padLeft(2, '0')} ${game.title}'),
                onSelected: enabled ? (_) => onSelect(id) : null,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _TeamPicker extends StatelessWidget {
  const _TeamPicker({
    required this.season,
    required this.gameId,
    required this.selectedTeamId,
    required this.enabled,
    required this.onSelect,
  });

  final Map<String, dynamic> season;
  final String gameId;
  final String selectedTeamId;
  final bool enabled;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final teams = seasonTeams(season);
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('КОМАНДА', style: TextStyle(color: muted, fontWeight: FontWeight.w800, letterSpacing: 1)),
          const SizedBox(height: 12),
          Row(
            children: teams.map((team) {
              final id = str(team['id']);
              final played = gameId.isNotEmpty && resultFor(season, gameId, id) != null;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilledButton.tonal(
                    onPressed: !enabled || played ? null : () => onSelect(id),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      side: id == selectedTeamId ? const BorderSide(color: lime, width: 2) : null,
                    ),
                    child: Text(played ? '${str(team['name'])}\nСЫГРАЛИ' : str(team['name']), textAlign: TextAlign.center),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _RunPanel extends StatelessWidget {
  const _RunPanel({
    required this.state,
    required this.season,
    required this.clock,
    required this.pending,
    required this.connected,
    required this.onDone,
    required this.onDoneFinal,
    required this.onCancel,
  });

  final Map<String, dynamic> state;
  final Map<String, dynamic> season;
  final LiveClock clock;
  final bool pending;
  final bool connected;
  final VoidCallback onDone;
  final ValueChanged<String> onDoneFinal;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final phase = str(state['phase']);
    final runStartedAt = integer(state['runStartedAt']);
    final isFinal = phase.startsWith('final_');
    final display = isFinal
        ? finalDisplay(
            serverNow: clock.nowMs,
            runStartedAt: runStartedAt,
            mode: finalMode(season),
            decision: phase == 'final_decision',
          )
        : regularDisplay(serverNow: clock.nowMs, runStartedAt: runStartedAt);

    return PanelCard(
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 110,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                display,
                style: TextStyle(
                  fontSize: display.length <= 2 ? 96 : 44,
                  fontWeight: FontWeight.w900,
                  color: phase.contains('playing') || phase == 'final_decision' ? lime : cyan,
                  height: 1,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (isFinal)
            _FinalDoneButtons(
              state: state,
              season: season,
              clock: clock,
              pending: pending,
              onDone: onDoneFinal,
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: primaryButtonStyle(color: lime),
                onPressed: phase == 'playing' && !pending ? onDone : null,
                child: Text(pending ? 'ФИКСИРУЮ...' : connected ? 'ГОТОВО' : 'ГОТОВО · СОХРАНИТЬ OFFLINE'),
              ),
            ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: connected ? onCancel : null,
            icon: const Icon(Icons.close_rounded),
            label: const Text('ОТМЕНИТЬ ЗАПУСК'),
          ),
        ],
      ),
    );
  }
}

class _FinalDoneButtons extends StatelessWidget {
  const _FinalDoneButtons({
    required this.state,
    required this.season,
    required this.clock,
    required this.pending,
    required this.onDone,
  });

  final Map<String, dynamic> state;
  final Map<String, dynamic> season;
  final LiveClock clock;
  final bool pending;
  final ValueChanged<String> onDone;

  @override
  Widget build(BuildContext context) {
    final phase = str(state['phase']);
    final teams = seasonTeams(season);
    return Column(
      children: [
        Text(finalRuleLabel(season), textAlign: TextAlign.center, style: const TextStyle(color: muted)),
        const SizedBox(height: 16),
        ...teams.map((team) {
          final id = str(team['id']);
          final startAt = finalTeamStartAt(state, id);
          final waitMs = startAt - clock.nowMs;
          final ready = phase == 'final_decision' || waitMs <= 0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: primaryButtonStyle(color: ready ? lime : cyan),
                onPressed: ready && !pending ? () => onDone(id) : null,
                child: Text(
                  pending
                      ? 'ФИКСИРУЮ...'
                      : ready
                          ? '${str(team['name'])} · ПОБЕДИЛИ'
                          : '${str(team['name'])} · СТАРТ ЧЕРЕЗ ${((waitMs + 999) ~/ 1000)}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _ResultFeedback extends StatelessWidget {
  const _ResultFeedback({
    required this.state,
    required this.season,
    required this.connected,
    required this.onCorrectTimeout,
    required this.onFinishSeason,
  });

  final Map<String, dynamic> state;
  final Map<String, dynamic> season;
  final bool connected;
  final VoidCallback onCorrectTimeout;
  final VoidCallback onFinishSeason;

  @override
  Widget build(BuildContext context) {
    final success = str(state['status']) == 'success';
    final timeout = str(state['status']) == 'timeout';
    final team = teamById(season, str(state['selectedTeamId']));
    return PanelCard(
      child: Column(
        children: [
          Icon(success ? Icons.check_circle_rounded : Icons.timer_off_rounded, size: 68, color: success ? lime : danger),
          const SizedBox(height: 12),
          Text(
            success ? 'ИСПЫТАНИЕ ПРОЙДЕНО' : 'ИСПЫТАНИЕ ПРОВАЛЕНО',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: success ? lime : danger),
          ),
          if (team != null) ...[
            const SizedBox(height: 8),
            Text(str(team['name']), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ],
          if (success) ...[
            const SizedBox(height: 8),
            Text(formatElapsedMs(integer(state['elapsedMs'])), style: const TextStyle(color: muted)),
          ],
          if (timeout) ...[
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: connected ? onCorrectTimeout : null,
              child: const Text('УСПЕЛИ — ЗАСЧИТАТЬ ВРУЧНУЮ'),
            ),
          ],
          const SizedBox(height: 10),
          TextButton(
            onPressed: connected ? onFinishSeason : null,
            child: const Text('ЗАВЕРШИТЬ СЕЗОН'),
          ),
        ],
      ),
    );
  }
}

class _DuelPanel extends StatelessWidget {
  const _DuelPanel({
    required this.state,
    required this.season,
    required this.connected,
    required this.onNext,
    required this.onFinishSeason,
  });

  final Map<String, dynamic> state;
  final Map<String, dynamic> season;
  final bool connected;
  final VoidCallback onNext;
  final VoidCallback onFinishSeason;

  @override
  Widget build(BuildContext context) {
    final gameId = str(state['duelGameId']);
    final game = gameInfo(gameId);
    final teams = seasonTeams(season);
    final winnerId = gameId.isEmpty ? null : winnerForGame(season, gameId);
    return PanelCard(
      child: Column(
        children: [
          const Text('РЕЗУЛЬТАТ ИСПЫТАНИЯ', style: TextStyle(color: cyan, fontWeight: FontWeight.w900, letterSpacing: 1)),
          const SizedBox(height: 10),
          Text(game?.title ?? gameId, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
          const SizedBox(height: 18),
          ...teams.map((team) {
            final id = str(team['id']);
            final result = resultFor(season, gameId, id);
            final success = str(result?['status']) == 'success';
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(winnerId == id ? Icons.emoji_events_rounded : Icons.groups_rounded, color: winnerId == id ? lime : muted),
              title: Text(str(team['name']), style: const TextStyle(fontWeight: FontWeight.w800)),
              trailing: Text(
                success ? formatElapsedMs(integer(result?['elapsedMs'])) : 'НЕ ВЫПОЛНЕНО',
                style: TextStyle(color: success ? Colors.white : danger, fontWeight: FontWeight.w800),
              ),
            );
          }),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: connected ? onNext : null, child: const Text('ДАЛЬШЕ')),
          ),
          TextButton(
            onPressed: connected ? onFinishSeason : null,
            child: const Text('ЗАВЕРШИТЬ СЕЗОН'),
          ),
        ],
      ),
    );
  }
}

class _FinalePanel extends StatelessWidget {
  const _FinalePanel({
    required this.state,
    required this.season,
    required this.connected,
    required this.onFinish,
    required this.onShowFinale,
    required this.onShowSummary,
  });

  final Map<String, dynamic> state;
  final Map<String, dynamic> season;
  final bool connected;
  final VoidCallback onFinish;
  final VoidCallback onShowFinale;
  final VoidCallback onShowSummary;

  @override
  Widget build(BuildContext context) {
    final phase = str(state['phase']);
    final finalData = asMap(season['final']);
    final winner = teamById(season, str(finalData['winnerTeamId']));
    final teams = seasonTeams(season);

    return PanelCard(
      child: Column(
        children: [
          if (phase == 'season_summary') ...[
            const Text('ИТОГОВАЯ ТАБЛИЦА', style: TextStyle(color: cyan, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
            const SizedBox(height: 18),
            ...teams.map((team) => ListTile(
                  leading: const Icon(Icons.groups_rounded, color: muted),
                  title: Text(str(team['name']), style: const TextStyle(fontWeight: FontWeight.w900)),
                  trailing: Text('${scoreFor(season, str(team['id']))} очк.', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: lime)),
                )),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: connected ? onShowFinale : null,
              child: const Text('ПОКАЗАТЬ ПОБЕДИТЕЛЯ НА ЭКРАНЕ'),
            ),
          ] else ...[
            const Icon(Icons.emoji_events_rounded, size: 88, color: lime),
            const SizedBox(height: 12),
            const Text('ПОБЕДИТЕЛИ СЕЗОНА', style: TextStyle(color: muted, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            Text(
              winner == null ? 'ФИНАЛ ЗАВЕРШЁН' : str(winner['name']).toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: lime),
            ),
            const SizedBox(height: 18),
            if (phase == 'season_finale')
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: connected ? onFinish : null,
                  child: const Text('ЗАФИКСИРОВАТЬ ИТОГ'),
                ),
              )
            else if (phase == 'season_finished')
              FilledButton.tonal(
                onPressed: connected ? onShowSummary : null,
                child: const Text('ПОКАЗАТЬ ИТОГОВУЮ ТАБЛИЦУ'),
              ),
          ],
        ],
      ),
    );
  }
}
