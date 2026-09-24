import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'config.dart';
import 'phone.dart';
import 'storage.dart';
import 'tv.dart';
import 'ui.dart';

class NeigryApp extends StatelessWidget {
  const NeigryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'НЕИГРЫ',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: ink,
        colorScheme: const ColorScheme.dark(
          primary: cyan,
          secondary: lime,
          surface: panel,
          error: danger,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: panel2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: .08)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: cyan, width: 2),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(style: primaryButtonStyle()),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(fontWeight: FontWeight.w900),
          headlineMedium: TextStyle(fontWeight: FontWeight.w900),
          titleLarge: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      home: const BootstrapPage(),
    );
  }
}

class BootstrapPage extends StatefulWidget {
  const BootstrapPage({super.key});

  @override
  State<BootstrapPage> createState() => _BootstrapPageState();
}

class _BootstrapPageState extends State<BootstrapPage> {
  final ApiClient _api = ApiClient(AppConfig.apiBaseUrl);
  Widget? _destination;

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<bool?> _liveKeyStillValid(StoredLiveSession session) async {
    try {
      await _api.live(session.code, liveKey: session.key);
      return true;
    } on ApiException catch (e) {
      if (e.code == 'not_found' || e.code == 'forbidden') return false;
      return null;
    } catch (_) {
      // A cold start without internet must not erase a still-valid live key.
      return null;
    }
  }

  Future<void> _restore() async {
    final store = SessionStore.instance;
    final role = await store.readDeviceRole();
    final token = await store.readAuthToken();
    if (token != null && token.isNotEmpty) _api.token = token;

    Widget destination;
    if (role == 'tv') {
      final session = await store.readStageSession();
      final validity = session == null ? false : await _liveKeyStillValid(session);
      if (session != null && validity != false) {
        destination = StagePage(
          api: _api,
          liveCode: session.code,
          stageKey: session.key,
        );
      } else {
        await store.clearStageSession();
        destination = TvPairingPage(api: _api);
      }
    } else if (role == 'phone') {
      final session = await store.readControllerSession();
      final validity = session == null ? false : await _liveKeyStillValid(session);
      if (session != null && validity != false) {
        destination = ControllerPage(
          api: _api,
          liveCode: session.code,
          controllerKey: session.key,
        );
      } else {
        await store.clearControllerSession();
        var authenticated = false;
        var authUnknown = false;
        if (_api.token != null && _api.token!.isNotEmpty) {
          try {
            await _api.store();
            authenticated = true;
          } on ApiException catch (e) {
            if (e.statusCode == 401 || e.code == 'unauthorized') {
              _api.token = null;
              await store.clearAuthToken();
            } else {
              authUnknown = true;
            }
          } catch (_) {
            // Preserve the token during a transient network outage.
            authUnknown = true;
          }
        }
        destination = authenticated || authUnknown
            ? PhonePairPage(api: _api)
            : PhoneLoginPage(api: _api);
      }
    } else {
      destination = DeviceModePage(api: _api);
    }

    if (!mounted) return;
    setState(() => _destination = destination);
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _destination ?? const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class DeviceModePage extends StatelessWidget {
  const DeviceModePage({super.key, required this.api});

  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final likelyTv = size.width >= 900 && size.height >= 500;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const NeigryLogo(large: true),
                  const SizedBox(height: 14),
                  Text(
                    'Выберите роль этого устройства',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(color: muted),
                  ),
                  const SizedBox(height: 36),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final horizontal = constraints.maxWidth > 650;
                      final cards = [
                        _ModeCard(
                          autofocus: !likelyTv,
                          icon: Icons.smartphone_rounded,
                          title: 'ТЕЛЕФОН',
                          subtitle: 'Пульт ведущего: вход, сезон, старт и фиксация результата.',
                          onTap: () async {
                            await SessionStore.instance.saveDeviceRole('phone');
                            if (!context.mounted) return;
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(builder: (_) => PhoneLoginPage(api: api)),
                            );
                          },
                        ),
                        _ModeCard(
                          autofocus: likelyTv,
                          icon: Icons.tv_rounded,
                          title: 'ТЕЛЕВИЗОР',
                          subtitle: 'Большой экран: код подключения, видео, таймер и финал.',
                          onTap: () async {
                            await SessionStore.instance.saveDeviceRole('tv');
                            if (!context.mounted) return;
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(builder: (_) => TvPairingPage(api: api)),
                            );
                          },
                        ),
                      ];
                      return horizontal
                          ? Row(
                              children: [
                                Expanded(child: cards[0]),
                                const SizedBox(width: 18),
                                Expanded(child: cards[1]),
                              ],
                            )
                          : Column(
                              children: [
                                cards[0],
                                const SizedBox(height: 18),
                                cards[1],
                              ],
                            );
                    },
                  ),
                  const SizedBox(height: 28),
                  Text(
                    AppConfig.apiBaseUrl,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
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

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.autofocus,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      autofocus: autofocus,
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: panel,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.all(26),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.white.withValues(alpha: .09)),
        ),
      ),
      child: Column(
        children: [
          Icon(icon, size: 58, color: cyan),
          const SizedBox(height: 18),
          Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          const SizedBox(height: 10),
          Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: muted, height: 1.35)),
        ],
      ),
    );
  }
}
