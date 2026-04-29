import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:recall_mobile/providers/auth_provider.dart';
import 'package:recall_mobile/providers/server_config_provider.dart';
import 'package:recall_mobile/screens/auth/auth_screen.dart';

Widget _wrap(Widget child, {ServerConfig? serverConfig}) {
  return ProviderScope(
    overrides: [
      authProvider.overrideWith(
        (ref) => AuthNotifier()..state = AuthState.unauthenticated(),
      ),
      serverConfigProvider.overrideWith(() {
        return _FakeServerConfig(serverConfig);
      }),
    ],
    child: MaterialApp(home: child),
  );
}

class _FakeServerConfig extends ServerConfigNotifier {
  final ServerConfig? _value;
  _FakeServerConfig(this._value);

  @override
  Future<ServerConfig?> build() async => _value;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows Google sign-in button for cloud config', (tester) async {
    await tester.pumpWidget(_wrap(
      const AuthScreen(),
      serverConfig: ServerConfig(mode: ServerMode.cloud, url: 'https://YOUR_BACKEND_DOMAIN/api'),
    ));
    await tester.pump();
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('shows email button for self-hosted config', (tester) async {
    await tester.pumpWidget(_wrap(
      const AuthScreen(),
      serverConfig: ServerConfig(mode: ServerMode.selfHosted, url: 'http://localhost:8000/api'),
    ));
    await tester.pump();
    expect(find.text('Continue with Email'), findsOneWidget);
  });
}
