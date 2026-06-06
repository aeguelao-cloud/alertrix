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
          title: 'Alertrix Response Overview',
          builder: (context, child) {
            final media = MediaQuery.maybeOf(context);
            if (media == null || child == null) {
              return child ?? const SizedBox.shrink();
            }
            if (media.size.width >= 600) return child;
            final userScale = media.textScaler.scale(1);
            final compactScale = (userScale * 0.88).clamp(0.82, 1.04);
            return MediaQuery(
              data: media.copyWith(
                textScaler: TextScaler.linear(compactScale.toDouble()),
              ),
              child: child,
            );
          },
          theme: ThemeData(
            fontFamily: 'Segoe UI',
            fontFamilyFallback: const ['Inter', 'Arial', 'sans-serif'],
            colorScheme: ColorScheme.fromSeed(
              seedColor: UiColors.brand,
              brightness: Brightness.light,
              primary: UiColors.brand,
              error: UiColors.danger,
            ),
            scaffoldBackgroundColor: UiColors.pageBg,
            cardColor: UiColors.surface,
            dividerColor: UiColors.border,
            visualDensity: VisualDensity.standard,
            textTheme: ThemeData.light().textTheme.apply(
                  bodyColor: UiColors.textBody,
                  displayColor: UiColors.textStrong,
                  fontFamily: 'Segoe UI',
                ),
            appBarTheme: const AppBarTheme(
              toolbarHeight: 64,
              backgroundColor: Color(0xFFF9FCFE),
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
            navigationBarTheme: NavigationBarThemeData(
              backgroundColor: const Color(0xFFF9FCFE),
              height: 72,
              indicatorColor: UiColors.brandSoft,
              elevation: 0,
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                final selected = states.contains(WidgetState.selected);
                return TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                  color: selected ? UiColors.brand : UiColors.textMuted,
                );
              }),
              iconTheme: WidgetStateProperty.resolveWith((states) {
                final selected = states.contains(WidgetState.selected);
                return IconThemeData(
                  color: selected ? UiColors.brand : UiColors.textMuted,
                  size: 22,
                );
              }),
            ),
            dividerTheme: const DividerThemeData(
              color: UiColors.border,
              thickness: 1,
              space: 1,
            ),
            chipTheme: ChipThemeData(
              backgroundColor: UiColors.surfaceAlt,
              selectedColor: UiColors.brandSoft,
              side: const BorderSide(color: UiColors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(UiRadius.pill),
              ),
              labelStyle: const TextStyle(
                color: UiColors.textBody,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            sliderTheme: SliderThemeData(
              activeTrackColor: UiColors.brand,
              inactiveTrackColor: UiColors.border,
              thumbColor: UiColors.brand,
              overlayColor: UiColors.brand.withValues(alpha: 0.12),
            ),
            snackBarTheme: SnackBarThemeData(
              behavior: SnackBarBehavior.floating,
              backgroundColor: UiColors.brandDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(UiRadius.button),
              ),
            ),
            progressIndicatorTheme: const ProgressIndicatorThemeData(
              color: UiColors.brand,
              linearTrackColor: Color(0xFFD9E5EC),
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
