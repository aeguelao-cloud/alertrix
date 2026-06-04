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
import '../utils/fcm_web_probe_stub.dart'
    if (dart.library.html) '../utils/fcm_web_probe_web.dart' as web_probe;
import '../widgets/ui_kit.dart';
import 'alert_detail_page.dart';
import 'admin_device_management_page.dart';
import 'alerts_page.dart';
import 'admin_management_page.dart';
import 'dashboard_page.dart';
import 'settings_page.dart';
import 'trends_page.dart';
import 'user_devices_page.dart';
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

class _HomeShellPageState extends State<HomeShellPage>
    with WidgetsBindingObserver {
  // Enable in-app alert popups so critical/warning messages are visible even
  // when browser/system push notifications are not shown.
  static const bool _enableInAppAlertPopups = true;

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
  String _pushRule = 'Warning + Critical';
  bool _alertSoundEnabled = true;
  DateTime? _lastNotificationSettingSync;
  bool _webAudioPrimed = false;
  bool _webAutoPermissionAttempted = false;
  bool _webAutoPermissionInFlight = false;
  bool _soundConsentPromptShown = false;
  bool _soundConsentPromptOpen = false;
  Timer? _pushRetryTimer;
  int _pushRetryCount = 0;
  bool _manualRefreshBusy = false;
  bool _manualPushBusy = false;
  bool _deviceBuzzerControlBusy = false;
  bool _deviceBuzzerStateFetchInFlight = false;
  bool _deviceBuzzerSilenced = false;
  String? _deviceBuzzerStateZone;
  int _refreshToken = 0;
  DateTime? _lastPopupShownAt;
  DateTime? _lastHiddenAlertNotificationAt;
  DateTime? _lastDeviceBuzzerStateFetchAt;
  SensorLevel? _activePageAlertLevel;
  bool _pageAlertSoundStopped = false;
  static const Duration _alertFeedbackWindow = Duration(seconds: 30);
  static const Duration _popupCooldown = _alertFeedbackWindow;
  static const Duration _recentAlertPopupWindow = Duration(minutes: 5);
  static const Duration _hiddenAlertNotificationCooldown = Duration(minutes: 1);
  static const Duration _deviceBuzzerStateRefreshGap = Duration(seconds: 5);
  static const String _defaultZone = 'Zone A - Pump Station';
  static const Color _sideNavBg = Color(0xFF102A34);
  static const Color _sideNavDivider = Color(0xFF1E3F4D);
  static const Color _sideNavAccent = Color(0xFF67D2E0);
  static const Color _sideNavMuted = Color(0xFF9EB8C3);
  static const Color _sideNavText = Color(0xFFE7F3F7);
  static const Color _sideNavSelected = Color(0xFF1A5667);
  bool get _isAdmin => widget.user.role == UserRole.admin;
  static const int _navDashboard = 0;
  static const int _navTrends = 1;
  static const int _navAlerts = 2;
  static const int _navWorkOrders = 3;
  static const int _navDevices = 4;
  static const int _navSettings = 5;
  static const int _navAdminManagement = 6;

  List<int> get _visibleNavIndexes {
    final base = _isAdmin
        ? const <int>[
            _navDashboard,
            _navTrends,
            _navAlerts,
            _navWorkOrders,
            _navDevices,
            _navSettings,
            _navAdminManagement,
          ]
        : const <int>[
            _navDashboard,
            _navTrends,
            _navAlerts,
            _navDevices,
            _navSettings,
          ];
    final seen = <int>{};
    return base.where(seen.add).toList(growable: false);
  }

  String get _alertsNavLabel => 'Active Incidents';
  String get _settingsNavLabel =>
      _isAdmin ? 'Response Settings' : 'Notification Settings';
  String get _devicesNavLabel => _isAdmin ? 'Device Management' : 'My Devices';
  String get _shellName => _isAdmin ? 'Alertrix Admin' : 'Alertrix User';

  List<_NavItem> get _navItems => [
        _NavItem(
          icon: Icons.dashboard_outlined,
          label: _isAdmin ? 'Response Overview' : 'Dashboard',
        ),
        const _NavItem(
          icon: Icons.insights_outlined,
          label: 'Situation Trends',
        ),
        _NavItem(icon: Icons.warning_amber_outlined, label: _alertsNavLabel),
        const _NavItem(icon: Icons.assignment_outlined, label: 'Work Orders'),
        _NavItem(icon: Icons.memory_outlined, label: _devicesNavLabel),
        _NavItem(icon: Icons.settings_outlined, label: _settingsNavLabel),
        const _NavItem(
          icon: Icons.admin_panel_settings_outlined,
          label: 'Admin Management',
        ),
      ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.removeObserver(this);
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_resumePageAlertSoundIfNeeded());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final snapshot = _controller.snapshot;
        final compact = _isCompactLayout(context);
        return Listener(
          onPointerDown:
              kIsWeb ? (_) => unawaited(_handleWebPointerDown()) : null,
          child: compact
              ? _buildCompactScaffold(snapshot)
              : _buildDesktopScaffold(snapshot),
        );
      },
    );
  }

  bool _isCompactLayout(BuildContext context) {
    return uiIsCompactLayout(context);
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
        leading: IconButton(
          tooltip: 'All pages',
          onPressed: _openCompactNavigationSheet,
          icon: const Icon(Icons.menu_rounded),
        ),
        title: _buildCompactTopBarTitle(),
        actions: [
          _buildDeviceBuzzerActionButton(compact: true),
          _buildRefreshActionButton(),
          _buildPushActionButton(),
          _buildUserMenuButton(),
        ],
      ),
      body: _buildShellBody(snapshot, compact: true),
      bottomNavigationBar: _buildCompactBottomNavigation(),
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
      final compactPadding = uiPagePadding(context);
      return Column(
        children: [
          Container(
            margin: EdgeInsets.fromLTRB(
              compactPadding.left,
              UiSpace.gap,
              compactPadding.right,
              0,
            ),
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
          SizedBox(height: uiSectionSpacing(context)),
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
        color: _sideNavBg,
        borderRadius: BorderRadius.circular(UiRadius.big),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1220303A),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: _buildNavigationMenu(closeOnTap: false),
    );
  }

  Widget _buildNavigationMenu({required bool closeOnTap}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A4857),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: _sideNavAccent,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _shellName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _sideNavText,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: _sideNavDivider),
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
                  onTap: () =>
                      _selectNavIndex(navIndex, closeDrawer: closeOnTap),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? _sideNavSelected : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          item.icon,
                          color: selected ? _sideNavAccent : _sideNavMuted,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          item.label,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: selected ? _sideNavAccent : _sideNavText,
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

  List<int> get _compactPrimaryNavIndexes {
    const preferred = <int>[
      _navDashboard,
      _navAlerts,
      _navDevices,
      _navSettings,
    ];
    final items = <int>[];
    for (final navIndex in preferred) {
      if (_visibleNavIndexes.contains(navIndex) && !items.contains(navIndex)) {
        items.add(navIndex);
      }
    }
    if (items.length < 4) {
      for (final navIndex in _visibleNavIndexes) {
        if (items.contains(navIndex)) continue;
        items.add(navIndex);
        if (items.length >= 4) break;
      }
    }
    return items;
  }

  int get _compactSelectedBarIndex {
    final primary = _compactPrimaryNavIndexes;
    final selected = primary.indexOf(_selectedIndex);
    if (selected >= 0) return selected;
    return primary.length;
  }

  Future<void> _openCompactNavigationSheet() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _sideNavBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: _sideNavMuted,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _buildNavigationMenu(closeOnTap: true),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCompactBottomNavigation() {
    final primary = _compactPrimaryNavIndexes;
    final destinations = [
      ...primary.map(
        (navIndex) => NavigationDestination(
          icon: Icon(_navItems[navIndex].icon),
          label: _navItems[navIndex].label,
        ),
      ),
      const NavigationDestination(
        icon: Icon(Icons.grid_view_rounded),
        label: 'More',
      ),
    ];
    return NavigationBar(
      selectedIndex: _compactSelectedBarIndex,
      onDestinationSelected: (destinationIndex) {
        if (destinationIndex < primary.length) {
          _selectNavIndex(primary[destinationIndex]);
          return;
        }
        unawaited(_openCompactNavigationSheet());
      },
      destinations: destinations,
    );
  }

  void _handleControllerSideEffects() {
    if (!_enableInAppAlertPopups) return;
    final snapshot = _controller.snapshot;
    if (snapshot == null || !mounted) return;
    _updateActivePageAlertState(snapshot);
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
                  color: UiColors.textMuted,
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
        _buildDeviceBuzzerActionButton(),
        const SizedBox(width: 6),
        _buildRefreshActionButton(),
        _buildPushActionButton(),
        _buildUserMenuButton(),
      ],
    );
  }

  Widget _buildCompactTopBarTitle() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Alertrix',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        Text(
          _titleByIndex(_selectedIndex),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            color: UiColors.textMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildTopStatusPills() {
    final ready = (_pushToken?.isNotEmpty ?? false);
    final disabled = _isPushDisabledMessage(_pushStatusMessage);
    final hasCloudError = _controller.errorMessage != null;
    final lastSync = _controller.lastSuccessfulSyncAt;

    final cloudLabel = hasCloudError ? 'Degraded' : 'Normal';
    final cloudTone =
        hasCloudError ? _TopStatusTone.warning : _TopStatusTone.healthy;
    final apiLabel = _controller.usingRemoteApi ? 'Connected' : 'No Data';
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

  Widget _buildDeviceBuzzerActionButton({bool compact = false}) {
    final hasActiveAlert =
        _highestActiveAlertLevel(_controller.snapshot?.alerts ?? const []) !=
            SensorLevel.normal;
    if (!hasActiveAlert) return const SizedBox.shrink();

    final onPressed = (_deviceBuzzerControlBusy || !_controller.usingRemoteApi)
        ? null
        : _toggleDeviceBuzzerFromButton;
    final enabled = _deviceBuzzerSilenced;
    final label = enabled ? 'Enable Buzzer' : 'Silence Buzzer';
    final tooltip = enabled ? 'Enable Device Buzzer' : 'Silence Device Buzzer';
    final icon = _deviceBuzzerControlBusy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(enabled ? Icons.volume_up_rounded : Icons.volume_off_rounded);
    final foreground = enabled ? UiColors.brand : UiColors.danger;
    final border = enabled ? const Color(0xFFB9D7DD) : const Color(0xFFF2B2B2);

    if (compact) {
      return IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: icon,
      );
    }

    return Tooltip(
      message: tooltip,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon,
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          backgroundColor: UiColors.surface,
          side: BorderSide(color: border),
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(UiRadius.button),
          ),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
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
          const Color(0xFFE8F7EE),
          UiColors.healthy,
        ),
      _TopStatusTone.warning => (
          const Color(0xFFFFF4DF),
          UiColors.warning,
        ),
      _TopStatusTone.danger => (
          const Color(0xFFFFECEC),
          UiColors.danger,
        ),
      _TopStatusTone.neutral => (
          const Color(0xFFEFF4F7),
          UiColors.neutral,
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
                size: 48, color: UiColors.neutral),
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
              style: const TextStyle(color: UiColors.textMuted),
            ),
            if (_controller.lastSuccessfulSyncAt != null) ...[
              const SizedBox(height: 4),
              Text(
                'Last successful sync: ${_formatSyncTime(_controller.lastSuccessfulSyncAt!)}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: UiColors.textMuted),
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
          isAdminView: _isAdmin,
          alertsLabel: _alertsNavLabel,
          onOpenAlertDetail: _openAlertDetail,
          onNavigateToAlerts: () => setState(() => _selectedIndex = 2),
          onNavigateToDevices: () =>
              setState(() => _selectedIndex = _navDevices),
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
          apiBaseUrl: widget.apiBaseUrl,
          onOpenAlertDetail: _openAlertDetail,
          onAcknowledgeVisible: (ids) =>
              _controller.confirmAlerts(ids, widget.user.role),
          onLoadMoreIncidents: _controller.loadMoreActiveIncidents,
          onLeaveIncidentQueue: _controller.resetActiveIncidentPagination,
        );
      case 3:
        if (_isAdmin) {
          return WorkOrdersPage(apiBaseUrl: widget.apiBaseUrl);
        }
        return UserDevicesPage(snapshot: snapshot);
      case 4:
        if (_isAdmin) {
          return AdminDeviceManagementPage(
            snapshot: snapshot,
            apiBaseUrl: widget.apiBaseUrl,
            actorUserId: _adminHeaderUserId(),
          );
        }
        return UserDevicesPage(snapshot: snapshot);
      case 5:
        return SettingsPage(
          username: widget.user.username,
          role: widget.user.role,
          onNavigateBackToDashboard: () => setState(() => _selectedIndex = 0),
          apiBaseUrl: widget.apiBaseUrl,
          onNotificationSettingsChanged: _loadNotificationSettings,
        );
      case 6:
        if (_isAdmin) {
          return AdminManagementPage(
            apiBaseUrl: widget.apiBaseUrl,
            adminHeaderUserId: _adminHeaderUserId(),
          );
        }
        return AlertsPage(
          snapshot: snapshot,
          role: widget.user.role,
          apiBaseUrl: widget.apiBaseUrl,
          onOpenAlertDetail: _openAlertDetail,
          onAcknowledgeVisible: (ids) =>
              _controller.confirmAlerts(ids, widget.user.role),
          onLoadMoreIncidents: _controller.loadMoreActiveIncidents,
          onLeaveIncidentQueue: _controller.resetActiveIncidentPagination,
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
          onResolve: () => _controller.resolveAlert(alert.id, widget.user.role),
          onIgnore: () => _controller.ignoreAlert(alert.id, widget.user.role),
          onCreateWorkOrder: () =>
              _controller.createWorkOrder(alert.id, widget.user.role),
          onSilenceBuzzer: () => _toggleDeviceBuzzerFromButton(
            zoneOverride: alert.zone,
          ),
          deviceBuzzerSilenced: _deviceBuzzerSilenced,
          onLoadIncidentEvents: () => _controller.fetchIncidentEvents(alert.id),
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
      return 'FCM pending permission: allow browser notifications when prompted';
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
        '${message.notification?.title}-${message.notification?.body}-${DateTime.now().millisecondsSinceEpoch ~/ _alertFeedbackWindow.inMilliseconds}';
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
    unawaited(_showHiddenAlertNotification(
      title: _pushPopupTitle(title: title, body: body, severity: severity),
      body: body,
      severity: _sensorLevelFromSeverityText(severity),
      tag: id,
    ));
    final level = _sensorLevelFromSeverityText(severity);
    unawaited(_startAlertFeedbackLoop(
      level,
      announcementText:
          '${level.label} alert. ${_pushPopupTitle(title: title, body: body, severity: severity)}. $body',
    ));

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.notifications_active_rounded, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _pushPopupTitle(title: title, body: body, severity: severity),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
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
                await _stopPageAlertSound();
              },
              child: const Text('Stop Page Sound'),
            ),
            TextButton(
              onPressed: () async {
                await _toggleDeviceBuzzerFromButton(zoneOverride: zone);
              },
              child: Text(_deviceBuzzerSilenced
                  ? 'Enable Device Buzzer'
                  : 'Silence Device Buzzer'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                setState(() => _selectedIndex = 2);
              },
              child: Text('Open $_alertsNavLabel'),
            ),
          ],
        ),
      );
    } finally {
      _alertDialogOpen = false;
    }
  }

  String _titleByIndex(int index) {
    switch (index) {
      case 0:
        return _isAdmin ? 'Response Overview' : 'Dashboard';
      case 1:
        return 'Situation Trends';
      case 2:
        return _alertsNavLabel;
      case 3:
        return _isAdmin ? 'Work Orders' : _devicesNavLabel;
      case 4:
        return _devicesNavLabel;
      case 6:
        return 'Admin Management';
      default:
        return _settingsNavLabel;
    }
  }

  String _adminHeaderUserId() {
    final current = widget.user.username.trim().toLowerCase();
    if (current == "admin") return "admin@alertrix.local";
    return current;
  }

  void _maybeShowAlertPopup(MonitoringSnapshot snapshot) {
    if (!_enableInAppAlertPopups) return;
    if (_alertDialogOpen) return;
    if (!mounted) return;
    if (!_alertPopupPrimed) return;
    if (!_canOpenPopupNow()) return;

    AlertEvent? target;
    for (final alert in snapshot.alerts) {
      if (alert.severity != SensorLevel.critical) continue;
      if (!_isAlertWithinPopupWindow(alert.timestamp)) continue;
      if (_shownAlertPopups.contains(_alertPopupKey(alert))) continue;
      target = alert;
      break;
    }
    if (target == null) {
      for (final alert in snapshot.alerts) {
        if (alert.severity != SensorLevel.warning) continue;
        if (!_isAlertWithinPopupWindow(alert.timestamp)) continue;
        if (_shownAlertPopups.contains(_alertPopupKey(alert))) continue;
        target = alert;
        break;
      }
    }

    final popupTarget = target;
    if (popupTarget == null) return;
    final popupKey = _alertPopupKey(popupTarget);
    if (_shownAlertPopups.contains(popupKey)) return;

    unawaited(_showHiddenAlertNotification(
      title: _alertDialogTitle(popupTarget),
      body: '${popupTarget.zone}: ${popupTarget.title}',
      severity: popupTarget.severity,
      tag: popupKey,
    ));
    _shownAlertPopups.add(popupKey);
    _alertDialogOpen = true;
    _lastPopupShownAt = DateTime.now();
    unawaited(_startAlertFeedbackLoop(
      popupTarget.severity,
      announcementText: _alertAnnouncementText(popupTarget),
    ));

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
                  Expanded(
                    child: Text(
                      _alertDialogTitle(popupTarget),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
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
                  Text(
                    'Recommended Action: ${_recommendedActionForIncident(popupTarget)}',
                    style: const TextStyle(color: UiColors.textMuted),
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
                    await _stopPageAlertSound();
                  },
                  child: const Text('Stop Page Sound'),
                ),
                TextButton(
                  onPressed: () async {
                    await _toggleDeviceBuzzerFromButton(
                      zoneOverride: popupTarget.zone,
                    );
                  },
                  child: Text(_deviceBuzzerSilenced
                      ? 'Enable Device Buzzer'
                      : 'Silence Device Buzzer'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    setState(() => _selectedIndex = 2);
                  },
                  child: Text('Open $_alertsNavLabel'),
                ),
              ],
            );
          },
        );
      } finally {
        _alertDialogOpen = false;
      }
    });
  }

  String _formatAlertTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  String _alertDialogTitle(AlertEvent alert) {
    final eventTitle = _humanReadableAlertEvent(alert.title);
    return '$eventTitle - ${alert.severity.label}';
  }

  String _pushPopupTitle({
    required String title,
    required String body,
    required String severity,
  }) {
    final eventTitle = _humanReadableAlertEvent('$title $body');
    final level = severity.toUpperCase() == 'CRITICAL' ? 'Critical' : 'Warning';
    return '$eventTitle - $level';
  }

  String _humanReadableAlertEvent(String raw) {
    final text = raw.toLowerCase();
    if (text.contains('vibration')) {
      return 'Vibration Threshold Exceeded';
    }
    if (text.contains('waterlevel') || text.contains('water level')) {
      return 'Water Level Threshold Exceeded';
    }
    if (text.contains('temperature')) {
      return 'Temperature Threshold Exceeded';
    }
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'Sensor Threshold Exceeded';
    return trimmed
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1).toLowerCase())
        .join(' ');
  }

  SensorLevel _sensorLevelFromSeverityText(String severityText) {
    return switch (severityText.toUpperCase()) {
      'CRITICAL' => SensorLevel.critical,
      'WARNING' => SensorLevel.warning,
      _ => SensorLevel.normal,
    };
  }

  String _recommendedActionForIncident(AlertEvent alert) {
    final title = alert.title.toLowerCase();
    if (title.contains('water') && alert.severity == SensorLevel.critical) {
      return 'Avoid ${alert.zone} and wait for further instructions.';
    }
    if (alert.severity == SensorLevel.critical) {
      return 'Move away from the affected area immediately.';
    }
    return 'Stay alert and avoid entering ${alert.zone} until the alert clears.';
  }

  String _alertAnnouncementText(AlertEvent alert) {
    return '${alert.severity.label} alert. ${_alertDialogTitle(alert)} at ${alert.zone}. ${_recommendedActionForIncident(alert)}';
  }

  Future<void> _startAlertFeedbackLoop(
    SensorLevel level, {
    String? announcementText,
  }) async {
    if (level == SensorLevel.normal) return;
    _activePageAlertLevel = level;
    _pageAlertSoundStopped = false;
    await _primeAlertAudioByInteraction();
    await _ensureNotificationSettingsFresh();
    if (!_shouldTriggerByPushRule(level)) return;

    await _triggerAlertFeedback(
      level,
      announce: true,
      continuous: true,
      announcementText: announcementText,
    );
  }

  void _updateActivePageAlertState(MonitoringSnapshot snapshot) {
    final level = _highestActiveAlertLevel(snapshot.alerts);
    if (level == SensorLevel.normal) {
      _activePageAlertLevel = null;
      _pageAlertSoundStopped = false;
      _deviceBuzzerSilenced = false;
      unawaited(_stopAlertSoundLoop());
      return;
    }
    _activePageAlertLevel = level;
    unawaited(_refreshDeviceBuzzerStateIfNeeded());
  }

  SensorLevel _highestActiveAlertLevel(Iterable<AlertEvent> alerts) {
    var hasWarning = false;
    for (final alert in alerts) {
      if (alert.status != IncidentStatus.active) continue;
      if (alert.severity == SensorLevel.critical) return SensorLevel.critical;
      if (alert.severity == SensorLevel.warning) hasWarning = true;
    }
    return hasWarning ? SensorLevel.warning : SensorLevel.normal;
  }

  Future<void> _resumePageAlertSoundIfNeeded() async {
    if (!mounted || _pageAlertSoundStopped) return;
    if (kIsWeb && !alert_audio.isAlertPageVisible()) return;
    final level = _activePageAlertLevel ??
        _highestActiveAlertLevel(_controller.snapshot?.alerts ?? const []);
    if (level == SensorLevel.normal) return;
    await _triggerAlertFeedback(level, announce: false, continuous: true);
  }

  Future<void> _showHiddenAlertNotification({
    required String title,
    required String body,
    required SensorLevel severity,
    required String tag,
  }) async {
    if (!kIsWeb) return;
    if (alert_audio.isAlertPageVisible()) return;
    if (!_shouldTriggerByPushRule(severity)) return;
    final last = _lastHiddenAlertNotificationAt;
    if (last != null &&
        DateTime.now().difference(last) < _hiddenAlertNotificationCooldown) {
      return;
    }
    _lastHiddenAlertNotificationAt = DateTime.now();
    await alert_audio.showAlertNotification(
      title: title,
      body: body,
      tag: tag,
      severityLabel: severity.label.toUpperCase(),
    );
  }

  Future<void> _refreshDeviceBuzzerStateIfNeeded({
    bool force = false,
    String? zoneOverride,
  }) async {
    if (!_controller.usingRemoteApi || _deviceBuzzerStateFetchInFlight) return;
    final zone = zoneOverride?.trim().isNotEmpty == true
        ? zoneOverride!.trim()
        : _resolveActiveZoneForSilence();
    final last = _lastDeviceBuzzerStateFetchAt;
    if (!force &&
        last != null &&
        _deviceBuzzerStateZone == zone &&
        DateTime.now().difference(last) < _deviceBuzzerStateRefreshGap) {
      return;
    }

    _deviceBuzzerStateFetchInFlight = true;
    try {
      final state = await _controller.fetchBuzzerSilenceState(zone: zone);
      if (!mounted) return;
      setState(() {
        _deviceBuzzerSilenced = state.silenced;
        _deviceBuzzerStateZone = state.zone;
        _lastDeviceBuzzerStateFetchAt = DateTime.now();
      });
    } catch (_) {
      // Keep the current UI state if the cloud state check fails.
    } finally {
      _deviceBuzzerStateFetchInFlight = false;
    }
  }

  Future<void> _stopAlertSoundLoop() async {
    if (kIsWeb) {
      await alert_audio.stopAlertTone();
    }
  }

  Future<void> _triggerAlertFeedback(
    SensorLevel level, {
    required bool announce,
    bool continuous = false,
    String? announcementText,
  }) async {
    if (level == SensorLevel.normal) return;
    await _ensureNotificationSettingsFresh();
    if (!_shouldTriggerByPushRule(level)) return;

    await _playAlertSound(
      level,
      announce: announce,
      continuous: continuous,
      announcementText: announcementText,
    );

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

  Future<void> _playAlertSound(
    SensorLevel level, {
    required bool announce,
    bool continuous = false,
    String? announcementText,
  }) async {
    if (!_alertSoundEnabled) return;
    try {
      if (kIsWeb) {
        await alert_audio.playAlertTone(
          severityLabel: level.label.toUpperCase(),
          announcementText: announcementText,
          announce: announce,
          continuous: continuous,
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

  Future<void> _handleWebPointerDown() async {
    await _primeAlertAudioByInteraction();
    await _maybeAutoEnablePushPermission();
    await _maybeAskAlertSoundConsent();
  }

  Future<void> _maybeAutoEnablePushPermission() async {
    if (!kIsWeb || !mounted) return;
    if (_webAutoPermissionAttempted || _webAutoPermissionInFlight) return;
    if (_pushToken?.isNotEmpty ?? false) {
      _webAutoPermissionAttempted = true;
      return;
    }

    final permission = web_probe.webNotificationPermission().toLowerCase();
    if (permission == 'denied') {
      _webAutoPermissionAttempted = true;
      return;
    }

    final needsUserDecision =
        permission == 'default' || permission == 'unknown';
    final hasGrantedButNoToken = permission == 'granted';
    if (!needsUserDecision && !hasGrantedButNoToken) {
      return;
    }

    _webAutoPermissionAttempted = true;
    _webAutoPermissionInFlight = true;
    try {
      await _setupPushNotifications(
        userInitiated: true,
        forceRefreshToken: hasGrantedButNoToken,
      );
    } finally {
      _webAutoPermissionInFlight = false;
    }
  }

  Future<void> _maybeAskAlertSoundConsent() async {
    if (!mounted) return;
    if (_soundConsentPromptShown || _soundConsentPromptOpen) return;

    _soundConsentPromptShown = true;
    _soundConsentPromptOpen = true;
    final enableSound = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enable Alert Sound'),
        content: const Text(
          'Would you like to enable warning/critical alert sound for this session?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('No Sound'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Enable Sound'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    try {
      if (enableSound == true) {
        setState(() => _alertSoundEnabled = true);
      } else if (enableSound == false) {
        setState(() => _alertSoundEnabled = false);
      }
    } finally {
      _soundConsentPromptOpen = false;
    }
  }

  Future<void> _stopPageAlertSound({bool showFeedback = true}) async {
    _pageAlertSoundStopped = true;
    await _stopAlertSoundLoop();
    if (!mounted || !showFeedback) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Page alert sound stopped.')),
    );
  }

  Future<void> _toggleDeviceBuzzerFromButton({
    String? zoneOverride,
  }) async {
    if (_deviceBuzzerControlBusy) return;
    if (mounted) {
      setState(() => _deviceBuzzerControlBusy = true);
    } else {
      _deviceBuzzerControlBusy = true;
    }
    try {
      await _setDeviceBuzzerSilenced(
        !_deviceBuzzerSilenced,
        zoneOverride: zoneOverride,
      );
    } finally {
      if (mounted) {
        setState(() => _deviceBuzzerControlBusy = false);
      } else {
        _deviceBuzzerControlBusy = false;
      }
    }
  }

  Future<void> _setDeviceBuzzerSilenced(
    bool silenced, {
    String? zoneOverride,
  }) async {
    final zone = zoneOverride?.trim().isNotEmpty == true
        ? zoneOverride!.trim()
        : _resolveActiveZoneForSilence();
    var message = silenced
        ? 'Device buzzer silence is unavailable.'
        : 'Device buzzer enable is unavailable.';
    if (_controller.usingRemoteApi) {
      try {
        final state = await _controller.setBuzzerSilence(
          zone: zone,
          role: widget.user.role,
          requestedBy: widget.user.username,
          durationSeconds: silenced ? 3600 : 0,
        );
        _deviceBuzzerSilenced = state.silenced;
        _deviceBuzzerStateZone = state.zone;
        _lastDeviceBuzzerStateFetchAt = DateTime.now();
        message = state.silenced
            ? 'Device buzzer silenced for 1 hour.'
            : 'Device buzzer enabled.';
      } catch (_) {
        message = silenced
            ? 'Device buzzer silence failed.'
            : 'Device buzzer enable failed.';
      }
    }
    if (!mounted) return;
    setState(() {});
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

  void _primeExistingAlerts(MonitoringSnapshot snapshot) {
    if (_alertPopupPrimed) return;
    for (final alert in snapshot.alerts) {
      if (_isAlertWithinPopupWindow(alert.timestamp)) continue;
      _shownAlertPopups.add(_alertPopupKey(alert));
    }
    _alertPopupPrimed = true;
  }

  String _alertPopupKey(AlertEvent alert) {
    return '${alert.id}|${alert.severity.name}|${alert.eventCount}|${alert.timestamp.toIso8601String()}';
  }

  bool _isAlertWithinPopupWindow(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.isNegative) return false;
    return diff <= _recentAlertPopupWindow;
  }

  bool _canOpenPopupNow() {
    final last = _lastPopupShownAt;
    if (last == null) return true;
    return DateTime.now().difference(last) >= _popupCooldown;
  }
}

class _NavItem {
  const _NavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

enum _TopStatusTone { healthy, warning, danger, neutral }
