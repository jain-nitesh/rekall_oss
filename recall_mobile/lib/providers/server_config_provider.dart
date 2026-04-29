import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyMode = 'server_mode';
const _keyUrl = 'server_url';
const _cloudUrl = 'https://YOUR_BACKEND_DOMAIN/api';

enum ServerMode { cloud, selfHosted }

class ServerConfig {
  final ServerMode mode;
  final String url;

  const ServerConfig({required this.mode, required this.url});
}

class ServerConfigNotifier extends AsyncNotifier<ServerConfig?> {
  @override
  Future<ServerConfig?> build() async {
    final prefs = await SharedPreferences.getInstance();
    final modeStr = prefs.getString(_keyMode);
    final url = prefs.getString(_keyUrl);
    if (modeStr == null || url == null) return null;
    final mode = modeStr == 'cloud' ? ServerMode.cloud : ServerMode.selfHosted;
    return ServerConfig(mode: mode, url: url);
  }

  Future<void> setCloud() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMode, 'cloud');
    await prefs.setString(_keyUrl, _cloudUrl);
    state = AsyncData(ServerConfig(mode: ServerMode.cloud, url: _cloudUrl));
  }

  Future<void> setSelfHosted(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMode, 'self_hosted');
    await prefs.setString(_keyUrl, url);
    state = AsyncData(ServerConfig(mode: ServerMode.selfHosted, url: url));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyMode);
    await prefs.remove(_keyUrl);
    state = const AsyncData(null);
  }
}

final serverConfigProvider =
    AsyncNotifierProvider<ServerConfigNotifier, ServerConfig?>(
  ServerConfigNotifier.new,
);
