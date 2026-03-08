import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Translations {
  static const Map<String, Map<String, String>> data = {
    'hu': {
      'app_title': 'Lockd 2.0',
      'unlock_bt': 'Feloldás',
      'auth_reason': 'Lockd feloldás',
      'set_key_title': 'API Kulcs beállítása',
      'set_key_hint': 'Másold be az auth kulcsodat (X-API-Key):',
      'set_key_input_hint': 'Kulcs beillesztése...',
      'cancel': 'Mégse',
      'save': 'Mentés',
      'error': 'Hiba',
      'network_error': 'Hálózati hiba',
      'invalid_key': 'Érvénytelen API kulcs!',
      'state_open': 'Nyitva',
      'state_closed': 'Zárva',
      'state_locking': 'Zárás...',
      'state_unlocking': 'Nyitás...',
      'state_refreshing': 'Frissítés...',
      'state_unknown': 'Ismeretlen',
      'state_not_installed': 'Nincs telepítve.',
      'btn_lock': 'ZÁR',
      'btn_unlock': 'NYIT',
      'btn_open': 'NYITÁS',
      'btn_pulse': 'GOMB',
      'last_refresh': 'Utolsó frissítés',
      'tooltip_set_key': 'Kulcs beállítása',
      'tooltip_refresh': 'Frissít',
      'open_type_error': 'Hiba: Az \'OPEN\' típusú zár nem zárható.',
      'set_url_hint': 'Add meg a szerver címet (pl. https://...):',
      'url_input_hint': 'https://domain.com:6443',
    },
    'en': {
      'app_title': 'Lockd 2.0',
      'unlock_bt': 'Unlock App',
      'auth_reason': 'Unlock Lockd',
      'set_key_title': 'Setup Server & Key',
      'set_key_hint': 'Paste your auth key (X-API-Key):',
      'set_key_input_hint': 'Paste key...',
      'cancel': 'Cancel',
      'save': 'Save',
      'error': 'Error',
      'network_error': 'Network error',
      'invalid_key': 'Invalid API Key!',
      'state_open': 'Open',
      'state_closed': 'Closed',
      'state_locking': 'Locking...',
      'state_unlocking': 'Opening...',
      'state_refreshing': 'Refreshing...',
      'state_unknown': 'Unknown',
      'state_not_installed': 'Not installed.',
      'btn_lock': 'LOCK',
      'btn_unlock': 'UNLOCK',
      'btn_open': 'OPEN',
      'btn_pulse': 'TRIGGER',
      'last_refresh': 'Last refresh',
      'tooltip_set_key': 'Setup',
      'tooltip_refresh': 'Refresh',
      'open_type_error': 'Error: OPEN type locks cannot be locked.',
      'set_url_hint': 'Enter server URL (e.g. https://...):',
      'url_input_hint': 'https://domain.com:6443',
    }
  };
}

void main() => runApp(const LocksApp());

class LocksApp extends StatefulWidget {
  const LocksApp({super.key});

  @override
  State<LocksApp> createState() => _LocksAppState();
}

class _LocksAppState extends State<LocksApp> {
  ThemeMode _themeMode = ThemeMode.system;
  String _locale = 'hu';
  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final loc = await _storage.read(key: 'locale') ?? 'hu';
    if (mounted) setState(() => _locale = loc);
  }

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

  void _toggleLanguage() async {
    final keys = Translations.data.keys.toList();
    final currentIndex = keys.indexOf(_locale);
    final nextIndex = (currentIndex + 1) % keys.length;
    final next = keys[nextIndex];
    await _storage.write(key: 'locale', value: next);
    setState(() => _locale = next);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Translations.data[_locale]!['app_title']!,
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
        locale: _locale,
        onLanguageToggle: _toggleLanguage,
      ),
    );
  }
}

class LocksHome extends StatefulWidget {
  final ThemeMode themeMode;
  final VoidCallback onThemeToggle;
  final String locale;
  final VoidCallback onLanguageToggle;

  const LocksHome({
    super.key,
    required this.themeMode,
    required this.onThemeToggle,
    required this.locale,
    required this.onLanguageToggle,
  });

  @override
  State<LocksHome> createState() => _LocksHomeState();
}

class _LocksHomeState extends State<LocksHome> with WidgetsBindingObserver {
  // SET TO false TO DISABLE BIOMETRICS FOR TESTING / SCREENSHOTS
  bool _useAuth = true;

  String? baseUrl;
  String? apiKey;

  final _storage = const FlutterSecureStorage();
  List<LockModel> locks = [];
  Timer? pollTimer;

  final LocalAuthentication _auth = LocalAuthentication();

  bool _unlocked = false;
  bool _authInProgress = false;
  bool _needsAuth = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadKey().then((_) => _gate());
  }

  String _t(String key) => Translations.data[widget.locale]![key] ?? key;

  Future<void> _loadKey() async {
    final key = await _storage.read(key: 'api_key');
    final url = await _storage.read(key: 'server_url');
    if (mounted) {
      setState(() {
        apiKey = key;
        baseUrl = url;
      });
    }
  }

  Future<void> _saveKey(String url, String key) async {
    await _storage.write(key: 'server_url', value: url);
    await _storage.write(key: 'api_key', value: key);
    if (mounted) {
      setState(() {
        baseUrl = url;
        apiKey = key;
      });
    }
    _refreshOnce();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _needsAuth = true;
      if (_unlocked) {
        _stopPolling();
        if (mounted) setState(() => _unlocked = false);
      }
      return;
    }
    if (state == AppLifecycleState.resumed) {
      if (_needsAuth) _gate();
    }
  }

  Map<String, String> _headers() => {
        "X-API-Key": apiKey ?? "",
        "Content-Type": "application/json",
        "Accept": "application/json",
      };

  Future<void> _gate() async {
    if (!_useAuth) {
      if (mounted) {
        setState(() {
          _unlocked = true;
          _needsAuth = false;
        });
      }
      if (apiKey == null || apiKey!.isEmpty || baseUrl == null || baseUrl!.isEmpty) {
        _showKeyDialog();
      } else {
        await _fetchLocks();
        _startPolling();
      }
      return;
    }

    if (_authInProgress) return;
    _authInProgress = true;

    try {
      final ok = await _auth.authenticate(
        localizedReason: _t('auth_reason'),
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );

      if (!mounted) return;

      if (ok) {
        _needsAuth = false;
        if (!_unlocked) {
          setState(() => _unlocked = true);
          if (apiKey == null || apiKey!.isEmpty || baseUrl == null || baseUrl!.isEmpty) {
            _showKeyDialog();
          } else {
            await _fetchLocks();
            _startPolling();
          }
        }
      } else {
        _needsAuth = true;
        if (_unlocked) {
          _stopPolling();
          setState(() => _unlocked = false);
        }
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      _snack("AUTH ${_t('error')}: ${e.code}");
      _needsAuth = false;
      if (!_unlocked) {
        setState(() => _unlocked = true);
        if (apiKey == null || apiKey!.isEmpty || baseUrl == null || baseUrl!.isEmpty) {
          _showKeyDialog();
        } else {
          _fetchLocks().then((_) => _startPolling());
        }
      }
    } finally {
      _authInProgress = false;
    }
  }

  void _showKeyDialog() {
    final urlController = TextEditingController(text: baseUrl);
    final keyController = TextEditingController(text: apiKey);
    
    showDialog(
      context: context,
      barrierDismissible: apiKey != null && apiKey!.isNotEmpty && baseUrl != null && baseUrl!.isNotEmpty,
      builder: (context) => AlertDialog(
        title: Text(_t('set_key_title')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_t('set_url_hint')),
              const SizedBox(height: 8),
              TextField(
                controller: urlController,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: _t('url_input_hint'),
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 16),
              Text(_t('set_key_hint')),
              const SizedBox(height: 8),
              TextField(
                controller: keyController,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: _t('set_key_input_hint'),
                ),
                autofocus: apiKey == null || apiKey!.isEmpty,
              ),
            ],
          ),
        ),
        actions: [
          if (apiKey != null && apiKey!.isNotEmpty && baseUrl != null && baseUrl!.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_t('cancel')),
            ),
          FilledButton(
            onPressed: () {
              final url = urlController.text.trim();
              final key = keyController.text.trim();
              if (url.isNotEmpty && key.isNotEmpty) {
                _saveKey(url, key);
                Navigator.pop(context);
                _fetchLocks().then((_) => _startPolling());
              }
            },
            child: Text(_t('save')),
          ),
        ],
      ),
    );
  }

  void _startPolling() {
    if (apiKey == null || apiKey!.isEmpty || baseUrl == null || baseUrl!.isEmpty) return;
    pollTimer?.cancel();
    _refreshOnce();
    pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refreshOnce());
  }

  void _stopPolling() {
    pollTimer?.cancel();
    pollTimer = null;
  }

  Future<void> _fetchLocks() async {
    if (apiKey == null || apiKey!.isEmpty || baseUrl == null || baseUrl!.isEmpty) return;
    try {
      final uri = Uri.parse("$baseUrl/v1/locks");
      final res = await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 5));

      if (res.statusCode == 401) {
        _snack(_t('invalid_key'));
        _showKeyDialog();
        return;
      }

      if (res.statusCode != 200) {
        _snack("API ${_t('error')} (lista): ${res.statusCode}");
        return;
      }

      final data = jsonDecode(res.body);
      final List rawList = data["locks"] ?? [];

      if (!mounted) return;
      setState(() {
        locks = rawList.map((j) => LockModel.fromJson(j)).toList();
      });
    } catch (e) {
      _snack("${_t('network_error')}: $e");
    }
  }

  Future<void> _refreshOnce() async {
    if (apiKey == null || apiKey!.isEmpty || baseUrl == null || baseUrl!.isEmpty) return;
    for (var lock in locks) {
      await _refreshLock(lock);
    }
  }

  Future<void> _refreshLock(LockModel lock) async {
    try {
      final uri = Uri.parse("$baseUrl/v1/locks/${lock.id}");
      final res = await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 3));

      if (res.statusCode != 200) return;

      final data = jsonDecode(res.body);
      final newState = (data["state"] ?? "Ismeretlen").toString();
      final newBatt = data["battery"]?.toString();
      final updatedAt = data["updated_at"]?.toString();

      if (!mounted) return;
      setState(() {
        lock.state = newState;
        lock.battery = newBatt;
        lock.updatedAt = updatedAt;

        if (lock.pending && _isFinalState(newState)) {
          lock.pending = false;
          lock.pendingLabel = null;
        }
      });
    } catch (_) {
      // csendben
    }
  }

  bool _isFinalState(String s) {
    return s == "Nyitva" || s == "Zárva" || s == "NOTFOUND" || s == "OFFLINE" || s == "Ismeretlen" ||
           s == "Open" || s == "Closed" || s == "Unknown";
  }

  Future<void> _sendCmd(LockModel lock, String cmd, {bool silent = false}) async {
    if (lock.state == "NOTFOUND") return;
    if (lock.pending) return;

    final upper = cmd.toUpperCase().trim();

    // Safety: no LOCK for OPEN type
    if (lock.type == "OPEN" && upper == "LOCK") {
      if (!silent) _snack(_t('open_type_error'));
      return;
    }

    if (!mounted) return;
    setState(() {
      lock.pending = true;
      lock.pendingLabel = (upper == "LOCK")
          ? _t('state_locking')
          : (upper == "UNLOCK")
              ? _t('state_unlocking')
              : _t('state_refreshing');
    });

    final timeout = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      if (lock.pending) {
        setState(() {
          lock.pending = false;
          lock.pendingLabel = null;
        });
      }
    });

    try {
      final uri = Uri.parse("$baseUrl/v1/locks/${lock.id}/cmd");
      final res = await http
          .post(uri, headers: _headers(), body: jsonEncode({"cmd": upper}))
          .timeout(const Duration(seconds: 5));

      if (res.statusCode != 200) {
        timeout.cancel();
        if (!mounted) return;
        setState(() {
          lock.pending = false;
          lock.pendingLabel = null;
        });
        if (!silent) _snack("${_t('error')}: ${res.body}");
        return;
      }

      // If it was a control command, trigger a status refresh soon
      if (upper != "STATUS") {
        await Future.delayed(const Duration(milliseconds: 500));
        _refreshLock(lock);
      }

      timeout.cancel();
    } catch (e) {
      timeout.cancel();
      if (!mounted) return;
      setState(() {
        lock.pending = false;
        lock.pendingLabel = null;
      });
      if (!silent) _snack("${_t('network_error')}: $e");
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _footer(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
          "Lockd 2.0 (Dynamic)",
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
    final langLabel = widget.locale.toUpperCase();

    if (!_unlocked) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_t('app_title')),
          actions: [
            TextButton(
              onPressed: widget.onLanguageToggle,
              child: Text(langLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
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
                label: Text(_t('unlock_bt')),
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
        title: Text(_t('app_title')),
        actions: [
          TextButton(
            onPressed: widget.onLanguageToggle,
            child: Text(langLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          IconButton(
            onPressed: _showKeyDialog,
            icon: const Icon(Icons.vpn_key),
            tooltip: _t('tooltip_set_key'),
          ),
          IconButton(
            onPressed: widget.onThemeToggle,
            icon: Icon(_getThemeIcon()),
          ),
          IconButton(
            onPressed: _refreshOnce,
            icon: const Icon(Icons.sync),
            tooltip: _t('tooltip_refresh'),
          )
        ],
      ),
      body: locks.isEmpty && (apiKey != null && apiKey!.isNotEmpty && baseUrl != null && baseUrl!.isNotEmpty)
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemBuilder: (_, i) => LockCard(
                lock: locks[i],
                locale: widget.locale,
                onLock: () => _sendCmd(locks[i], "LOCK"),
                onUnlock: () => _sendCmd(locks[i], "UNLOCK"),
                onStatus: () => _sendCmd(locks[i], "STATUS"),
              ),
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemCount: locks.length,
            ),
      bottomNavigationBar: _footer(context),
    );
  }
}

class LockModel {
  final String id;
  final String name;
  final String type;
  final bool hasBattery;

  String state;
  String? battery;
  String? updatedAt;

  bool pending;
  String? pendingLabel;

  LockModel({
    required this.id,
    required this.name,
    required this.type,
    required this.hasBattery,
    this.state = "Ismeretlen",
    this.battery,
    this.updatedAt,
    this.pending = false,
    this.pendingLabel,
  });

  factory LockModel.fromJson(Map<String, dynamic> j) {
    return LockModel(
      id: j["id"] ?? "",
      name: j["name"] ?? "Névtelen",
      type: j["type"] ?? "TOGGLE",
      hasBattery: j["has_battery"] ?? false,
      state: j["state"] ?? "Ismeretlen",
      battery: j["battery"]?.toString(),
      updatedAt: j["updated_at"]?.toString(),
    );
  }
}

class LockCard extends StatelessWidget {
  final LockModel lock;
  final String locale;
  final VoidCallback onLock;
  final VoidCallback onUnlock;
  final VoidCallback onStatus;

  const LockCard({
    super.key,
    required this.lock,
    required this.locale,
    required this.onLock,
    required this.onUnlock,
    required this.onStatus,
  });

  String _t(String key) => Translations.data[locale]![key] ?? key;

  bool get _baseDisabled => lock.state == "NOTFOUND" || lock.pending;
  bool get _unlockDisabled => _baseDisabled || 
    (lock.type == "TOGGLE" && (lock.state == "Nyitva" || lock.state == "Open"));
  bool get _lockDisabled => _baseDisabled || 
    (lock.type == "TOGGLE" && (lock.state == "Zárva" || lock.state == "Closed"));

  @override
  Widget build(BuildContext context) {
    final shownStateRaw = lock.pending ? (lock.pendingLabel ?? "…") : lock.state;
    // Map backend state strings to localized labels if not pending
    String shownState = shownStateRaw;
    if (!lock.pending) {
      if (shownStateRaw == "Nyitva" || shownStateRaw == "Open") shownState = _t('state_open');
      else if (shownStateRaw == "Zárva" || shownStateRaw == "Closed") shownState = _t('state_closed');
      else if (shownStateRaw == "Ismeretlen" || shownStateRaw == "Unknown") shownState = _t('state_unknown');
      else if (shownStateRaw == "NOTFOUND") shownState = _t('state_not_installed');
    }

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
                if (lock.hasBattery && lock.battery != null) _buildBatteryIndicator(context, lock.battery!),
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
                "${_t('last_refresh')}: ${lock.updatedAt}",
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _unlockDisabled ? null : onUnlock,
                    icon: Icon(lock.type == "PULSE" ? Icons.bolt : (lock.type == "TOGGLE" ? Icons.lock_open : Icons.key)),
                    label: Text(
                      lock.type == "PULSE" ? _t('btn_pulse') : 
                      (lock.type == "STRIKE" || lock.type == "OPEN") ? _t('btn_open') : _t('btn_unlock')
                    ),
                  ),
                ),
                if (lock.type == "TOGGLE") ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _lockDisabled ? null : onLock,
                      icon: const Icon(Icons.lock),
                      label: Text(_t('btn_lock')),
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.errorContainer,
                        foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: lock.pending ? null : onStatus,
                  icon: const Icon(Icons.sync),
                ),
              ],
            ),
            if (lock.state == "NOTFOUND") ...[
              const SizedBox(height: 8),
              Text(_t('state_not_installed'), style: const TextStyle(color: Colors.red)),
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
      case "Open":
        return Icons.lock_open;
      case "Zárva":
      case "Closed":
        return Icons.lock;
      case "Zárás...":
      case "Nyitás...":
      case "Locking...":
      case "Opening...":
        return Icons.autorenew;
      default:
        return Icons.help_outline;
    }
  }

  Color _getStateColor(String state) {
    switch (state) {
      case "Nyitva":
      case "Open":
        return Colors.green;
      case "Zárva":
      case "Closed":
        return Colors.red;
      case "Zárás...":
      case "Nyitás...":
      case "Locking...":
      case "Opening...":
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}
