import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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

class _LocksHomeState extends State<LocksHome> {
  // TODO: később settings screen + secure storage
  final String baseUrl = "https://lockd.reas.hu:6443"; // lockd URL (LAN/WAN)
  final String apiKey = "2a45a442ead470916467464ab4f44b66";

  final Map<String, LockModel> locks = {
    "front": LockModel(id: "front", name: "Bejárati ajtó"),
    "back": LockModel(id: "back", name: "Hátsó ajtó"),
  };

  Timer? pollTimer;

  @override
  void initState() {
    super.initState();
    _refreshOnce(); // initial fetch
    _sendCmd("front", "STATUS", silent: true); // one-time confirm on launch
    pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refreshOnce());
  }

  @override
  void dispose() {
    pollTimer?.cancel();
    super.dispose();
  }

  Map<String, String> _headers() => {
        "X-API-Key": apiKey,
        "Content-Type": "application/json",
        "Accept": "application/json",
      };

  Future<void> _refreshOnce() async {
    await _refreshLock("front");
    await _refreshLock("back");
  }

  Future<void> _refreshLock(String id) async {
    try {
      final uri = Uri.parse("$baseUrl/v1/locks/$id");
      final res = await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 3));

      if (res.statusCode == 404) {
        // nincs telepítve
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
      // csendben: a state úgyis OFFLINE lehet a backendben, ha akarod
    }
  }

  bool _isFinalState(String s) {
    return s == "Nyitva" ||
        s == "Zárva" ||
        s == "NOTFOUND" ||
        s == "OFFLINE" ||
        s == "Ismeretlen";
  }

  Future<void> _sendCmd(String id, String cmd, {bool silent = false}) async {
    final lock = locks[id]!;
    if (lock.state == "NOTFOUND") return;
    if (lock.pending) return; // spamvédelem

    final upper = cmd.toUpperCase().trim();

    // Pending UI azonnal
    if (!mounted) return;
    setState(() {
      lock.pending = true;
      lock.pendingLabel = (upper == "LOCK")
          ? "Zárás..."
          : (upper == "UNLOCK")
              ? "Nyitás..."
              : "Frissítés...";
    });

    // Ha nem jön vissza friss állapot, ne ragadjon be
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

      // Parancs után kérjünk STATUS-t is (refresh)
      if (upper != "STATUS") {
        await http
            .post(uri, headers: _headers(), body: jsonEncode({"cmd": "STATUS"}))
            .timeout(const Duration(seconds: 4));
      }

      // pending oldódik, ha a pollingból jön Nyitva/Zárva
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

  @override
  Widget build(BuildContext context) {
    final list = locks.values.toList();
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

  bool get disabled => lock.state == "NOTFOUND" || lock.pending;

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
              Text("Utolsó frissítés: ${lock.updatedAt}",
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: disabled ? null : onUnlock,
                  child: const Text("Nyit"),
                ),
                FilledButton(
                  onPressed: disabled ? null : onLock,
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
