import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';

void main() => runApp(const LocksApp());

class LocksApp extends StatefulWidget {
  const LocksApp({super.key});

  @override
  State<LocksApp> createState() => _LocksAppState();
}

class _LocksAppState extends State<LocksApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void _toggleTheme() {
    setState(() {
      if (_themeMode == ThemeMode.light) {
        _themeMode = ThemeMode.dark;
      } else if (_themeMode == ThemeMode.dark) {
        _themeMode = ThemeMode.system;
      } else {
        _themeMode = ThemeMode.light;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zárak',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.dark,
      ),
      themeMode: _themeMode,
      home: LocksHome(
        themeMode: _themeMode,
        onThemeToggle: _toggleTheme,
      ),
    );
  }
}

class LocksHome extends StatefulWidget {
  final ThemeMode themeMode;
  final VoidCallback onThemeToggle;

  const LocksHome({
    super.key,
    required this.themeMode,
    required this.onThemeToggle,
  });

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
      final newBatt = data["battery"]?.toString();
      final updatedAt = data["updated_at"]?.toString();

      if (!mounted) return;
      setState(() {
        locks[id]!.state = newState;
        locks[id]!.battery = newBatt;
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
          "VibeLock 1.1",
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }

  IconData _getThemeIcon() {
    switch (widget.themeMode) {
      case ThemeMode.light:
        return Icons.light_mode;
      case ThemeMode.dark:
        return Icons.dark_mode;
      case ThemeMode.system:
        return Icons.brightness_auto;
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = locks.values.toList();

    if (!_unlocked) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("VibeLock"),
          actions: [
            IconButton(
              onPressed: widget.onThemeToggle,
              icon: Icon(_getThemeIcon()),
            ),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 80, color: Colors.blue),
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                onPressed: _gate,
                icon: const Icon(Icons.fingerprint),
                label: const Text("Feloldás"),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
              ),
            ],
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
            onPressed: widget.onThemeToggle,
            icon: Icon(_getThemeIcon()),
          ),
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
  String? battery;
  String? updatedAt;

  bool pending;
  String? pendingLabel;

  LockModel({
    required this.id,
    required this.name,
    this.state = "Ismeretlen",
    this.battery,
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
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    lock.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (lock.battery != null) _buildBatteryIndicator(context, lock.battery!),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getStateIcon(lock.state),
                    size: 18,
                    color: _getStateColor(lock.state),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    shownState,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: _getStateColor(lock.state),
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
            if (lock.updatedAt != null) ...[
              const SizedBox(height: 8),
              Text(
                "Utolsó frissítés: ${lock.updatedAt}",
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _unlockDisabled ? null : onUnlock,
                    icon: const Icon(Icons.lock_open),
                    label: const Text("NYIT"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _lockDisabled ? null : onLock,
                    icon: const Icon(Icons.lock),
                    label: const Text("ZÁR"),
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.errorContainer,
                      foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: lock.pending ? null : onStatus,
                  icon: const Icon(Icons.sync),
                ),
              ],
            ),
            if (lock.state == "NOTFOUND") ...[
              const SizedBox(height: 8),
              const Text("Nincs telepítve.", style: TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBatteryIndicator(BuildContext context, String battStr) {
    final val = int.tryParse(battStr) ?? 0;
    IconData icon;
    Color color;

    if (val > 85) {
      icon = Icons.battery_full;
      color = Colors.green;
    } else if (val > 65) {
      icon = Icons.battery_6_bar;
      color = Colors.green;
    } else if (val > 45) {
      icon = Icons.battery_4_bar;
      color = Colors.orange;
    } else if (val > 25) {
      icon = Icons.battery_2_bar;
      color = Colors.orange;
    } else {
      icon = Icons.battery_alert;
      color = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            "$val%",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getStateIcon(String state) {
    switch (state) {
      case "Nyitva":
        return Icons.lock_open;
      case "Zárva":
        return Icons.lock;
      case "Zárás...":
      case "Nyitás...":
        return Icons.autorenew;
      default:
        return Icons.help_outline;
    }
  }

  Color _getStateColor(String state) {
    switch (state) {
      case "Nyitva":
        return Colors.green;
      case "Zárva":
        return Colors.red;
      case "Zárás...":
      case "Nyitás...":
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}
