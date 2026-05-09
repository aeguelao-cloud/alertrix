import 'package:flutter/material.dart';

import 'pages/home_shell_page.dart';
import 'pages/login_page.dart';
import 'state/session_controller.dart';
import 'widgets/ui_kit.dart';

class AlertrixApp extends StatefulWidget {
  const AlertrixApp({super.key});

  @override
  State<AlertrixApp> createState() => _AlertrixAppState();
}

class _AlertrixAppState extends State<AlertrixApp> {
  static const String _apiBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');

  late final SessionController _session;

  @override
  void initState() {
    super.initState();
    _session = SessionController();
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _session,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Alertix Response Overview',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF0A7E8C),
              brightness: Brightness.light,
            ),
            scaffoldBackgroundColor: UiColors.pageBg,
            cardColor: UiColors.surface,
            dividerColor: UiColors.border,
            appBarTheme: const AppBarTheme(
              toolbarHeight: 64,
              backgroundColor: UiColors.surface,
              foregroundColor: UiColors.textStrong,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: UiColors.surface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(UiRadius.input),
                borderSide: const BorderSide(color: UiColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(UiRadius.input),
                borderSide: const BorderSide(color: UiColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(UiRadius.input),
                borderSide: const BorderSide(color: UiColors.brand, width: 1.4),
              ),
            ),
            useMaterial3: true,
          ),
          home: _session.isLoggedIn
              ? HomeShellPage(
                  user: _session.user!,
                  onLogout: _session.logout,
                  apiBaseUrl: _apiBaseUrl.isEmpty ? null : _apiBaseUrl,
                )
              : LoginPage(
                  apiBaseUrl: _apiBaseUrl.isEmpty ? null : _apiBaseUrl,
                  onLogin: (username, role) =>
                      _session.login(username: username, role: role),
                ),
        );
      },
    );
  }
}
