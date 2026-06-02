import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/auth_models.dart';
import '../widgets/dashboard_layout.dart';
import '../widgets/section_header.dart';
import '../widgets/status_badge.dart';
import '../widgets/ui_kit.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.username,
    required this.role,
    required this.onNavigateBackToDashboard,
    this.apiBaseUrl,
    this.onNotificationSettingsChanged,
  });

  final String username;
  final UserRole role;
  final VoidCallback onNavigateBackToDashboard;
  final String? apiBaseUrl;
  final Future<void> Function()? onNotificationSettingsChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const int _hardwareBuzzerSilenceSeconds = 3600;

  double _waterWarning = 70;
  double _waterCritical = 85;
  double _vibrationWarning = 10.0;
  double _vibrationCritical = 14.0;
  double _temperatureWarning = 35;
  double _temperatureCritical = 40;

  int _refreshSeconds = 4;
  String _defaultTrendWindow = '1H';
  String _refreshMode = 'Auto + Manual';
  String _pushRule = 'Warning + Critical';
  bool _alertSoundEnabled = true;
  String _notificationEmail = '';
  String _emailSubscriptionStatus = 'Not configured';
  String _deviceLocation = 'Zone A - Pump Station';
  String _siteName = 'Pilot Monitoring Site';
  String _siteDescription = 'Primary monitoring station';
  bool _loadingNotificationSettings = false;
  bool _loadingDeviceLocation = false;
  bool _silencingHardwareBuzzer = false;

  bool get _isAdmin => widget.role == UserRole.admin;
  bool get _hasApi => (widget.apiBaseUrl ?? '').trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadSystemSettings();
    _loadNotificationSettings();
    _loadDeviceLocation();
  }

  @override
  Widget build(BuildContext context) {
    final sectionSpace = uiSectionSpacing(context);
    if (_isAdmin) {
      return _buildAdminSettingsView(sectionSpace);
    }
    return _buildUserSettingsView(sectionSpace);
  }

  Widget _buildUserSettingsView(double sectionSpace) {
    final receiveWarning = _pushRule == 'Warning + Critical';
    final receiveCritical = _pushRule != 'Disabled';
    return DashboardLayout(
      title: 'Notification Settings',
      subtitle:
          'Manage how you receive warning and critical alerts for your account.',
      trailing: const StatusBadge(
        label: 'User Access',
        tone: UiBadgeTone.stable,
        icon: Icons.person_outline_rounded,
        prominent: true,
      ),
      children: [
        _SettingsMiniGrid(
          items: [
            _SettingsMiniItem(
              label: 'Push Policy',
              value: _pushRule,
              tone: _pushRule == 'Disabled'
                  ? UiBadgeTone.noTelemetry
                  : UiBadgeTone.healthy,
            ),
            _SettingsMiniItem(
              label: 'Alert Sound',
              value: _alertSoundEnabled ? 'Enabled' : 'Disabled',
              tone:
                  _alertSoundEnabled ? UiBadgeTone.healthy : UiBadgeTone.stable,
            ),
            _SettingsMiniItem(
              label: 'Warning Alerts',
              value: receiveWarning ? 'On' : 'Off',
              tone: receiveWarning
                  ? UiBadgeTone.warning
                  : UiBadgeTone.noTelemetry,
            ),
            _SettingsMiniItem(
              label: 'Critical Alerts',
              value: receiveCritical ? 'On' : 'Off',
              tone: receiveCritical
                  ? UiBadgeTone.critical
                  : UiBadgeTone.noTelemetry,
            ),
          ],
        ),
        SizedBox(height: sectionSpace),
        const SectionHeader(
          title: 'Notification Settings',
          subtitle: 'Email, push, and alert sound preferences.',
          icon: Icons.notifications_active_rounded,
        ),
        _ConfigTile(
          icon: Icons.alternate_email_outlined,
          title: 'Email notification',
          summary: _notificationEmail.isEmpty
              ? 'Not configured'
              : '$_notificationEmail ($_emailSubscriptionStatus)',
          actionLabel: 'Manage',
          enabled: true,
          onTap: _editNotificationEmail,
        ),
        _ConfigTile(
          icon: Icons.notifications_active_outlined,
          title: 'Push notification',
          summary: _pushRule,
          actionLabel: 'Manage',
          enabled: true,
          onTap: _editPushNotifications,
        ),
        _ConfigTile(
          icon: Icons.volume_up_outlined,
          title: 'Alert sound',
          summary: _loadingNotificationSettings
              ? 'Syncing...'
              : (_alertSoundEnabled ? 'Enabled' : 'Disabled'),
          actionLabel: 'Manage',
          enabled: true,
          onTap: _editAlertSound,
        ),
        _ConfigTile(
          icon: Icons.warning_amber_outlined,
          title: 'Receive warning alerts',
          summary: receiveWarning ? 'Enabled' : 'Disabled',
          actionLabel: 'Manage',
          enabled: true,
          onTap: _editPushNotifications,
        ),
        _ConfigTile(
          icon: Icons.crisis_alert_outlined,
          title: 'Receive critical alerts',
          summary: receiveCritical ? 'Enabled' : 'Disabled',
          actionLabel: 'Manage',
          enabled: true,
          onTap: _editPushNotifications,
        ),
        SizedBox(height: sectionSpace),
        const SectionHeader(
          title: 'Account Profile',
          subtitle: 'Read-only account context for this notification profile.',
          icon: Icons.account_circle_outlined,
        ),
        _ConfigTile(
          icon: Icons.badge_outlined,
          title: 'Account role',
          summary: widget.role.label,
          actionLabel: '',
          enabled: false,
        ),
        _ConfigTile(
          icon: Icons.person_outline,
          title: 'Account ID',
          summary: widget.username,
          actionLabel: '',
          enabled: false,
        ),
        _ConfigTile(
          icon: Icons.place_outlined,
          title: 'Assigned zone',
          summary: _loadingDeviceLocation ? 'Syncing...' : _deviceLocation,
          actionLabel: '',
          enabled: false,
        ),
      ],
    );
  }

  Widget _buildAdminSettingsView(double sectionSpace) {
    final thresholdRisk = _temperatureCritical >= 45 || _waterCritical >= 90
        ? UiBadgeTone.critical
        : UiBadgeTone.warning;
    final pushTone = _pushRule == 'Disabled'
        ? UiBadgeTone.noTelemetry
        : (_pushRule == 'Critical only'
            ? UiBadgeTone.warning
            : UiBadgeTone.healthy);
    final dataSourceTone = _hasApi ? UiBadgeTone.healthy : UiBadgeTone.warning;
    return DashboardLayout(
      title: 'Response Settings',
      subtitle:
          'Admin Control Panel. Only administrators can modify system policy, thresholds, and device settings.',
      trailing: const StatusBadge(
        label: 'Admin Control Panel',
        tone: UiBadgeTone.healthy,
        icon: Icons.admin_panel_settings_rounded,
        prominent: true,
      ),
      children: [
        _SettingsOpsBanner(
          isAdmin: _isAdmin,
          hasApi: _hasApi,
          loadingNotificationSettings: _loadingNotificationSettings,
          loadingDeviceLocation: _loadingDeviceLocation,
          pushRule: _pushRule,
          alertSoundEnabled: _alertSoundEnabled,
        ),
        SizedBox(height: sectionSpace),
        _SettingsMiniGrid(
          items: [
            const _SettingsMiniItem(
              label: 'Access Mode',
              value: 'Admin Control Panel',
              tone: UiBadgeTone.healthy,
            ),
            _SettingsMiniItem(
              label: 'Threshold Risk',
              value: thresholdRisk == UiBadgeTone.critical
                  ? 'Aggressive'
                  : 'Controlled',
              tone: thresholdRisk,
            ),
            _SettingsMiniItem(
              label: 'Push Policy',
              value: _pushRule,
              tone: pushTone,
            ),
            _SettingsMiniItem(
              label: 'Data Source',
              value: _hasApi ? 'Cloud API' : 'No telemetry API',
              tone: dataSourceTone,
            ),
          ],
        ),
        SizedBox(height: sectionSpace),
        const SectionHeader(
          title: 'System Policy',
          subtitle: 'Refresh behavior and trend defaults.',
          icon: Icons.settings_suggest_rounded,
        ),
        _ConfigTile(
          icon: Icons.speed_outlined,
          title: 'Auto Refresh Interval',
          summary: 'Every $_refreshSeconds seconds',
          actionLabel: 'Manage',
          enabled: true,
          onTap: _editRefreshInterval,
        ),
        _ConfigTile(
          icon: Icons.timeline_outlined,
          title: 'Default Trend Window',
          summary: _defaultTrendWindow,
          actionLabel: 'Manage',
          enabled: true,
          onTap: _editDefaultTrendWindow,
        ),
        _ConfigTile(
          icon: Icons.sync_alt_outlined,
          title: 'Dashboard Refresh Mode',
          summary: _refreshMode,
          actionLabel: 'Manage',
          enabled: true,
          onTap: _editRefreshMode,
        ),
        SizedBox(height: sectionSpace),
        const SectionHeader(
          title: 'Alert Thresholds',
          subtitle: 'Threshold controls and safety policy baseline.',
          icon: Icons.rule_rounded,
        ),
        _ThresholdGroupGrid(
          children: [
            _ThresholdGroupCard(
              icon: Icons.water_drop_outlined,
              title: 'Water Level',
              unit: '%',
              warningValue: _waterWarning.toStringAsFixed(0),
              criticalValue: _waterCritical.toStringAsFixed(0),
              basis: 'Public InfoBanjir stages',
              actionLabel: 'Manage',
              onTap: _openWaterThresholdEditor,
            ),
            _ThresholdGroupCard(
              icon: Icons.vibration_outlined,
              title: 'Vibration',
              unit: 'mm/s RMS',
              warningValue: _vibrationWarning.toStringAsFixed(1),
              criticalValue: _vibrationCritical.toStringAsFixed(1),
              basis: 'Prototype calibration',
              actionLabel: 'Manage',
              onTap: _openVibrationThresholdEditor,
            ),
            _ThresholdGroupCard(
              icon: Icons.thermostat_outlined,
              title: 'Temperature',
              unit: 'deg C',
              warningValue: _temperatureWarning.toStringAsFixed(0),
              criticalValue: _temperatureCritical.toStringAsFixed(0),
              basis: 'Malaysian heat-wave scale',
              actionLabel: 'Manage',
              onTap: _openTemperatureThresholdEditor,
            ),
          ],
        ),
        const SizedBox(height: UiSpace.gap),
        _ThresholdAuditCard(
          title: 'Threshold Audit',
          summary: 'Last modified by: ${widget.username}',
          detail:
              'Last modified at: ${_formatAuditTimestamp(DateTime.now())}\nUpdated fields: water, vibration, temperature thresholds',
        ),
        SizedBox(height: sectionSpace),
        const SectionHeader(
          title: 'Notification Settings',
          subtitle: 'Email, push, and audible warning preferences.',
          icon: Icons.notifications_active_rounded,
        ),
        _ConfigTile(
          icon: Icons.alternate_email_outlined,
          title: 'Notification Email',
          summary: _notificationEmail.isEmpty
              ? 'Not configured'
              : '$_notificationEmail ($_emailSubscriptionStatus)',
          actionLabel: 'Manage',
          enabled: true,
          onTap: _editNotificationEmail,
        ),
        _ConfigTile(
          icon: Icons.notifications_active_outlined,
          title: 'Push Notifications',
          summary: _pushRule,
          actionLabel: 'Manage',
          enabled: true,
          onTap: _editPushNotifications,
        ),
        _ConfigTile(
          icon: Icons.volume_up_outlined,
          title: 'Alert Sound',
          summary: _loadingNotificationSettings
              ? 'Syncing...'
              : (_alertSoundEnabled ? 'Enabled' : 'Disabled'),
          actionLabel: 'Manage',
          enabled: true,
          onTap: _editAlertSound,
        ),
        _ConfigTile(
          icon: Icons.volume_off_outlined,
          title: 'Hardware Buzzer',
          summary: _silencingHardwareBuzzer
              ? 'Sending silence command...'
              : 'Silence $_deviceLocation for 1 hour',
          actionLabel: _silencingHardwareBuzzer ? 'Sending' : 'Silence',
          enabled: _hasApi && !_silencingHardwareBuzzer,
          onTap: _silenceHardwareBuzzer,
        ),
        SizedBox(height: sectionSpace),
        const SectionHeader(
          title: 'Site and User',
          subtitle: null,
          icon: Icons.account_tree_rounded,
        ),
        _ConfigTile(
          icon: Icons.apartment_outlined,
          title: 'Site Name',
          summary: _siteName,
          actionLabel: 'Manage',
          enabled: true,
          onTap: _openSiteProfileEditor,
        ),
        _ConfigTile(
          icon: Icons.badge_outlined,
          title: 'Current Role',
          summary: widget.role.label,
          actionLabel: '',
          enabled: false,
        ),
        _ConfigTile(
          icon: Icons.place_outlined,
          title: 'Device Location',
          summary: _loadingDeviceLocation ? 'Syncing...' : _deviceLocation,
          actionLabel: 'Manage',
          enabled: true,
          onTap: _openDeviceLocationEditor,
        ),
      ],
    );
  }

  String _formatAuditTimestamp(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  Future<void> _openWaterThresholdEditor() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ThresholdEditorPage(
          title: 'Edit Water Level Thresholds',
          unit: '%',
          warning: _waterWarning,
          critical: _waterCritical,
          editable: _isAdmin,
          min: 0,
          max: 100,
          step: 1,
          onSave: (warning, critical) async {
            if (!_hasApi) {
              setState(() {
                _waterWarning = warning;
                _waterCritical = critical;
              });
              return true;
            }
            return _saveSystemSettings(
              thresholds: _buildThresholdPayload(
                waterWarning: warning,
                waterCritical: critical,
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openVibrationThresholdEditor() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ThresholdEditorPage(
          title: 'Edit Vibration Thresholds',
          unit: 'mm/s RMS',
          warning: _vibrationWarning,
          critical: _vibrationCritical,
          editable: _isAdmin,
          min: 0,
          max: 20,
          step: 0.1,
          onSave: (warning, critical) async {
            if (!_hasApi) {
              setState(() {
                _vibrationWarning = warning;
                _vibrationCritical = critical;
              });
              return true;
            }
            return _saveSystemSettings(
              thresholds: _buildThresholdPayload(
                vibrationWarning: warning,
                vibrationCritical: critical,
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openTemperatureThresholdEditor() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ThresholdEditorPage(
          title: 'Edit Temperature Thresholds',
          unit: 'deg C',
          warning: _temperatureWarning,
          critical: _temperatureCritical,
          editable: _isAdmin,
          min: 0,
          max: 100,
          step: 1,
          onSave: (warning, critical) async {
            if (!_hasApi) {
              setState(() {
                _temperatureWarning = warning;
                _temperatureCritical = critical;
              });
              return true;
            }
            return _saveSystemSettings(
              thresholds: _buildThresholdPayload(
                temperatureWarning: warning,
                temperatureCritical: critical,
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openSiteProfileEditor() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _SiteProfilePage(
          name: _siteName,
          description: _siteDescription,
          editable: _isAdmin,
          onSave: (name, description) async {
            if (!_hasApi) {
              setState(() {
                _siteName = name;
                _siteDescription = description;
              });
              return true;
            }
            return _saveSystemSettings(
              siteName: name,
              siteDescription: description,
            );
          },
        ),
      ),
    );
  }

  Future<void> _openDeviceLocationEditor() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _DeviceLocationPage(
          location: _deviceLocation,
          editable: _isAdmin,
          onSave: (location) async {
            setState(() => _deviceLocation = location);
            await _saveDeviceLocation(location);
          },
        ),
      ),
    );
  }

  Future<void> _editRefreshInterval() async {
    final selected = await _openChoiceDialog<int>(
      title: 'Edit Auto Refresh Interval',
      currentValue: _refreshSeconds,
      options: const [4, 10, 30, 60],
      labelBuilder: (v) => '$v seconds',
    );
    if (selected != null) {
      if (!_hasApi) {
        setState(() => _refreshSeconds = selected);
      } else {
        await _saveSystemSettings(autoRefreshIntervalSeconds: selected);
      }
    }
  }

  Future<void> _editDefaultTrendWindow() async {
    final selected = await _openChoiceDialog<String>(
      title: 'Select Default Trend Window',
      currentValue: _defaultTrendWindow,
      options: const ['1H', '6H', '24H', '7D', '14D', '30D'],
      labelBuilder: (v) => v,
    );
    if (selected != null) {
      if (!_hasApi) {
        setState(() => _defaultTrendWindow = selected);
      } else {
        await _saveSystemSettings(defaultTrendWindow: selected);
      }
    }
  }

  Future<void> _editRefreshMode() async {
    final selected = await _openChoiceDialog<String>(
      title: 'Configure Dashboard Refresh Mode',
      currentValue: _refreshMode,
      options: const ['Auto', 'Manual', 'Auto + Manual'],
      labelBuilder: (v) => v,
    );
    if (selected != null) {
      if (!_hasApi) {
        setState(() => _refreshMode = selected);
      } else {
        await _saveSystemSettings(dashboardRefreshMode: selected);
      }
    }
  }

  Future<void> _editPushNotifications() async {
    final selected = await _openChoiceDialog<String>(
      title: 'Push Notification Settings',
      currentValue: _pushRule,
      options: const ['Warning + Critical', 'Critical only', 'Disabled'],
      labelBuilder: (v) => v,
    );
    if (selected != null) {
      setState(() => _pushRule = selected);
      await _saveNotificationSettings(pushRule: selected);
    }
  }

  Future<void> _editNotificationEmail() async {
    final controller = TextEditingController(text: _notificationEmail);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notification Email'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Email',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null) return;
    setState(() => _notificationEmail = value);
    await _saveNotificationSettings(notificationEmail: value);
    await _loadNotificationSettings();
  }

  Future<void> _editAlertSound() async {
    final selected = await _openChoiceDialog<bool>(
      title: 'Alert Sound Settings',
      currentValue: _alertSoundEnabled,
      options: const [true, false],
      labelBuilder: (v) => v ? 'Enabled' : 'Disabled',
    );
    if (selected != null) {
      setState(() => _alertSoundEnabled = selected);
      await _saveNotificationSettings(alertSoundEnabled: selected);
    }
  }

  Future<void> _silenceHardwareBuzzer() async {
    if (!_hasApi) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cloud API is not configured.')),
      );
      return;
    }

    setState(() => _silencingHardwareBuzzer = true);
    try {
      final resp = await http.post(
        Uri.parse('${widget.apiBaseUrl}/api/device/buzzer/silence'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'zone': _deviceLocation,
          'actorRole': widget.role.label,
          'requestedBy': widget.username,
          'durationSeconds': _hardwareBuzzerSilenceSeconds,
        }),
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('silence failed');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hardware buzzer silenced for 1 hour.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to silence hardware buzzer.')),
      );
    } finally {
      if (mounted) {
        setState(() => _silencingHardwareBuzzer = false);
      }
    }
  }

  Future<void> _loadSystemSettings() async {
    if (!_hasApi) return;
    try {
      final resp = await http.get(
        Uri.parse('${widget.apiBaseUrl}/api/settings/system'),
        headers: _settingsHeaders(),
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return;
      }
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _applySystemSettingsFromApi(json);
      });
    } catch (_) {
      // Keep local defaults when API is unavailable.
    }
  }

  Future<bool> _saveSystemSettings({
    int? autoRefreshIntervalSeconds,
    String? defaultTrendWindow,
    String? dashboardRefreshMode,
    String? siteName,
    String? siteDescription,
    Map<String, dynamic>? thresholds,
  }) async {
    if (!_hasApi) return false;
    try {
      final payload = <String, dynamic>{};
      if (autoRefreshIntervalSeconds != null) {
        payload['autoRefreshIntervalSeconds'] = autoRefreshIntervalSeconds;
      }
      if (defaultTrendWindow != null) {
        payload['defaultTrendWindow'] = defaultTrendWindow;
      }
      if (dashboardRefreshMode != null) {
        payload['dashboardRefreshMode'] = dashboardRefreshMode;
      }
      if (siteName != null) {
        payload['siteName'] = siteName;
      }
      if (siteDescription != null) {
        payload['siteDescription'] = siteDescription;
      }
      if (thresholds != null) {
        payload['thresholds'] = thresholds;
      }
      if (payload.isEmpty) return true;

      final resp = await http.post(
        Uri.parse('${widget.apiBaseUrl}/api/settings/system'),
        headers: {
          ..._settingsHeaders(),
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('save failed');
      }

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return false;
      setState(() {
        _applySystemSettingsFromApi(json);
      });
      return true;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save system settings to backend')),
      );
      return false;
    }
  }

  Map<String, dynamic> _buildThresholdPayload({
    double? waterWarning,
    double? waterCritical,
    double? vibrationWarning,
    double? vibrationCritical,
    double? temperatureWarning,
    double? temperatureCritical,
  }) {
    return {
      'waterLevel': {
        'warning': waterWarning ?? _waterWarning,
        'critical': waterCritical ?? _waterCritical,
      },
      'vibration': {
        'warning': vibrationWarning ?? _vibrationWarning,
        'critical': vibrationCritical ?? _vibrationCritical,
      },
      'temperature': {
        'warning': temperatureWarning ?? _temperatureWarning,
        'critical': temperatureCritical ?? _temperatureCritical,
      },
    };
  }

  Map<String, String> _settingsHeaders() {
    return {
      'x-user-id': widget.username,
      'x-user-role': widget.role.label,
    };
  }

  void _applySystemSettingsFromApi(Map<String, dynamic> json) {
    final refreshSecondsRaw = json['autoRefreshIntervalSeconds'];
    if (refreshSecondsRaw is num) {
      _refreshSeconds = refreshSecondsRaw.toInt();
    }

    final trendWindowRaw = json['defaultTrendWindow']?.toString().trim();
    if (trendWindowRaw != null && trendWindowRaw.isNotEmpty) {
      _defaultTrendWindow = trendWindowRaw;
    }

    final refreshModeRaw = json['dashboardRefreshMode']?.toString().trim();
    if (refreshModeRaw != null && refreshModeRaw.isNotEmpty) {
      _refreshMode = refreshModeRaw;
    }

    final siteNameRaw = json['siteName']?.toString().trim();
    if (siteNameRaw != null && siteNameRaw.isNotEmpty) {
      _siteName = siteNameRaw;
    }

    final siteDescriptionRaw = json['siteDescription']?.toString().trim();
    if (siteDescriptionRaw != null && siteDescriptionRaw.isNotEmpty) {
      _siteDescription = siteDescriptionRaw;
    }

    final thresholdsRaw = json['thresholds'];
    if (thresholdsRaw is Map) {
      final water = thresholdsRaw['waterLevel'];
      if (water is Map) {
        final warning = water['warning'];
        final critical = water['critical'];
        if (warning is num) _waterWarning = warning.toDouble();
        if (critical is num) _waterCritical = critical.toDouble();
      }

      final vibration = thresholdsRaw['vibration'];
      if (vibration is Map) {
        final warning = vibration['warning'];
        final critical = vibration['critical'];
        if (warning is num) _vibrationWarning = warning.toDouble();
        if (critical is num) _vibrationCritical = critical.toDouble();
      }

      final temperature = thresholdsRaw['temperature'];
      if (temperature is Map) {
        final warning = temperature['warning'];
        final critical = temperature['critical'];
        if (warning is num) _temperatureWarning = warning.toDouble();
        if (critical is num) _temperatureCritical = critical.toDouble();
      }
    }
  }

  Future<T?> _openChoiceDialog<T>({
    required String title,
    required T currentValue,
    required List<T> options,
    required String Function(T) labelBuilder,
  }) async {
    T selected = currentValue;
    return showDialog<T>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: options
                .map(
                  (option) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(labelBuilder(option)),
                    trailing: Icon(
                      selected == option
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: selected == option
                          ? UiColors.brand
                          : const Color(0xFF9AA7AD),
                    ),
                    onTap: () => setDialogState(() => selected = option),
                  ),
                )
                .toList(growable: false),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(selected),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadNotificationSettings() async {
    if (!_hasApi) return;
    setState(() => _loadingNotificationSettings = true);
    try {
      final resp = await http.get(
        Uri.parse('${widget.apiBaseUrl}/api/settings/notifications'),
        headers: _settingsHeaders(),
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        if (!mounted) return;
        setState(() {
          _pushRule = json['pushRule']?.toString() ?? _pushRule;
          _alertSoundEnabled =
              (json['alertSoundEnabled'] as bool?) ?? _alertSoundEnabled;
          _notificationEmail =
              json['notificationEmail']?.toString() ?? _notificationEmail;
          _emailSubscriptionStatus =
              json['emailSubscriptionStatus']?.toString() ??
                  _emailSubscriptionStatus;
        });
      }
    } catch (_) {
      // Keep local defaults silently when API is unavailable.
    } finally {
      if (mounted) setState(() => _loadingNotificationSettings = false);
    }
  }

  Future<void> _saveNotificationSettings({
    String? pushRule,
    bool? alertSoundEnabled,
    String? notificationEmail,
  }) async {
    if (!_hasApi) return;
    try {
      final payload = <String, dynamic>{};
      if (pushRule != null) payload['pushRule'] = pushRule;
      if (alertSoundEnabled != null) {
        payload['alertSoundEnabled'] = alertSoundEnabled;
      }
      if (notificationEmail != null) {
        payload['notificationEmail'] = notificationEmail;
      }
      if (payload.isEmpty) return;

      final resp = await http.post(
        Uri.parse('${widget.apiBaseUrl}/api/settings/notifications'),
        headers: {
          'Content-Type': 'application/json',
          ..._settingsHeaders(),
        },
        body: jsonEncode(payload),
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('save failed');
      }
      await widget.onNotificationSettingsChanged?.call();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Failed to save notification settings to backend')),
      );
    }
  }

  Future<void> _loadDeviceLocation() async {
    if (!_hasApi) return;
    setState(() => _loadingDeviceLocation = true);
    try {
      final resp = await http
          .get(Uri.parse('${widget.apiBaseUrl}/api/settings/device-location'));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        if (!mounted) return;
        setState(() {
          _deviceLocation = json['location']?.toString() ?? _deviceLocation;
        });
      }
    } catch (_) {
      // Keep local value when API is unavailable.
    } finally {
      if (mounted) setState(() => _loadingDeviceLocation = false);
    }
  }

  Future<void> _saveDeviceLocation(String location) async {
    if (!_hasApi) return;
    try {
      final resp = await http.post(
        Uri.parse('${widget.apiBaseUrl}/api/settings/device-location'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'location': location}),
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('save failed');
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Failed to save device location to backend')),
      );
    }
  }
}

class _SettingsOpsBanner extends StatelessWidget {
  const _SettingsOpsBanner({
    required this.isAdmin,
    required this.hasApi,
    required this.loadingNotificationSettings,
    required this.loadingDeviceLocation,
    required this.pushRule,
    required this.alertSoundEnabled,
  });

  final bool isAdmin;
  final bool hasApi;
  final bool loadingNotificationSettings;
  final bool loadingDeviceLocation;
  final String pushRule;
  final bool alertSoundEnabled;

  @override
  Widget build(BuildContext context) {
    final loadingAny = loadingNotificationSettings || loadingDeviceLocation;
    final tone = !hasApi
        ? UiBadgeTone.warning
        : (isAdmin ? UiBadgeTone.healthy : UiBadgeTone.stable);
    final bg = switch (tone) {
      UiBadgeTone.warning => const Color(0xFFFFF5E6),
      UiBadgeTone.stable => const Color(0xFFEAF2F8),
      _ => const Color(0xFFEAF7EF),
    };
    final border = switch (tone) {
      UiBadgeTone.warning => const Color(0xFFF2D094),
      UiBadgeTone.stable => const Color(0xFFBFD5E6),
      _ => const Color(0xFFB8DFC4),
    };
    final title = !hasApi
        ? 'Cloud API not configured'
        : (isAdmin
            ? 'Administrative control panel active'
            : 'Operator settings panel in read-only governance mode');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(UiRadius.card),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(
            !hasApi
                ? Icons.cloud_off_rounded
                : (isAdmin
                    ? Icons.admin_panel_settings_rounded
                    : Icons.tune_rounded),
            color: !hasApi
                ? UiColors.warning
                : (isAdmin ? UiColors.healthy : UiColors.brand),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: UiText.cardTitle),
                const SizedBox(height: 2),
                Text(
                  'Push: $pushRule | Alert Sound: ${alertSoundEnabled ? 'Enabled' : 'Disabled'} | Device location sync: ${loadingDeviceLocation ? 'Syncing' : 'Ready'}${loadingAny ? ' | Updating policy cache...' : ''}',
                  style: UiText.helper,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsMiniItem {
  const _SettingsMiniItem({
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final String value;
  final UiBadgeTone tone;
}

class _SettingsMiniGrid extends StatelessWidget {
  const _SettingsMiniGrid({required this.items});

  final List<_SettingsMiniItem> items;

  @override
  Widget build(BuildContext context) {
    final compact = uiIsCompactLayout(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final singleColumn = uiIsCompactLayout(context);
        final width = constraints.maxWidth >= 1200
            ? (constraints.maxWidth - UiSpace.gap * 3) / 4
            : !singleColumn && constraints.maxWidth >= 760
                ? (constraints.maxWidth - UiSpace.gap) / 2
                : constraints.maxWidth;
        return Wrap(
          spacing: UiSpace.gap,
          runSpacing: UiSpace.gap,
          children: items
              .map(
                (item) => SizedBox(
                  width: width,
                  child: UiCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _SettingsStatusDot(tone: item.tone),
                            const SizedBox(width: 6),
                            Expanded(
                                child: Text(item.label, style: UiText.helper)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.value,
                          style: UiText.cardTitle.copyWith(
                            fontSize: compact ? 14 : 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _SettingsStatusDot extends StatelessWidget {
  const _SettingsStatusDot({required this.tone});

  final UiBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      UiBadgeTone.critical => UiColors.danger,
      UiBadgeTone.warning => UiColors.warning,
      UiBadgeTone.offline => UiColors.neutral,
      UiBadgeTone.noTelemetry => UiColors.neutral,
      UiBadgeTone.healthy => UiColors.healthy,
      UiBadgeTone.stable => UiColors.brand,
    };
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _ThresholdGroupGrid extends StatelessWidget {
  const _ThresholdGroupGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = uiIsCompactLayout(context);
        final width = constraints.maxWidth >= 1180
            ? (constraints.maxWidth - UiSpace.gap * 2) / 3
            : (!compact && constraints.maxWidth >= 760
                ? (constraints.maxWidth - UiSpace.gap) / 2
                : constraints.maxWidth);
        return Wrap(
          spacing: UiSpace.gap,
          runSpacing: UiSpace.gap,
          children: children
              .map((child) => SizedBox(width: width, child: child))
              .toList(growable: false),
        );
      },
    );
  }
}

class _ThresholdGroupCard extends StatelessWidget {
  const _ThresholdGroupCard({
    required this.icon,
    required this.title,
    required this.unit,
    required this.warningValue,
    required this.criticalValue,
    required this.basis,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String unit;
  final String warningValue;
  final String criticalValue;
  final String basis;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return UiCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: UiColors.brandSoft,
                  borderRadius: BorderRadius.circular(UiRadius.input),
                ),
                child: Icon(icon, color: UiColors.brand, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: UiText.cardTitle)),
              OutlinedButton(
                onPressed: onTap,
                style: uiSecondaryButton(),
                child: Text(actionLabel),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ThresholdValueBlock(
                  label: 'Warning',
                  value: warningValue,
                  unit: unit,
                  tone: UiBadgeTone.warning,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ThresholdValueBlock(
                  label: 'Critical',
                  value: criticalValue,
                  unit: unit,
                  tone: UiBadgeTone.critical,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Basis: $basis', style: UiText.helper),
        ],
      ),
    );
  }
}

class _ThresholdValueBlock extends StatelessWidget {
  const _ThresholdValueBlock({
    required this.label,
    required this.value,
    required this.unit,
    required this.tone,
  });

  final String label;
  final String value;
  final String unit;
  final UiBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: uiToneSoftColor(tone),
        borderRadius: BorderRadius.circular(UiRadius.input),
        border: Border.all(color: uiToneBorderColor(tone)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: UiText.label.copyWith(color: uiToneColor(tone))),
          const SizedBox(height: 5),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              '$value $unit',
              style: UiText.cardTitle.copyWith(fontSize: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfigTile extends StatelessWidget {
  const _ConfigTile({
    required this.icon,
    required this.title,
    required this.summary,
    required this.actionLabel,
    required this.enabled,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String summary;
  final String actionLabel;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: UiCard(
        padding: const EdgeInsets.all(UiSpace.card),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;
            final content = Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: UiText.cardTitle),
                  const SizedBox(height: 4),
                  Text(
                    summary,
                    style: UiText.body,
                    maxLines: compact ? 4 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );

            final actionButton = actionLabel.isEmpty
                ? null
                : SizedBox(
                    width: 104,
                    height: 40,
                    child: OutlinedButton(
                      onPressed: enabled ? onTap : null,
                      style: uiSecondaryButton(),
                      child: Text(
                        actionLabel,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF4F6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, size: 18, color: UiColors.brand),
                      ),
                      const SizedBox(width: 10),
                      content,
                    ],
                  ),
                  if (actionButton != null) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: actionButton,
                    ),
                  ],
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF4F6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: UiColors.brand),
                ),
                const SizedBox(width: 10),
                content,
                if (actionButton != null) ...[
                  const SizedBox(width: 10),
                  actionButton,
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ThresholdAuditCard extends StatelessWidget {
  const _ThresholdAuditCard({
    required this.title,
    required this.summary,
    required this.detail,
  });

  final String title;
  final String summary;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFCFD),
        border: Border.all(color: const Color(0xFFE7EFF3)),
        borderRadius: BorderRadius.circular(UiRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.history_toggle_off_outlined,
                size: 16,
                color: UiColors.neutral,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: UiText.helper.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(summary, style: UiText.helper),
          const SizedBox(height: 4),
          Text(detail, style: UiText.helper),
        ],
      ),
    );
  }
}

class _ThresholdEditorPage extends StatefulWidget {
  const _ThresholdEditorPage({
    required this.title,
    required this.unit,
    required this.warning,
    required this.critical,
    required this.editable,
    required this.min,
    required this.max,
    required this.step,
    required this.onSave,
  });

  final String title;
  final String unit;
  final double warning;
  final double critical;
  final bool editable;
  final double min;
  final double max;
  final double step;
  final Future<bool> Function(double warning, double critical) onSave;

  @override
  State<_ThresholdEditorPage> createState() => _ThresholdEditorPageState();
}

class _ThresholdEditorPageState extends State<_ThresholdEditorPage> {
  late double _warning;
  late double _critical;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _warning = widget.warning;
    _critical = widget.critical;
  }

  @override
  Widget build(BuildContext context) {
    final invalid = _critical <= _warning;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: uiPagePadding(context),
        children: [
          Text(
            widget.editable
                ? 'Adjust thresholds and save changes.'
                : 'Read-only mode for User role.',
            style: UiText.helper,
          ),
          const SizedBox(height: 14),
          _ThresholdSlider(
            label: 'Warning Threshold',
            value: _warning,
            unit: widget.unit,
            min: widget.min,
            max: widget.max,
            step: widget.step,
            enabled: widget.editable,
            onChanged: (v) => setState(() => _warning = v),
          ),
          const SizedBox(height: 10),
          _ThresholdSlider(
            label: 'Critical Threshold',
            value: _critical,
            unit: widget.unit,
            min: widget.min,
            max: widget.max,
            step: widget.step,
            enabled: widget.editable,
            onChanged: (v) => setState(() => _critical = v),
          ),
          const SizedBox(height: 10),
          _ThresholdValidationNotice(
            invalid: invalid,
            editable: widget.editable,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: uiSecondaryButton(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed:
                      widget.editable && !invalid && !_saving ? _save : null,
                  style: uiPrimaryButton(),
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_critical <= _warning) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Critical threshold must be higher than warning threshold.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await widget.onSave(_warning, _critical);
      if (!mounted || !saved) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _ThresholdValidationNotice extends StatelessWidget {
  const _ThresholdValidationNotice({
    required this.invalid,
    required this.editable,
  });

  final bool invalid;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final tone = invalid ? UiBadgeTone.critical : UiBadgeTone.healthy;
    final text = invalid
        ? 'Critical threshold must be higher than warning threshold.'
        : (editable
            ? 'Threshold order is valid and ready to save.'
            : 'Read-only preview; values are locked for this role.');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: uiToneSoftColor(tone),
        borderRadius: BorderRadius.circular(UiRadius.input),
        border: Border.all(color: uiToneBorderColor(tone)),
      ),
      child: Row(
        children: [
          Icon(
            invalid ? Icons.error_rounded : Icons.check_circle_rounded,
            size: 18,
            color: uiToneColor(tone),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: UiText.helper.copyWith(
                color: uiToneColor(tone),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThresholdSlider extends StatelessWidget {
  const _ThresholdSlider({
    required this.label,
    required this.value,
    required this.unit,
    required this.min,
    required this.max,
    required this.step,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final double value;
  final String unit;
  final double min;
  final double max;
  final double step;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final decimalDigits = step < 1 ? 1 : 0;
    return UiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: UiText.cardTitle),
          const SizedBox(height: 8),
          Text(
            '${value.toStringAsFixed(decimalDigits)} $unit',
            style: UiText.sectionTitle,
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: ((max - min) / step).round(),
            label: value.toStringAsFixed(decimalDigits),
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}

class _SiteProfilePage extends StatefulWidget {
  const _SiteProfilePage({
    required this.name,
    required this.description,
    required this.editable,
    required this.onSave,
  });

  final String name;
  final String description;
  final bool editable;
  final Future<bool> Function(String name, String description) onSave;

  @override
  State<_SiteProfilePage> createState() => _SiteProfilePageState();
}

class _SiteProfilePageState extends State<_SiteProfilePage> {
  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.name);
    _descController = TextEditingController(text: widget.description);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Site Profile')),
      body: ListView(
        padding: uiPagePadding(context),
        children: [
          TextField(
            controller: _nameController,
            enabled: widget.editable,
            decoration: const InputDecoration(
              labelText: 'Site Name',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _descController,
            enabled: widget.editable,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Description',
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: uiSecondaryButton(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: widget.editable && !_saving ? _save : null,
                  style: uiPrimaryButton(),
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final description = _descController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Site name cannot be empty.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await widget.onSave(name, description);
      if (!mounted || !saved) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _DeviceLocationPage extends StatefulWidget {
  const _DeviceLocationPage({
    required this.location,
    required this.editable,
    required this.onSave,
  });

  final String location;
  final bool editable;
  final Future<void> Function(String location) onSave;

  @override
  State<_DeviceLocationPage> createState() => _DeviceLocationPageState();
}

class _DeviceLocationPageState extends State<_DeviceLocationPage> {
  late final TextEditingController _locationController;

  @override
  void initState() {
    super.initState();
    _locationController = TextEditingController(text: widget.location);
  }

  @override
  void dispose() {
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Device Location')),
      body: ListView(
        padding: uiPagePadding(context),
        children: [
          TextField(
            controller: _locationController,
            enabled: widget.editable,
            decoration: const InputDecoration(
              labelText: 'Device Location (Zone)',
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: uiSecondaryButton(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: widget.editable
                      ? () async {
                          final value = _locationController.text.trim();
                          if (value.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Location cannot be empty.')),
                            );
                            return;
                          }
                          await widget.onSave(value);
                          if (!context.mounted) return;
                          Navigator.of(context).pop();
                        }
                      : null,
                  style: uiPrimaryButton(),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
