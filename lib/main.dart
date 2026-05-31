import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

// ─── Translations ──────────────────────────────────────────────────────────────

class Translations {
  static final data = {
    'hu': {
      'app_title': 'Lockd 2.3.1',
      'unlock_bt': 'FELOLDÁS',
      'invalid_key': 'Érvénytelen kulcs!',
      'error': 'Hiba',
      'network_error': 'Hálózati hiba',
      'conn_refused_hint':
          'A szerver visszautasította a kapcsolatot. Ellenőrizd a címet (0.0.0.0-n figyel?), a portot és a tűzfalat!',
      'proto_mismatch_hint':
          'Protokoll hiba: HTTPS-t használsz, de a szerver valószínűleg csak sima HTTP-t tud. Írd át http://-re!',
      'view_logs': 'NAPLÓ MEGNYITÁSA',
      'logs_title': 'Rendszernapló',
      'set_key_title': 'Profil beállítása',
      'set_key_hint': 'API Kulcs:',
      'set_key_input_hint': 'Másold be a kulcsot...',
      'set_url_hint': 'Szerver URL (pl. https://lockd.reas.hu:8090):',
      'url_input_hint': 'Szerver címe...',
      'profile_name_hint': 'Profil neve (pl. Otthon):',
      'profile_name_input': 'Profil neve...',
      'save': 'MENTÉS',
      'cancel': 'MÉGSE',
      'state_open': 'Nyitva',
      'state_closed': 'Zárva',
      'state_unknown': 'Ismeretlen',
      'state_not_installed': 'Nincs telepítve',
      'auth_reason': 'Lockd feloldás',
      'state_locking': 'Zárás...',
      'state_unlocking': 'Nyitás...',
      'state_refreshing': 'Frissítés...',
      'btn_lock': 'ZÁR',
      'btn_unlock': 'NYIT',
      'btn_open': 'NYITÁS',
      'btn_pulse': 'GOMB',
      'last_refresh': 'Utolsó frissítés',
      'tooltip_set_key': 'Beállítások',
      'tooltip_refresh': 'Frissít',
      'open_type_error': 'Hiba: Az \'OPEN\' típusú zár nem zárható.',
      'offline_banner': 'Nincs kapcsolat – utolsó ismert állapot',
      'retry': 'ÚJRA',
      'add_profile': 'Profil hozzáadása',
      'profiles_title': 'Profilok',
    },
    'en': {
      'app_title': 'Lockd 2.3.1',
      'unlock_bt': 'UNLOCK',
      'invalid_key': 'Invalid Key!',
      'error': 'Error',
      'network_error': 'Network error',
      'conn_refused_hint':
          'Connection refused. Is the server listening on 0.0.0.0? Check firewall!',
      'proto_mismatch_hint':
          'Protocol mismatch: Using HTTPS on a plain HTTP server? Try http:// instead!',
      'view_logs': 'VIEW LOGS',
      'logs_title': 'System Logs',
      'set_key_title': 'Profile Setup',
      'set_key_hint': 'API Key:',
      'set_key_input_hint': 'Paste your key here...',
      'set_url_hint': 'Server URL (e.g. https://lockd.reas.hu:8090):',
      'url_input_hint': 'Server address...',
      'profile_name_hint': 'Profile name (e.g. Home):',
      'profile_name_input': 'Profile name...',
      'save': 'SAVE',
      'cancel': 'CANCEL',
      'state_open': 'Open',
      'state_closed': 'Closed',
      'state_unknown': 'Unknown',
      'state_not_installed': 'Not Installed',
      'auth_reason': 'Unlock Lockd',
      'state_locking': 'Locking...',
      'state_unlocking': 'Opening...',
      'state_refreshing': 'Refreshing...',
      'btn_lock': 'LOCK',
      'btn_unlock': 'UNLOCK',
      'btn_open': 'OPEN',
      'btn_pulse': 'TRIGGER',
      'last_refresh': 'Last refresh',
      'tooltip_set_key': 'Settings',
      'tooltip_refresh': 'Refresh',
      'open_type_error': 'Error: OPEN type locks cannot be locked.',
      'offline_banner': 'Offline – showing last known state',
      'retry': 'RETRY',
      'add_profile': 'Add Profile',
      'profiles_title': 'Profiles',
    }
  };
}

// ─── Debug Logger ──────────────────────────────────────────────────────────────

class DebugLogger {
  static final List<String> _logs = [];

  static void log(String msg) async {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    final line = "[$ts] $msg";
    _logs.add(line);
    if (_logs.length > 100) _logs.removeAt(0);
    debugPrint(line);
    if (Platform.isWindows) {
      try {
        final dir = await getApplicationSupportDirectory();
        await File(p.join(dir.path, 'debug.log'))
            .writeAsString("$line\n", mode: FileMode.append);
      } catch (_) {}
    }
  }

  static String get all => _logs.join("\n");
}

// ─── Profile Model ─────────────────────────────────────────────────────────────

class Profile {
  final String id;
  String name;
  String url;
  String apiKey;

  Profile(
      {required this.id,
      required this.name,
      required this.url,
      required this.apiKey});

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'url': url, 'key': apiKey};

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        url: j['url'] as String? ?? '',
        apiKey: j['key'] as String? ?? '',
      );
}

// ─── Entry Point ───────────────────────────────────────────────────────────────

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _MyHttpOverrides();
  runApp(const LocksApp());
}

class _MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

// ─── App Shell ─────────────────────────────────────────────────────────────────

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
    _storage.read(key: 'locale').then((v) {
      if (mounted && v != null) setState(() => _locale = v);
    });
  }

  void _toggleTheme() => setState(() {
        _themeMode = switch (_themeMode) {
          ThemeMode.light => ThemeMode.dark,
          ThemeMode.dark => ThemeMode.system,
          ThemeMode.system => ThemeMode.light,
        };
      });

  void _toggleLanguage() async {
    final keys = Translations.data.keys.toList();
    final next = keys[(keys.indexOf(_locale) + 1) % keys.length];
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
          brightness: Brightness.light),
      darkTheme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.blue,
          brightness: Brightness.dark),
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

// ─── Main Screen ───────────────────────────────────────────────────────────────

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
  // SET TO false TO DISABLE BIOMETRICS FOR TESTING
  bool _useAuth = true;

  String? baseUrl;
  String? apiKey;

  List<Profile> _profiles = [];
  Profile? _activeProfile;

  final _storage = const FlutterSecureStorage();
  List<LockModel> locks = [];
  Timer? pollTimer;

  final LocalAuthentication _auth = LocalAuthentication();
  bool _unlocked = false;
  bool _authInProgress = false;
  bool _needsAuth = true;

  bool _isOffline = false;
  bool _pickingFile = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadProfiles().then((_) => _gate());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (state == AppLifecycleState.inactive &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return;
      if (_pickingFile) return;
      _needsAuth = true;
      if (_unlocked) {
        _stopPolling();
        if (mounted) setState(() => _unlocked = false);
      }
      return;
    }
    if (state == AppLifecycleState.resumed && _needsAuth) _gate();
  }

  String _t(String key) => Translations.data[widget.locale]![key] ?? key;

  // ─── Profile Storage ────────────────────────────────────────────────────────

  String _newId() =>
      '${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(9999)}';

  Future<void> _loadProfiles() async {
    var profilesJson = await _storage.read(key: 'profiles');

    // Migrate from legacy single-profile storage
    if (profilesJson == null) {
      final oldKey = await _storage.read(key: 'api_key');
      final oldUrl = await _storage.read(key: 'server_url');
      if (oldKey != null &&
          oldUrl != null &&
          oldKey.isNotEmpty &&
          oldUrl.isNotEmpty) {
        final migrated = Profile(
            id: _newId(), name: 'Default', url: oldUrl, apiKey: oldKey);
        profilesJson = jsonEncode([migrated.toJson()]);
        await _storage.write(key: 'profiles', value: profilesJson);
      }
    }

    if (profilesJson == null) {
      if (mounted) setState(() { _profiles = []; _activeProfile = null; });
      return;
    }

    final list = (jsonDecode(profilesJson) as List)
        .map((j) => Profile.fromJson(j as Map<String, dynamic>))
        .toList();

    final activeId = await _storage.read(key: 'active_profile');
    Profile? active;
    if (list.isNotEmpty) {
      if (activeId != null) {
        try { active = list.firstWhere((pr) => pr.id == activeId); } catch (_) {}
      }
      active ??= list.first;
    }

    if (mounted) {
      setState(() {
        _profiles = list;
        _activeProfile = active;
        if (active != null) { baseUrl = active.url; apiKey = active.apiKey; }
      });
    }
  }

  Future<void> _saveProfiles() async {
    await _storage.write(
        key: 'profiles',
        value: jsonEncode(_profiles.map((pr) => pr.toJson()).toList()));
    if (_activeProfile != null) {
      await _storage.write(key: 'active_profile', value: _activeProfile!.id);
    }
  }

  Future<void> _switchProfile(Profile pr) async {
    _stopPolling();
    if (mounted) setState(() {
      _activeProfile = pr;
      baseUrl = pr.url;
      apiKey = pr.apiKey;
      locks = [];
      _isOffline = false;
    });
    await _storage.write(key: 'active_profile', value: pr.id);
    await _fetchLocks();
    _startPolling();
  }

  // ─── Profile Dialog ─────────────────────────────────────────────────────────

  void _showProfileDialog({Profile? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final urlCtrl =
        TextEditingController(text: existing?.url ?? baseUrl ?? '');
    final keyCtrl = TextEditingController(text: existing?.apiKey ?? '');

    showDialog(
      context: context,
      barrierDismissible: _profiles.isNotEmpty,
      builder: (ctx) => AlertDialog(
        title: Text(existing != null ? _t('set_key_title') : _t('add_profile')),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () =>
                      _loadConfigFromFile(urlCtrl, keyCtrl, nameCtrl),
                  icon: const Icon(Icons.upload_file),
                  label: const Text("Betöltés fájlból"),
                ),
                const SizedBox(height: 16),
                const Text("vagy írj be kézzel:",
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 12),
                Text(_t('profile_name_hint')),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: _t('profile_name_input')),
                ),
                const SizedBox(height: 12),
                Text(_t('set_url_hint')),
                const SizedBox(height: 6),
                TextField(
                  controller: urlCtrl,
                  decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: _t('url_input_hint')),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                Text(_t('set_key_hint')),
                const SizedBox(height: 6),
                TextField(
                  controller: keyCtrl,
                  decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: _t('set_key_input_hint')),
                  autofocus: existing?.apiKey.isEmpty ?? true,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: _showLogs, child: Text(_t('view_logs'))),
          if (_profiles.isNotEmpty)
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(_t('cancel'))),
          FilledButton(
            onPressed: () {
              final url = urlCtrl.text.trim();
              final key = keyCtrl.text.trim();
              if (url.isEmpty || key.isEmpty) return;
              final name = nameCtrl.text.trim();
              Navigator.pop(ctx);
              if (existing != null) {
                existing.name = name.isEmpty ? existing.name : name;
                existing.url = url;
                existing.apiKey = key;
                _saveProfiles();
                if (_activeProfile?.id == existing.id) {
                  setState(() { baseUrl = url; apiKey = key; });
                  _stopPolling();
                  _fetchLocks().then((_) => _startPolling());
                }
                setState(() {});
              } else {
                final newPr = Profile(
                  id: _newId(),
                  name: name.isEmpty ? 'Profile ${_profiles.length + 1}' : name,
                  url: url,
                  apiKey: key,
                );
                setState(() => _profiles.add(newPr));
                _saveProfiles();
                _switchProfile(newPr);
              }
            },
            child: Text(_t('save')),
          ),
        ],
      ),
    );
  }

  void _showProfileSwitcher() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_t('profiles_title'),
                      style: Theme.of(context).textTheme.titleMedium),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: _t('add_profile'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showProfileDialog();
                    },
                  ),
                ],
              ),
            ),
            ..._profiles.map((pr) => ListTile(
                  leading: Icon(Icons.account_circle,
                      color: pr.id == _activeProfile?.id
                          ? Theme.of(context).colorScheme.primary
                          : null),
                  title: Text(pr.name),
                  subtitle: Text(pr.url, overflow: TextOverflow.ellipsis),
                  selected: pr.id == _activeProfile?.id,
                  onTap: () {
                    Navigator.pop(ctx);
                    if (pr.id != _activeProfile?.id) _switchProfile(pr);
                  },
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (pr.id == _activeProfile?.id)
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showProfileDialog(existing: pr);
                          },
                        ),
                      if (_profiles.length > 1)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () {
                            setInner(() => _profiles.removeWhere((x) => x.id == pr.id));
                            setState(() {});
                            _saveProfiles();
                            if (_activeProfile?.id == pr.id && _profiles.isNotEmpty) {
                              Navigator.pop(ctx);
                              _switchProfile(_profiles.first);
                            } else if (_profiles.isEmpty) {
                              Navigator.pop(ctx);
                            }
                          },
                        ),
                    ],
                  ),
                )),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _loadConfigFromFile(
    TextEditingController urlCtrl,
    TextEditingController keyCtrl,
    TextEditingController nameCtrl,
  ) async {
    try {
      _pickingFile = true;
      final FilePickerResult? result;
      try {
        result = await FilePicker.platform.pickFiles(type: FileType.any);
      } finally {
        _pickingFile = false;
      }
      if (result == null || result.files.isEmpty) return;
      final content = await File(result.files.single.path!).readAsString();
      final j = jsonDecode(content) as Map<String, dynamic>;
      final url = j['url'] as String?;
      final token = j['token'] as String?;
      if (url == null || token == null) {
        _snack("${_t('error')}: 'url' és 'token' szükséges");
        return;
      }
      urlCtrl.text = url;
      keyCtrl.text = token;
      if (nameCtrl.text.isEmpty) {
        nameCtrl.text = Uri.tryParse(url)?.host ?? 'Default';
      }
      _snack("Sikeresen betöltve!");
      DebugLogger.log("Config loaded from file: $url");
    } catch (e) {
      _snack("${_t('error')}: $e");
    }
  }

  // ─── Auth ───────────────────────────────────────────────────────────────────

  Map<String, String> _headers() => {
        "X-API-Key": apiKey ?? "",
        "Content-Type": "application/json",
        "Accept": "application/json",
      };

  Future<void> _gate() async {
    bool canCheck = false;
    try { canCheck = await _auth.canCheckBiometrics; } catch (_) {}

    if (!_useAuth || !canCheck) {
      if (mounted) setState(() { _unlocked = true; _needsAuth = false; });
      if (_profiles.isEmpty) {
        _showProfileDialog();
      } else {
        _fetchLocks().then((_) => _startPolling());
      }
      return;
    }

    if (_authInProgress) return;
    _authInProgress = true;
    try {
      final ok = await _auth.authenticate(
        localizedReason: _t('auth_reason'),
        options: const AuthenticationOptions(
            biometricOnly: false, stickyAuth: true, useErrorDialogs: true),
      );
      if (!mounted) return;
      if (ok) {
        _needsAuth = false;
        if (!_unlocked) {
          setState(() => _unlocked = true);
          if (_profiles.isEmpty) _showProfileDialog();
          else _fetchLocks().then((_) => _startPolling());
        }
      } else {
        _needsAuth = true;
        if (_unlocked) { _stopPolling(); setState(() => _unlocked = false); }
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      _snack("AUTH ${_t('error')}: ${e.code}");
      _needsAuth = false;
      if (!_unlocked) {
        setState(() => _unlocked = true);
        if (_profiles.isEmpty) _showProfileDialog();
        else _fetchLocks().then((_) => _startPolling());
      }
    } finally {
      _authInProgress = false;
    }
  }

  // ─── Polling ────────────────────────────────────────────────────────────────

  void _startPolling() {
    if (apiKey == null || apiKey!.isEmpty || baseUrl == null || baseUrl!.isEmpty) return;
    pollTimer?.cancel();
    _refreshOnce();
    pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refreshOnce());
  }

  void _stopPolling() { pollTimer?.cancel(); pollTimer = null; }

  Future<void> _refreshOnce() async {
    for (final lock in locks) {
      await _refreshLock(lock);
    }
  }

  Future<void> _fetchLocks() async {
    if (apiKey == null || apiKey!.isEmpty || baseUrl == null || baseUrl!.isEmpty) return;
    DebugLogger.log("Fetching locks from $baseUrl...");
    try {
      final res = await http
          .get(Uri.parse("$baseUrl/v1/locks"), headers: _headers())
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 401) {
        DebugLogger.log("Auth failed (401)");
        _snack(_t('invalid_key'));
        _showProfileDialog(existing: _activeProfile);
        return;
      }
      if (res.statusCode != 200) {
        DebugLogger.log("API Error: ${res.statusCode}");
        if (mounted) setState(() => _isOffline = true);
        return;
      }

      final data = jsonDecode(res.body);
      final List rawList = data["locks"] ?? [];
      DebugLogger.log("Received ${rawList.length} locks");
      if (!mounted) return;
      setState(() {
        locks = rawList.map((j) => LockModel.fromJson(j)).toList();
        _isOffline = false;
      });
      _pushWidgetUpdate();
    } catch (e) {
      DebugLogger.log("Network error: $e");
      _onNetworkError(e);
    }
  }

  Future<void> _refreshLock(LockModel lock) async {
    try {
      final res = await http
          .get(Uri.parse("$baseUrl/v1/locks/${lock.id}"), headers: _headers())
          .timeout(const Duration(seconds: 3));
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
        _isOffline = false;
      });
      _pushWidgetUpdate();
    } catch (e) {
      _onNetworkError(e, silent: true);
    }
  }

  void _onNetworkError(Object e, {bool silent = false}) {
    if (!mounted) return;
    setState(() => _isOffline = true);
    if (!silent) {
      String msg = e.toString();
      if (msg.contains("1225")) msg = _t('conn_refused_hint');
      else if (msg.contains("WRONG_VERSION_NUMBER")) msg = _t('proto_mismatch_hint');
      _snack("${_t('network_error')}: $msg");
    }
  }

  Future<void> _pushWidgetUpdate() async {
    if (!Platform.isAndroid) return;
    try {
      final data = locks.map((l) => {'name': l.name, 'state': l.state}).toList();
      await HomeWidget.saveWidgetData<String>('locks_json', jsonEncode(data));
      await HomeWidget.saveWidgetData<String>(
          'last_update', DateTime.now().toIso8601String());
      await HomeWidget.updateWidget(androidName: 'LockWidgetProvider');
    } catch (_) {}
  }

  bool _isFinalState(String s) {
    if (s.contains("...") || s.contains("…")) return false;
    const finals = {
      "Nyitva", "Zárva", "NOTFOUND", "OFFLINE", "Ismeretlen",
      "Open", "Closed", "Unknown", "Opened", "Locked", "Unlocked",
      "LOCK", "UNLOCK",
    };
    return finals.contains(s);
  }

  String _getPendingLabel(String upper) {
    if (upper == "LOCK") return _t('state_locking');
    if (upper == "OPEN") return _t('state_unlocking');
    return _t('state_refreshing');
  }

  Future<void> _sendCmd(LockModel lock, String cmd, {bool silent = false}) async {
    if (lock.state == "NOTFOUND" || lock.pending) return;
    final upper = cmd.toUpperCase().trim();
    if (lock.type == "OPEN" && upper == "LOCK") {
      if (!silent) _snack(_t('open_type_error'));
      return;
    }
    if (!mounted) return;
    if (!silent) setState(() { lock.pending = true; lock.pendingLabel = _getPendingLabel(upper); });

    DebugLogger.log("Sending: $upper → ${lock.id}");
    final timeout = Timer(const Duration(seconds: 10), () {
      if (!mounted || !lock.pending) return;
      setState(() { lock.pending = false; lock.pendingLabel = null; });
      _snack("${_t('error')}: Timeout");
    });

    try {
      final res = await http.post(
        Uri.parse("$baseUrl/v1/locks/${lock.id}/cmd"),
        headers: _headers(),
        body: jsonEncode({"cmd": upper}),
      ).timeout(const Duration(seconds: 8));

      DebugLogger.log("Cmd response: ${res.statusCode}");
      if (res.statusCode != 200) {
        if (mounted) setState(() { lock.pending = false; lock.pendingLabel = null; });
        if (!silent) _snack("${_t('error')}: ${res.body}");
        return;
      }
      for (int i = 0; i < 3; i++) {
        if (!lock.pending) break;
        await Future.delayed(Duration(milliseconds: 800 * (i + 1)));
        await _refreshLock(lock);
      }
    } catch (e) {
      DebugLogger.log("Cmd failure: $e");
      if (mounted) setState(() { lock.pending = false; lock.pendingLabel = null; });
      if (!silent) _onNetworkError(e);
    } finally {
      timeout.cancel();
    }
  }

  // ─── UI Helpers ─────────────────────────────────────────────────────────────

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showLogs() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('logs_title')),
        content: Container(
          width: 600,
          height: 400,
          decoration: BoxDecoration(
              color: Colors.black, borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.all(8),
          child: SingleChildScrollView(
            child: Text(
              DebugLogger.all.isEmpty ? "No logs yet." : DebugLogger.all,
              style: const TextStyle(
                  color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],
      ),
    );
  }

  Widget _footer(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text("Lockd 2.3.1",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall),
        ),
      );

  IconData _getThemeIcon() => switch (widget.themeMode) {
        ThemeMode.light => Icons.light_mode,
        ThemeMode.dark => Icons.dark_mode,
        ThemeMode.system => Icons.brightness_auto,
      };

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final langLabel = widget.locale.toUpperCase();
    final multiProfile = _profiles.length > 1;

    if (!_unlocked) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_t('app_title')),
          actions: [
            TextButton(
                onPressed: widget.onLanguageToggle,
                child: Text(langLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold))),
            IconButton(
                onPressed: widget.onThemeToggle, icon: Icon(_getThemeIcon())),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 16)),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _footer(context),
      );
    }

    // Locks list
    Widget locksList;
    if (locks.isEmpty &&
        apiKey != null &&
        apiKey!.isNotEmpty) {
      locksList = const Center(child: CircularProgressIndicator());
    } else {
      locksList = ListView.separated(
        padding: const EdgeInsets.all(12),
        itemBuilder: (_, i) => LockCard(
          lock: locks[i],
          locale: widget.locale,
          onLock: () => _sendCmd(locks[i], "LOCK"),
          onUnlock: () => _sendCmd(locks[i], "OPEN"),
          onStatus: () => _refreshLock(locks[i]),
        ),
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemCount: locks.length,
      );
    }

    // Offline wrapper
    Widget body = _isOffline
        ? Column(children: [
            MaterialBanner(
              backgroundColor: Colors.orange.shade700,
              content: Text(_t('offline_banner'),
                  style: const TextStyle(color: Colors.white)),
              leading: const Icon(Icons.wifi_off, color: Colors.white),
              actions: [
                TextButton(
                  onPressed: _fetchLocks,
                  child: Text(_t('retry'),
                      style: const TextStyle(color: Colors.white)),
                ),
              ],
            ),
            Expanded(child: locksList),
          ])
        : locksList;

    // AppBar title: show active profile name + dropdown if 2+ profiles
    Widget titleWidget = multiProfile && _activeProfile != null
        ? GestureDetector(
            onTap: _showProfileSwitcher,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_activeProfile!.name),
                const SizedBox(width: 2),
                const Icon(Icons.arrow_drop_down, size: 20),
              ],
            ),
          )
        : Text(_t('app_title'));

    return Scaffold(
      appBar: AppBar(
        title: titleWidget,
        actions: [
          TextButton(
              onPressed: widget.onLanguageToggle,
              child: Text(langLabel,
                  style: const TextStyle(fontWeight: FontWeight.bold))),
          if (multiProfile)
            IconButton(
              onPressed: _showProfileSwitcher,
              icon: const Icon(Icons.manage_accounts),
              tooltip: _t('profiles_title'),
            )
          else
            IconButton(
              onPressed: () => _showProfileDialog(existing: _activeProfile),
              icon: const Icon(Icons.vpn_key),
              tooltip: _t('tooltip_set_key'),
            ),
          IconButton(
              onPressed: widget.onThemeToggle, icon: Icon(_getThemeIcon())),
          IconButton(
              onPressed: _fetchLocks,
              icon: const Icon(Icons.sync),
              tooltip: _t('tooltip_refresh')),
        ],
      ),
      body: body,
      bottomNavigationBar: _footer(context),
    );
  }
}

// ─── Lock Model ────────────────────────────────────────────────────────────────

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

  factory LockModel.fromJson(Map<String, dynamic> j) => LockModel(
        id: j["id"] ?? "",
        name: j["name"] ?? "Névtelen",
        type: j["type"] ?? "TOGGLE",
        hasBattery: j["has_battery"] ?? false,
        state: j["state"] ?? "Ismeretlen",
        battery: j["battery"]?.toString(),
        updatedAt: j["updated_at"]?.toString(),
      );
}

// ─── Lock Card ─────────────────────────────────────────────────────────────────

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
  bool get _unlockDisabled =>
      _baseDisabled ||
      (lock.type == "TOGGLE" &&
          (lock.state == "Nyitva" ||
              lock.state == "Open" ||
              lock.state == "UNLOCK"));
  bool get _lockDisabled =>
      _baseDisabled ||
      (lock.type == "TOGGLE" &&
          (lock.state == "Zárva" ||
              lock.state == "Closed" ||
              lock.state == "LOCK"));

  @override
  Widget build(BuildContext context) {
    final shownStateRaw = lock.pending ? (lock.pendingLabel ?? "…") : lock.state;
    String shownState = shownStateRaw;
    if (!lock.pending) {
      if (shownStateRaw == "Nyitva" ||
          shownStateRaw == "Open" ||
          shownStateRaw == "UNLOCK") shownState = _t('state_open');
      else if (shownStateRaw == "Zárva" ||
          shownStateRaw == "Closed" ||
          shownStateRaw == "LOCK") shownState = _t('state_closed');
      else if (shownStateRaw == "Ismeretlen" ||
          shownStateRaw == "Unknown") shownState = _t('state_unknown');
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
                  child: Text(lock.name,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                if (lock.hasBattery && lock.battery != null)
                  _buildBatteryIndicator(context, lock.battery!),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceVariant
                    .withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    lock.pending
                        ? Icons.autorenew
                        : _getStateIcon(lock.state),
                    size: 18,
                    color: lock.pending
                        ? Colors.orange
                        : _getStateColor(lock.state),
                  ),
                  const SizedBox(width: 8),
                  Text(shownState,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                            color: lock.pending
                                ? Colors.orange
                                : _getStateColor(lock.state),
                            fontWeight: FontWeight.w600,
                          )),
                ],
              ),
            ),
            if (lock.updatedAt != null) ...[
              const SizedBox(height: 8),
              Text("${_t('last_refresh')}: ${lock.updatedAt}",
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _unlockDisabled ? null : onUnlock,
                    icon: Icon(lock.type == "PULSE"
                        ? Icons.bolt
                        : (lock.type == "TOGGLE"
                            ? Icons.lock_open
                            : Icons.key)),
                    label: Text(lock.type == "PULSE"
                        ? _t('btn_pulse')
                        : (lock.type == "STRIKE" || lock.type == "OPEN")
                            ? _t('btn_open')
                            : _t('btn_unlock')),
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
                        backgroundColor:
                            Theme.of(context).colorScheme.errorContainer,
                        foregroundColor:
                            Theme.of(context).colorScheme.onErrorContainer,
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
              Text(_t('state_not_installed'),
                  style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBatteryIndicator(BuildContext context, String battStr) {
    final val = int.tryParse(battStr.replaceAll('%', '').trim()) ?? 0;
    final IconData icon;
    final Color color;
    if (val > 85) {
      icon = Icons.battery_full; color = Colors.green;
    } else if (val > 65) {
      icon = Icons.battery_6_bar; color = Colors.green;
    } else if (val > 45) {
      icon = Icons.battery_4_bar; color = Colors.orange;
    } else if (val > 25) {
      icon = Icons.battery_2_bar; color = Colors.orange;
    } else {
      icon = Icons.battery_alert; color = Colors.red;
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
          Text("$val%",
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  IconData _getStateIcon(String state) => switch (state) {
        "Nyitva" || "Open" || "UNLOCK" => Icons.lock_open,
        "Zárva" || "Closed" || "LOCK" => Icons.lock,
        _ => Icons.help_outline,
      };

  Color _getStateColor(String state) => switch (state) {
        "Nyitva" || "Open" || "UNLOCK" => Colors.green,
        "Zárva" || "Closed" || "LOCK" => Colors.red,
        _ => Colors.grey,
      };
}
