import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/auth_models.dart';
import '../models/monitoring_models.dart';
import '../services/push_notification_service.dart';
import '../state/monitoring_controller.dart';
import '../utils/alert_audio_player_stub.dart'
    if (dart.library.html) '../utils/alert_audio_player_web.dart'
    as alert_audio;
import '../widgets/ui_kit.dart';
import 'alert_detail_page.dart';
import 'alerts_page.dart';
import 'admin_management_page.dart';
import 'dashboard_page.dart';
import 'settings_page.dart';
import 'trends_page.dart';
import 'work_orders_page.dart';

class HomeShellPage extends StatefulWidget {
  const HomeShellPage({
    super.key,
    required this.user,
    required this.onLogout,
    this.apiBaseUrl,
  });

  final AppUser user;
  final VoidCallback onLogout;
  final String? apiBaseUrl;

  @override
  State<HomeShellPage> createState() => _HomeShellPageState();
}

class _HomeShellPageState extends State<HomeShellPage> {
  // Temporary safety switch: disable in-app popup overlays on web debug to
  // avoid re-entrant layout / mouse tracker assertion storms.
  static const bool _enableInAppAlertPopups = false;
  static const double _compactBreakpoint = 1024;

  late final MonitoringController _controller;
  late final PushNotificationService _pushService;
  StreamSubscription<RemoteMessage>? _fcmSubscription;
  String? _pushToken;
  String? _pushStatusMessage = 'FCM initializing...';
  int _selectedIndex = 0;
  bool _alertDialogOpen = false;
  final Set<String> _shownAlertPopups = <String>{};
  final Set<String> _shownFcmPopups = <String>{};
  bool _alertPopupPrimed = false;
  SensorLevel _activeAlertSoundLevel = SensorLevel.warning;
  String _pushRule = 'Warning + Critical';
  bool _alertSoundEnabled = true;
  DateTime? _lastNotificationSettingSync;
  bool _webAudioPrimed = false;
  Timer? _alertSoundLoopTimer;
  Timer? _pushRetryTimer;
  int _pushRetryCount = 0;
  bool _manualRefreshBusy = false;
  bool _manualPushBusy = false;
  int _refreshToken = 0;
  Duration _alertSoundInterval = const Duration(seconds: 4);
  DateTime? _lastPopupShownAt;
  static const Duration _popupWindow = Duration(seconds: 15);
  static const String _defaultZone = 'Zone A - Pump Station';
  bool get _isAdmin => widget.user.role == UserRole.admin;
  bool get _isSuperAdmin {
    final id = widget.user.username.trim().toLowerCase();
    return id == 'admin@alertrix.local' || id == 'admin';
  }

  List<int> get _visibleNavIndexes {
    final base =
        _isSuperAdmin ? const <int>[0, 1, 2, 3, 4, 5] : const <int>[0, 1, 2, 4];
    final seen = <int>{};
    return base.where(seen.add).toList(growable: false);
  }

  static const List<_NavItem> _navItems = [
    _NavItem(icon: Icons.dashboard_outlined, label: 'Response Overview'),
    _NavItem(icon: Icons.insights_outlined, label: 'Situation Trends'),
    _NavItem(icon: Icons.warning_amber_outlined, label: 'Incident Queue'),
    _NavItem(icon: Icons.assignment_outlined, label: 'Work Orders'),
    _NavItem(icon: Icons.settings_outlined, label: 'Response Settings'),
    _NavItem(
        icon: Icons.admin_panel_settings_outlined, label: 'Admin Management'),
  ];

  @override
  void initState() {
    super.initState();
    _pushService = PushNotificationService();
    _controller = MonitoringController(apiBaseUrl: widget.apiBaseUrl);
    if (_enableInAppAlertPopups) {
      _controller.addListener(_handleControllerSideEffects);
    }
    _controller.initialize();
    _loadNotificationSettings();
    _setupPushNotifications();
  }

  @override
  void dispose() {
    unawaited(_stopAlertSoundLoop());
    _pushRetryTimer?.cancel();
    _fcmSubscription?.cancel();
    if (_enableInAppAlertPopups) {
      _controller.removeListener(_handleControllerSideEffects);
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final snapshot = _controller.snapshot;
        final compact = _isCompactLayout(context);
        return Listener(
          onPointerDown: kIsWeb && !_webAudioPrimed
              ? (_) => _primeAlertAudioByInteraction()
              : null,
          child: compact
              ? _buildCompactScaffold(snapshot)
              : _buildDesktopScaffold(snapshot),
        );
      },
    );
  }

  bool _isCompactLayout(BuildContext context) {
    return MediaQuery.sizeOf(context).width < _compactBreakpoint;
  }

  Widget _buildDesktopScaffold(MonitoringSnapshot? snapshot) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 24,
        elevation: 0,
        centerTitle: false,
        title: _buildTopBarTitle(),
      ),
      body: _buildShellBody(snapshot, compact: false),
    );
  }

  Widget _buildCompactScaffold(MonitoringSnapshot? snapshot) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 58,
        titleSpacing: 8,
        title: Text(
          _titleByIndex(_selectedIndex),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        actions: [
          _buildQuickPopupButton(),
          _buildRefreshActionButton(),
          _buildPushActionButton(),
          _buildUserMenuButton(),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A7E8C).withOpacity(0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.shield_outlined,
                        color: Color(0xFF0A7E8C),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Alertrix',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _visibleNavIndexes.length,
                  itemBuilder: (context, index) {
                    final navIndex = _visibleNavIndexes[index];
                    final selected = _selectedIndex == navIndex;
                    final item = _navItems[navIndex];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        item.icon,
                        color: selected
                            ? const Color(0xFF0A7E8C)
                            : const Color(0xFF5D7078),
                      ),
                      title: Text(
                        item.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? const Color(0xFF0A7E8C)
                              : const Color(0xFF2A3B42),
                        ),
                      ),
                      selected: selected,
                      selectedTileColor:
                          const Color(0xFF0A7E8C).withOpacity(0.10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      onTap: () => _selectNavIndex(navIndex, closeDrawer: true),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      body: _buildShellBody(snapshot, compact: true),
    );
  }

  Widget _buildShellBody(
    MonitoringSnapshot? snapshot, {
    required bool compact,
  }) {
    if (_controller.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot == null) {
      return _buildNoDataView();
    }

    if (compact) {
      return Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(
                UiSpace.page, UiSpace.page, UiSpace.page, 0),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: UiColors.surface,
              borderRadius: BorderRadius.circular(UiRadius.button),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _buildTopStatusPills(),
            ),
          ),
          const SizedBox(height: UiSpace.page),
          Expanded(child: _buildPage(snapshot)),
        ],
      );
    }

    return Row(
      children: [
        _buildDesktopNavigationPanel(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              UiSpace.page,
              UiSpace.page,
              UiSpace.page,
              UiSpace.page,
            ),
            child: _buildPage(snapshot),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopNavigationPanel() {
    return Container(
      width: 248,
      margin: const EdgeInsets.fromLTRB(
        UiSpace.page,
        UiSpace.page,
        0,
        UiSpace.page,
      ),
      decoration: BoxDecoration(
        color: UiColors.surface,
        borderRadius: BorderRadius.circular(UiRadius.big),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1220303A),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A7E8C).withOpacity(0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    color: Color(0xFF0A7E8C),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Alertrix',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: _visibleNavIndexes.length,
              padding: const EdgeInsets.all(10),
              itemBuilder: (context, index) {
                final navIndex = _visibleNavIndexes[index];
                final selected = _selectedIndex == navIndex;
                final item = _navItems[navIndex];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _selectNavIndex(navIndex),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF0A7E8C).withOpacity(0.14)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            item.icon,
                            color: selected
                                ? const Color(0xFF0A7E8C)
                                : const Color(0xFF5D7078),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            item.label,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: selected
                                  ? const Color(0xFF0A7E8C)
                                  : const Color(0xFF2A3B42),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _selectNavIndex(int navIndex, {bool closeDrawer = false}) {
    if (_selectedIndex != navIndex) {
      setState(() => _selectedIndex = navIndex);
    }
    if (closeDrawer) {
      Navigator.of(context).pop();
    }
  }

  void _handleControllerSideEffects() {
    if (!_enableInAppAlertPopups) return;
    final snapshot = _controller.snapshot;
    if (snapshot == null || !mounted) return;
    _primeExistingAlerts(snapshot);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final latest = _controller.snapshot;
      if (latest == null) return;
      _maybeShowAlertPopup(latest);
    });
  }

  Widget _buildTopBarTitle() {
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Alertrix',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              Text(
                _titleByIndex(_selectedIndex),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF5E7179),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 11,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _buildTopStatusPills(),
          ),
        ),
        const SizedBox(width: 8),
        _buildQuickPopupButton(),
        _buildRefreshActionButton(),
        _buildPushActionButton(),
        _buildUserMenuButton(),
      ],
    );
  }

  Widget _buildTopStatusPills() {
    final ready = (_pushToken?.isNotEmpty ?? false);
    final disabled = _isPushDisabledMessage(_pushStatusMessage);
    final hasCloudError = _controller.errorMessage != null;
    final lastSync = _controller.lastSuccessfulSyncAt;

    final cloudLabel = hasCloudError ? 'Degraded' : 'Healthy';
    final cloudTone =
        hasCloudError ? _TopStatusTone.warning : _TopStatusTone.healthy;
    final apiLabel = _controller.usingRemoteApi ? 'Connected' : 'Fallback';
    final pushLabel =
        ready ? 'Enabled' : (disabled ? 'Off' : 'Permission Required');
    final pushTone = ready
        ? _TopStatusTone.healthy
        : (disabled ? _TopStatusTone.neutral : _TopStatusTone.warning);
    final syncText = lastSync == null ? '--' : _formatHeaderTime(lastSync);

    return Row(
      children: [
        _buildTopStatusPill(
          label: 'Cloud Sync',
          value: cloudLabel,
          tone: cloudTone,
        ),
        _buildTopStatusPill(
          label: 'Last Sync',
          value: syncText,
          tone: _TopStatusTone.neutral,
        ),
        _buildTopStatusPill(
          label: 'API',
          value: apiLabel,
          tone: _controller.usingRemoteApi
              ? _TopStatusTone.healthy
              : _TopStatusTone.warning,
        ),
        _buildTopStatusPill(
          label: 'Push',
          value: pushLabel,
          tone: pushTone,
        ),
      ],
    );
  }

  Widget _buildRefreshActionButton() {
    return IconButton(
      tooltip: 'Refresh',
      onPressed: (_controller.loading || _manualRefreshBusy)
          ? null
          : _manualRefreshWithFeedback,
      icon: _manualRefreshBusy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh_rounded),
    );
  }

  Widget _buildQuickPopupButton() {
    return IconButton(
      tooltip: 'Show popup',
      onPressed: _showQuickPopup,
      icon: const Icon(Icons.open_in_new_rounded),
    );
  }

  Future<void> _showQuickPopup() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Notification'),
          content: const Text('Popup channel is active.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPushActionButton() {
    return IconButton(
      tooltip: (_pushToken?.isNotEmpty ?? false)
          ? 'Notifications Enabled'
          : 'Enable Push Notifications',
      onPressed: _manualPushBusy ? null : _manualRetryPushSetupWithFeedback,
      icon: _manualPushBusy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              (_pushToken?.isNotEmpty ?? false)
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_outlined,
            ),
    );
  }

  Widget _buildUserMenuButton() {
    return PopupMenuButton<String>(
      tooltip: 'User menu',
      onSelected: (value) {
        if (value == 'profile') {
          _showProfileDialog();
          return;
        }
        if (value == 'permission') {
          unawaited(_manualRetryPushSetupWithFeedback());
          return;
        }
        if (value == 'logout') widget.onLogout();
      },
      itemBuilder: (context) => [
        const PopupMenuItem<String>(
          value: 'profile',
          child: Text('Profile'),
        ),
        const PopupMenuItem<String>(
          value: 'permission',
          child: Text('Notification Permission'),
        ),
        PopupMenuItem<String>(
          enabled: false,
          value: 'role',
          child: Text('Role: ${widget.user.role.label}'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'logout',
          child: Text('Logout'),
        ),
      ],
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6),
        child: Icon(Icons.account_circle_outlined),
      ),
    );
  }

  Widget _buildTopStatusPill({
    required String label,
    required String value,
    required _TopStatusTone tone,
  }) {
    final (bg, text) = switch (tone) {
      _TopStatusTone.healthy => (
          const Color(0xFFE7F7EE),
          const Color(0xFF1E7A3F),
        ),
      _TopStatusTone.warning => (
          const Color(0xFFFFF4DF),
          const Color(0xFFA06100),
        ),
      _TopStatusTone.danger => (
          const Color(0xFFFFECEC),
          const Color(0xFF9A2D2D),
        ),
      _TopStatusTone.neutral => (
          const Color(0xFFF1F4F7),
          const Color(0xFF566A72),
        ),
    };

    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: text,
        ),
      ),
    );
  }

  String _formatHeaderTime(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Widget _buildNoDataView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 48, color: Color(0xFF7C8F96)),
            const SizedBox(height: 12),
            const Text(
              'Cloud communication lost / no telemetry received',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              _controller.errorMessage ??
                  'Unable to fetch cloud sensor readings right now.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF62757E)),
            ),
            if (_controller.lastSuccessfulSyncAt != null) ...[
              const SizedBox(height: 4),
              Text(
                'Last successful sync: ${_formatSyncTime(_controller.lastSuccessfulSyncAt!)}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF62757E)),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _manualRefreshBusy
                  ? null
                  : () => unawaited(_manualRefreshWithFeedback()),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry Sync'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatSyncTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm:$ss';
  }

  Widget _buildPage(MonitoringSnapshot snapshot) {
    switch (_selectedIndex) {
      case 0:
        return DashboardPage(
          snapshot: snapshot,
          onOpenAlertDetail: _openAlertDetail,
          onNavigateToAlerts: () => setState(() => _selectedIndex = 2),
          onRetrySync: () => unawaited(_manualRefreshWithFeedback()),
          syncBusy: _manualRefreshBusy || _controller.loading,
        );
      case 1:
        return TrendsPage(
          snapshot: snapshot,
          apiBaseUrl: widget.apiBaseUrl,
          refreshToken: _refreshToken,
        );
      case 2:
        return AlertsPage(
          snapshot: snapshot,
          role: widget.user.role,
          onOpenAlertDetail: _openAlertDetail,
          onAcknowledgeVisible: (ids) =>
              _controller.confirmAlerts(ids, widget.user.role),
        );
      case 3:
        if (_isAdmin) {
          return WorkOrdersPage(apiBaseUrl: widget.apiBaseUrl);
        }
        return AlertsPage(
          snapshot: snapshot,
          role: widget.user.role,
          onOpenAlertDetail: _openAlertDetail,
          onAcknowledgeVisible: (ids) =>
              _controller.confirmAlerts(ids, widget.user.role),
        );
      case 5:
        if (_isAdmin) {
          return AdminManagementPage(
            apiBaseUrl: widget.apiBaseUrl,
            adminHeaderUserId: _adminHeaderUserId(),
          );
        }
        return SettingsPage(
          username: widget.user.username,
          role: widget.user.role,
          onNavigateBackToDashboard: () => setState(() => _selectedIndex = 0),
          apiBaseUrl: widget.apiBaseUrl,
          onNotificationSettingsChanged: _loadNotificationSettings,
        );
      default:
        return SettingsPage(
          username: widget.user.username,
          role: widget.user.role,
          onNavigateBackToDashboard: () => setState(() => _selectedIndex = 0),
          apiBaseUrl: widget.apiBaseUrl,
          onNotificationSettingsChanged: _loadNotificationSettings,
        );
    }
  }

  Future<void> _openAlertDetail(AlertEvent alert) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlertDetailPage(
          alert: alert,
          role: widget.user.role,
          onConfirm: () => _controller.confirmAlert(alert.id, widget.user.role),
          onIgnore: () => _controller.ignoreAlert(alert.id, widget.user.role),
          onCreateWorkOrder: () =>
              _controller.createWorkOrder(alert.id, widget.user.role),
          onSilenceBuzzer: () => _silenceCurrentAlertSound(
            zoneOverride: alert.zone,
          ),
        ),
      ),
    );
  }

  Future<void> _showProfileDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('User: ${widget.user.username}'),
            const SizedBox(height: 6),
            Text('Role: ${widget.user.role.label}'),
            const SizedBox(height: 6),
            Text(
              'Push Status: ${(_pushToken?.isNotEmpty ?? false) ? 'Enabled' : 'Permission Required'}',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _setupPushNotifications({
    bool userInitiated = false,
    bool forceRefreshToken = false,
  }) async {
    if (forceRefreshToken) {
      try {
        await FirebaseMessaging.instance.deleteToken();
      } catch (_) {
        // Ignore delete-token failures; we'll still try to fetch a fresh token.
      }
      if (mounted) {
        setState(() => _pushToken = null);
      } else {
        _pushToken = null;
      }
    }

    if (!forceRefreshToken && _pushToken != null && _pushToken!.isNotEmpty) {
      return;
    }

    String? token;
    try {
      token = await _pushService
          .initializeAndGetToken(userInitiated: userInitiated)
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _pushStatusMessage =
            'FCM init timeout: browser permission/token request did not finish';
      });
      return;
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _pushStatusMessage = 'FCM init exception: $error';
      });
      if (_pushService.lastFailureRetryable) {
        _schedulePushSetupRetry();
      }
      return;
    }

    if (!mounted) return;
    if (token == null || token.isEmpty) {
      final message = _normalizePushStatusMessage(
        _pushService.lastErrorMessage ?? 'FCM token unavailable',
      );
      setState(() => _pushStatusMessage = message);
      if (_pushService.lastFailureRetryable) {
        _schedulePushSetupRetry();
      }
      return;
    }

    _pushRetryTimer?.cancel();
    _pushRetryCount = 0;
    setState(() {
      _pushToken = token;
      _pushStatusMessage = 'FCM token ready';
    });
    _bindFcmForegroundPopup();

    final apiBaseUrl = widget.apiBaseUrl;
    if (apiBaseUrl == null || apiBaseUrl.isEmpty) return;

    try {
      await _pushService.registerToken(
        apiBaseUrl: apiBaseUrl,
        token: token,
        userId: widget.user.username,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() =>
          _pushStatusMessage = 'FCM token acquired, backend register failed');
    }
  }

  Future<void> _manualRetryPushSetup() async {
    if (!mounted) return;
    _pushRetryTimer?.cancel();
    _pushRetryCount = 0;
    setState(() => _pushStatusMessage = 'Refreshing notification channel...');
    await _setupPushNotifications(
      userInitiated: true,
      forceRefreshToken: true,
    );
  }

  Future<void> _manualRetryPushSetupWithFeedback() async {
    if (_manualPushBusy) return;
    setState(() => _manualPushBusy = true);
    await _manualRetryPushSetup();
    if (!mounted) return;
    setState(() => _manualPushBusy = false);
    final status = _pushStatusMessage ?? 'Notification action completed.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(status)),
    );
  }

  Future<void> _manualRefreshWithFeedback() async {
    if (_manualRefreshBusy) return;
    setState(() => _manualRefreshBusy = true);
    await _controller.manualRefresh();
    if (!mounted) return;
    setState(() {
      _manualRefreshBusy = false;
      _refreshToken += 1;
    });

    final err = _controller.errorMessage;
    final text =
        err == null ? 'Cloud sync finished.' : 'Cloud sync failed: $err';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  void _schedulePushSetupRetry() {
    if (!mounted) return;
    if (_pushRetryCount >= 4) return;

    _pushRetryCount += 1;
    final waitSeconds = 2 * _pushRetryCount;
    _pushRetryTimer?.cancel();
    _pushRetryTimer = Timer(Duration(seconds: waitSeconds), () {
      if (!mounted || (_pushToken?.isNotEmpty ?? false)) return;
      setState(() =>
          _pushStatusMessage = 'FCM reconnecting... ($_pushRetryCount/4)');
      unawaited(_setupPushNotifications());
    });
  }

  String _normalizePushStatusMessage(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('push disabled by config')) {
      return 'Push disabled by config (MQTT mode)';
    }
    if (lower.contains('waiting for user action')) {
      return 'FCM pending permission: click the bell icon to enable notifications';
    }
    if (lower.contains('timeout')) {
      return 'FCM timeout: browser did not return permission/token in time';
    }
    if (lower.contains('token-subscribe-failed') ||
        lower.contains('missing required authentication credential')) {
      return 'Browser push auth credential missing; FCM is disabled in this tab';
    }
    return raw;
  }

  bool _isPushDisabledMessage(String? message) {
    final m = (message ?? '').toLowerCase();
    return m.contains('push disabled by config') || m.contains('mqtt mode');
  }

  void _bindFcmForegroundPopup() {
    _fcmSubscription?.cancel();
    _fcmSubscription = FirebaseMessaging.onMessage.listen((message) {
      if (!mounted) return;
      _showFcmPopup(message);
    });
  }

  Future<void> _showFcmPopup(RemoteMessage message) async {
    if (!_enableInAppAlertPopups) return;
    if (_alertDialogOpen) return;
    if (!_canOpenPopupNow()) return;

    final id = message.messageId ??
        message.data['alertId']?.toString() ??
        '${message.notification?.title}-${message.notification?.body}-${DateTime.now().millisecondsSinceEpoch ~/ 10000}';
    if (_shownFcmPopups.contains(id)) return;
    _shownFcmPopups.add(id);
    _alertDialogOpen = true;
    _lastPopupShownAt = DateTime.now();

    final title = message.notification?.title ?? 'Alertrix Notification';
    final body = message.notification?.body ?? 'A new alert has been received.';
    final zone = message.data['zone']?.toString();
    final severity =
        (message.data['severity']?.toString() ?? 'WARNING').toUpperCase();
    final color = severity == 'CRITICAL'
        ? const Color(0xFFC93C3C)
        : const Color(0xFFE09D25);
    unawaited(_startAlertFeedbackLoop(_sensorLevelFromSeverityText(severity)));

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.notifications_active_rounded, color: color),
              const SizedBox(width: 8),
              const Text('Push Alert'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(body),
              const SizedBox(height: 8),
              Text(
                'Severity: $severity',
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Later'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _silenceCurrentAlertSound(zoneOverride: zone);
              },
              child: const Text('Silence'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                setState(() => _selectedIndex = 2);
              },
              child: const Text('Open Incident Queue'),
            ),
          ],
        ),
      );
    } finally {
      await _stopAlertSoundLoop();
      _alertDialogOpen = false;
    }
  }

  String _titleByIndex(int index) {
    switch (index) {
      case 0:
        return 'Response Overview';
      case 1:
        return 'Situation Trends';
      case 2:
        return 'Incident Queue';
      case 3:
        return 'Work Orders';
      case 5:
        return 'Admin Management';
      default:
        return 'Response Settings';
    }
  }

  String _adminHeaderUserId() {
    final current = widget.user.username.trim().toLowerCase();
    if (current == "admin") return "admin@alertrix.local";
    return current;
  }

  void _maybeShowAlertPopup(MonitoringSnapshot snapshot) {
    if (!_enableInAppAlertPopups) return;
    if (!_alertPopupPrimed) return;
    if (_alertDialogOpen) return;
    if (!mounted) return;
    if (!_canOpenPopupNow()) return;

    AlertEvent? target;
    for (final alert in snapshot.alerts) {
      if (alert.severity != SensorLevel.critical) continue;
      if (_shownAlertPopups.contains(alert.id)) continue;
      if (!_isAlertWithinPopupWindow(alert.timestamp)) continue;
      target = alert;
      break;
    }
    if (target == null) {
      for (final alert in snapshot.alerts) {
        if (alert.severity != SensorLevel.warning) continue;
        if (_shownAlertPopups.contains(alert.id)) continue;
        if (!_isAlertWithinPopupWindow(alert.timestamp)) continue;
        target = alert;
        break;
      }
    }

    final popupTarget = target;
    if (popupTarget == null) return;
    if (_shownAlertPopups.contains(popupTarget.id)) return;

    _shownAlertPopups.add(popupTarget.id);
    _alertDialogOpen = true;
    _lastPopupShownAt = DateTime.now();
    unawaited(_startAlertFeedbackLoop(popupTarget.severity));

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await showDialog<void>(
          context: context,
          barrierDismissible: true,
          builder: (dialogContext) {
            final severity = popupTarget.severity;
            final color = severity.color;
            return AlertDialog(
              titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
              title: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: color),
                  const SizedBox(width: 8),
                  Text('${severity.label} Alert'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(popupTarget.title,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text('Location: ${popupTarget.zone}'),
                  const SizedBox(height: 4),
                  Text('Time: ${_formatAlertTime(popupTarget.timestamp)}'),
                  const SizedBox(height: 8),
                  const Text(
                    'Recommended: Open Incident Queue and acknowledge this incident.',
                    style: TextStyle(color: Color(0xFF5F727A)),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Later'),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    await _silenceCurrentAlertSound(
                      zoneOverride: popupTarget.zone,
                    );
                  },
                  child: const Text('Silence'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    setState(() => _selectedIndex = 2);
                  },
                  child: const Text('Open Incident Queue'),
                ),
              ],
            );
          },
        );
      } finally {
        await _stopAlertSoundLoop();
        _alertDialogOpen = false;
      }
    });
  }

  void _primeExistingAlerts(MonitoringSnapshot snapshot) {
    if (_alertPopupPrimed) return;
    for (final alert in snapshot.alerts) {
      _shownAlertPopups.add(alert.id);
    }
    _alertPopupPrimed = true;
  }

  String _formatAlertTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  SensorLevel _sensorLevelFromSeverityText(String severityText) {
    return switch (severityText.toUpperCase()) {
      'CRITICAL' => SensorLevel.critical,
      'WARNING' => SensorLevel.warning,
      _ => SensorLevel.normal,
    };
  }

  Future<void> _startAlertFeedbackLoop(SensorLevel level) async {
    if (level == SensorLevel.normal) return;
    _activeAlertSoundLevel = level;
    _alertSoundInterval = level == SensorLevel.critical
        ? const Duration(seconds: 4)
        : const Duration(seconds: 9);
    await _primeAlertAudioByInteraction();
    await _ensureNotificationSettingsFresh();
    if (!_shouldTriggerByPushRule(level)) return;

    await _triggerAlertFeedback(level, announce: true);
    if (!_alertSoundEnabled) return;

    _alertSoundLoopTimer?.cancel();
    _alertSoundLoopTimer = Timer.periodic(_alertSoundInterval, (timer) {
      unawaited(_tickAlertSoundLoop());
    });
  }

  Future<void> _tickAlertSoundLoop() async {
    if (!mounted || !_alertDialogOpen || !_alertSoundEnabled) {
      await _stopAlertSoundLoop();
      return;
    }
    await _playAlertSound(_activeAlertSoundLevel, announce: false);
  }

  Future<void> _stopAlertSoundLoop() async {
    _alertSoundLoopTimer?.cancel();
    _alertSoundLoopTimer = null;
    if (kIsWeb) {
      await alert_audio.stopAlertTone();
    }
  }

  Future<void> _triggerAlertFeedback(SensorLevel level,
      {required bool announce}) async {
    if (level == SensorLevel.normal) return;
    await _ensureNotificationSettingsFresh();
    if (!_shouldTriggerByPushRule(level)) return;

    await _playAlertSound(level, announce: announce);

    if (_supportsMobileHaptics()) {
      try {
        if (level == SensorLevel.critical) {
          await HapticFeedback.heavyImpact();
          await Future.delayed(const Duration(milliseconds: 140));
          await HapticFeedback.heavyImpact();
        } else {
          await HapticFeedback.vibrate();
        }
      } catch (_) {
        // Ignore platform vibration limitations.
      }
    }
  }

  Future<void> _playAlertSound(SensorLevel level,
      {required bool announce}) async {
    if (!_alertSoundEnabled) return;
    try {
      if (kIsWeb) {
        await alert_audio.playAlertTone(
          severityLabel: level.label.toUpperCase(),
          announce: announce,
        );
      } else {
        await SystemSound.play(SystemSoundType.alert);
      }
    } catch (_) {
      // Ignore platform sound limitations.
    }
  }

  bool _shouldTriggerByPushRule(SensorLevel level) {
    switch (_pushRule) {
      case 'Disabled':
        return false;
      case 'Critical only':
        return level == SensorLevel.critical;
      default:
        return level == SensorLevel.warning || level == SensorLevel.critical;
    }
  }

  bool _supportsMobileHaptics() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<void> _ensureNotificationSettingsFresh() async {
    final last = _lastNotificationSettingSync;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 20)) {
      return;
    }
    await _loadNotificationSettings();
  }

  Future<void> _loadNotificationSettings() async {
    final apiBaseUrl = widget.apiBaseUrl;
    if (apiBaseUrl == null || apiBaseUrl.trim().isEmpty) return;
    try {
      final resp = await http.get(
        Uri.parse('$apiBaseUrl/api/settings/notifications'),
        headers: {
          'x-user-id': widget.user.username,
          'x-user-role': widget.user.role.label,
        },
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) return;
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _pushRule = json['pushRule']?.toString() ?? _pushRule;
        _alertSoundEnabled =
            (json['alertSoundEnabled'] as bool?) ?? _alertSoundEnabled;
        _lastNotificationSettingSync = DateTime.now();
      });
    } catch (_) {
      // Keep local defaults silently when API is unavailable.
    }
  }

  Future<void> _primeAlertAudioByInteraction() async {
    if (!kIsWeb || _webAudioPrimed) return;
    _webAudioPrimed = true;
    await alert_audio.primeAlertAudio();
  }

  Future<void> _silenceCurrentAlertSound({String? zoneOverride}) async {
    await _stopAlertSoundLoop();
    final zone = zoneOverride?.trim().isNotEmpty == true
        ? zoneOverride!.trim()
        : _resolveActiveZoneForSilence();
    var message = 'Alert sound stopped.';
    if (_controller.usingRemoteApi) {
      try {
        await _controller.silenceBuzzer(
          zone: zone,
          role: widget.user.role,
          requestedBy: widget.user.username,
          durationSeconds: 120,
        );
        message = 'Alert sound stopped. Cloud buzzer silenced for 120s.';
      } catch (_) {
        message = 'Alert sound stopped. Cloud buzzer silence failed.';
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _resolveActiveZoneForSilence() {
    final snapshot = _controller.snapshot;
    if (snapshot == null) return _defaultZone;
    for (final alert in snapshot.alerts) {
      if (alert.severity == SensorLevel.critical &&
          alert.zone.trim().isNotEmpty) {
        return alert.zone.trim();
      }
    }
    for (final alert in snapshot.alerts) {
      if (alert.zone.trim().isNotEmpty) return alert.zone.trim();
    }
    return _defaultZone;
  }

  bool _isAlertWithinPopupWindow(DateTime timestamp) {
    final age = DateTime.now().difference(timestamp);
    return age >= Duration.zero && age <= _popupWindow;
  }

  bool _canOpenPopupNow() {
    final last = _lastPopupShownAt;
    if (last == null) return true;
    return DateTime.now().difference(last) >= _popupWindow;
  }
}

class _NavItem {
  const _NavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

enum _TopStatusTone { healthy, warning, danger, neutral }
