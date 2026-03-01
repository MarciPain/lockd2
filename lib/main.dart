import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';

void main() => runApp(const LocksApp());

class LocksApp extends StatelessWidget {
  const LocksApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zárak',
      theme: ThemeData(useMaterial3: true),
      home: const LocksHome(),
    );
  }
}

class LocksHome extends StatefulWidget {
  const LocksHome({super.key});

  @override
  State<LocksHome> createState() => _LocksHomeState();
}

class _LocksHomeState extends State<LocksHome> with WidgetsBindingObserver {
  // TODO: később settings screen + secure storage
  final String baseUrl = "https://lockd.reas.hu:6443"; // lockd URL (LAN/WAN)
  final String apiKey = "2a45a442ead470916467464ab4f44b66";

  final Map<String, LockModel> locks = {
    "front": LockModel(id: "front", name: "Bejárati ajtó"),
    "back": LockModel(id: "back", name: "Hátsó ajtó"),
  };

  Timer? pollTimer;

  final LocalAuthentication _auth = LocalAuthentication();

  bool _unlocked = false;
  bool _authInProgress = false;

  // csak akkor kérjünk újra authot, ha tényleg háttérbe ment
  bool _needsAuth = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _gate(); // induláskor kérjen
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Ha tényleg háttérbe ment, akkor zárjuk vissza.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _needsAuth = true;

      // ha már fel volt oldva, tegyük vissza "zárt" állapotba és állítsuk le a pollingot
      if (_unlocked) {
        _stopPolling();
        if (mounted) setState(() => _unlocked = false);
      }
      return;
    }

    // Visszajött előtérbe: csak akkor kérjünk, ha előtte tényleg háttérben volt
    if (state == AppLifecycleState.resumed) {
      if (_needsAuth) _gate();
    }
  }

  Map<String, String> _headers() => {
        "X-API-Key": apiKey,
        "Content-Type": "application/json",
        "Accept": "application/json",
      };

  Future<void> _gate() async {
    if (_authInProgress) return;
    _authInProgress = true;

    try {
      // Nem ellenőrizgetjük a telefon lock állapotát külön, csak kérünk authot.
      final ok = await _auth.authenticate(
        localizedReason: 'VibeLock feloldás',
        options: const AuthenticationOptions(
          biometricOnly: false, // ujjlenyomat VAGY minta/PIN
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );

      if (!mounted) return;

      if (ok) {
        _needsAuth = false; // <- ez a kulcs, ettől nem lesz loop
        if (!_unlocked) {
          setState(() => _unlocked = true);
          _startPolling();
        }
      } else {
        // Ha cancel / elutasítás: maradjon zárva
        _needsAuth = true;
        if (_unlocked) {
          _stopPolling();
          setState(() => _unlocked = false);
        }
      }
    } on PlatformException catch (e) {
      // Ha az OS nem tud authot, ne legyen tégla. (Ha ezt inkább TILTSUK, szólj.)
      if (!mounted) return;
      _snack("AUTH hiba: ${e.code}");
      _needsAuth = false;
      if (!_unlocked) {
        setState(() => _unlocked = true);
        _startPolling();
      }
    } finally {
      _authInProgress = false;
    }
  }

  void _startPolling() {
    pollTimer?.cancel();
    _refreshOnce(); // initial fetch
    _sendCmd("front", "STATUS", silent: true); // one-time confirm on launch
    pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refreshOnce());
  }

  void _stopPolling() {
    pollTimer?.cancel();
    pollTimer = null;
  }

  Future<void> _refreshOnce() async {
    await _refreshLock("front");
    await _refreshLock("back");
  }

  Future<void> _refreshLock(String id) async {
    try {
      final uri = Uri.parse("$baseUrl/v1/locks/$id");
      final res = await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 3));

      if (res.statusCode == 404) {
        if (!mounted) return;
        setState(() {
          locks[id]!.state = "NOTFOUND";
          locks[id]!.updatedAt = null;
          locks[id]!.pending = false;
          locks[id]!.pendingLabel = null;
        });
        return;
      }

      if (res.statusCode != 200) return;

      final data = jsonDecode(res.body);
      final newState = (data["state"] ?? "Ismeretlen").toString();
      final updatedAt = data["updated_at"]?.toString();

      if (!mounted) return;
      setState(() {
        locks[id]!.state = newState;
        locks[id]!.updatedAt = updatedAt;

        if (locks[id]!.pending && _isFinalState(newState)) {
          locks[id]!.pending = false;
          locks[id]!.pendingLabel = null;
        }
      });
    } catch (_) {
      // csendben
    }
  }

  bool _isFinalState(String s) {
    return s == "Nyitva" || s == "Zárva" || s == "NOTFOUND" || s == "OFFLINE" || s == "Ismeretlen";
  }

  Future<void> _sendCmd(String id, String cmd, {bool silent = false}) async {
    final lock = locks[id]!;
    if (lock.state == "NOTFOUND") return;
    if (lock.pending) return;

    final upper = cmd.toUpperCase().trim();

    if (!mounted) return;
    setState(() {
      lock.pending = true;
      lock.pendingLabel = (upper == "LOCK")
          ? "Zárás..."
          : (upper == "UNLOCK")
              ? "Nyitás..."
              : "Frissítés...";
    });

    final timeout = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      setState(() {
        lock.pending = false;
        lock.pendingLabel = null;
      });
    });

    try {
      final uri = Uri.parse("$baseUrl/v1/locks/$id/cmd");
      final res = await http
          .post(uri, headers: _headers(), body: jsonEncode({"cmd": upper}))
          .timeout(const Duration(seconds: 4));

      if (res.statusCode != 200) {
        timeout.cancel();
        if (!mounted) return;
        setState(() {
          lock.pending = false;
          lock.pendingLabel = null;
        });
        if (!silent) _snack("Hiba: ${res.body}");
        return;
      }

      if (upper != "STATUS") {
        await http
            .post(uri, headers: _headers(), body: jsonEncode({"cmd": "STATUS"}))
            .timeout(const Duration(seconds: 4));
      }

      timeout.cancel();
      await Future.delayed(const Duration(milliseconds: 200));
    } catch (e) {
      timeout.cancel();
      if (!mounted) return;
      setState(() {
        lock.pending = false;
        lock.pendingLabel = null;
      });
      if (!silent) _snack("Hálózati hiba: $e");
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _footer(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
          "VibeLock 1.0",
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = locks.values.toList();

    if (!_unlocked) {
      return Scaffold(
        appBar: AppBar(title: const Text("Zárak")),
        body: Center(
          child: FilledButton(
            onPressed: _gate,
            child: const Text("Feloldás"),
          ),
        ),
        bottomNavigationBar: _footer(context),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Zárak"),
        actions: [
          IconButton(
            onPressed: _refreshOnce,
            icon: const Icon(Icons.refresh),
            tooltip: "Frissít",
          )
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemBuilder: (_, i) => LockCard(
          lock: list[i],
          onLock: () => _sendCmd(list[i].id, "LOCK"),
          onUnlock: () => _sendCmd(list[i].id, "UNLOCK"),
          onStatus: () => _sendCmd(list[i].id, "STATUS"),
        ),
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemCount: list.length,
      ),
      bottomNavigationBar: _footer(context),
    );
  }
}

class LockModel {
  final String id;
  final String name;
  String state;
  String? updatedAt;

  bool pending;
  String? pendingLabel;

  LockModel({
    required this.id,
    required this.name,
    this.state = "Ismeretlen",
    this.updatedAt,
    this.pending = false,
    this.pendingLabel,
  });
}

class LockCard extends StatelessWidget {
  final LockModel lock;
  final VoidCallback onLock;
  final VoidCallback onUnlock;
  final VoidCallback onStatus;

  const LockCard({
    super.key,
    required this.lock,
    required this.onLock,
    required this.onUnlock,
    required this.onStatus,
  });

  bool get _baseDisabled => lock.state == "NOTFOUND" || lock.pending;
  bool get _unlockDisabled => _baseDisabled || lock.state == "Nyitva";
  bool get _lockDisabled => _baseDisabled || lock.state == "Zárva";

  @override
  Widget build(BuildContext context) {
    final shownState = lock.pending ? (lock.pendingLabel ?? "…") : lock.state;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(lock.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Row(
              children: [
                Text("Állapot: ", style: Theme.of(context).textTheme.titleMedium),
                Flexible(
                  child: Text(shownState, style: Theme.of(context).textTheme.titleMedium),
                ),
              ],
            ),
            if (lock.updatedAt != null) ...[
              const SizedBox(height: 4),
              Text(
                "Utolsó frissítés: ${lock.updatedAt}",
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _unlockDisabled ? null : onUnlock,
                  child: const Text("Nyit"),
                ),
                FilledButton(
                  onPressed: _lockDisabled ? null : onLock,
                  child: const Text("Zár"),
                ),
                OutlinedButton(
                  onPressed: lock.pending ? null : onStatus,
                  child: const Text("Frissít"),
                ),
              ],
            ),
            if (lock.state == "NOTFOUND") ...[
              const SizedBox(height: 8),
              Text("Nincs telepítve.", style: Theme.of(context).textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}
