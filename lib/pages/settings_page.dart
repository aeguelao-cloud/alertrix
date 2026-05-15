import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/auth_models.dart';
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
  double _waterWarning = 70;
  double _waterCritical = 85;
  double _vibrationWarning = 2.8;
  double _vibrationCritical = 4.0;
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

  bool get _isAdmin => widget.role == UserRole.admin;
  bool get _hasApi => (widget.apiBaseUrl ?? '').trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadNotificationSettings();
    _loadDeviceLocation();
  }

  @override
  Widget build(BuildContext context) {
    final sectionSpace = uiSectionSpacing(context);
    return ListView(
      padding: uiPagePadding(context),
      children: [
        const UiPageHeader(
          systemName: 'Alertrix',
          title: 'Response Settings',
          subtitle:
              'System policy, threshold controls, and notification preferences.',
        ),
        SizedBox(height: sectionSpace),
        _SectionTitle(
          title: 'System Policy',
          subtitle: _isAdmin ? null : 'Read-only in User role',
        ),
        _ConfigTile(
          icon: Icons.speed_outlined,
          title: 'Auto Refresh Interval',
          summary: 'Every $_refreshSeconds seconds',
          actionLabel: _isAdmin ? 'Manage' : 'View',
          enabled: true,
          onTap: _isAdmin ? _editRefreshInterval : _showAdminOnlyHint,
        ),
        _ConfigTile(
          icon: Icons.timeline_outlined,
          title: 'Default Trend Window',
          summary: _defaultTrendWindow,
          actionLabel: _isAdmin ? 'Manage' : 'View',
          enabled: true,
          onTap: _isAdmin ? _editDefaultTrendWindow : _showAdminOnlyHint,
        ),
        _ConfigTile(
          icon: Icons.sync_alt_outlined,
          title: 'Dashboard Refresh Mode',
          summary: _refreshMode,
          actionLabel: _isAdmin ? 'Manage' : 'View',
          enabled: true,
          onTap: _isAdmin ? _editRefreshMode : _showAdminOnlyHint,
        ),
        SizedBox(height: sectionSpace),
        _SectionTitle(
          title: 'Alert Thresholds',
          subtitle: _isAdmin
              ? null
              : 'Threshold editing is restricted to administrators',
        ),
        _ConfigTile(
          icon: Icons.water_drop_outlined,
          title: 'Water Level Thresholds',
          summary: '',
          summaryContent: _ThresholdSummary(
            warningCritical:
                'Warning ${_waterWarning.toStringAsFixed(0)}% | Critical ${_waterCritical.toStringAsFixed(0)}%',
            basis: 'Basis: Public InfoBanjir stages',
          ),
          actionLabel: _isAdmin ? 'Manage' : 'View',
          enabled: true,
          onTap: _openWaterThresholdEditor,
        ),
        _ConfigTile(
          icon: Icons.vibration_outlined,
          title: 'Vibration Thresholds',
          summary: '',
          summaryContent: _ThresholdSummary(
            warningCritical:
                'Warning ${_vibrationWarning.toStringAsFixed(1)} mm/s | Critical ${_vibrationCritical.toStringAsFixed(1)} mm/s',
            basis: 'Basis: prototype calibration',
          ),
          actionLabel: _isAdmin ? 'Manage' : 'View',
          enabled: true,
          onTap: _openVibrationThresholdEditor,
        ),
        _ConfigTile(
          icon: Icons.thermostat_outlined,
          title: 'Temperature Thresholds',
          summary: '',
          summaryContent: _ThresholdSummary(
            warningCritical:
                'Warning ${_temperatureWarning.toStringAsFixed(0)}°C | Critical ${_temperatureCritical.toStringAsFixed(0)}°C',
            basis: 'Basis: Malaysian heat-wave scale',
          ),
          actionLabel: _isAdmin ? 'Manage' : 'View',
          enabled: true,
          onTap: _openTemperatureThresholdEditor,
        ),
        _ThresholdAuditCard(
          title: 'Threshold Audit',
          summary:
              'Last modified on ${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')} by ${widget.username}',
          detail: 'Updated scope: water, vibration, temperature thresholds',
        ),
        SizedBox(height: sectionSpace),
        const _SectionTitle(title: 'Notification Settings'),
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
        SizedBox(height: sectionSpace),
        _SectionTitle(
          title: 'Site and User',
          subtitle: _isAdmin ? null : 'Site fields are read-only in User role',
        ),
        _ConfigTile(
          icon: Icons.apartment_outlined,
          title: 'Site Name',
          summary: _siteName,
          actionLabel: _isAdmin ? 'Manage' : 'View',
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
          actionLabel: _isAdmin ? 'Manage' : 'View',
          enabled: true,
          onTap: _openDeviceLocationEditor,
        ),
      ],
    );
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
          onSave: (warning, critical) {
            setState(() {
              _waterWarning = warning;
              _waterCritical = critical;
            });
          },
        ),
      ),
    );
  }

  void _showAdminOnlyHint() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('This setting is read-only for User role.'),
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
          max: 10,
          step: 0.1,
          onSave: (warning, critical) {
            setState(() {
              _vibrationWarning = warning;
              _vibrationCritical = critical;
            });
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
          unit: '°C',
          warning: _temperatureWarning,
          critical: _temperatureCritical,
          editable: _isAdmin,
          min: 0,
          max: 100,
          step: 1,
          onSave: (warning, critical) {
            setState(() {
              _temperatureWarning = warning;
              _temperatureCritical = critical;
            });
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
          onSave: (name, description) {
            setState(() {
              _siteName = name;
              _siteDescription = description;
            });
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
      setState(() => _refreshSeconds = selected);
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
      setState(() => _defaultTrendWindow = selected);
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
      setState(() => _refreshMode = selected);
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
        headers: {
          'x-user-id': widget.username,
          'x-user-role': widget.role.label,
        },
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
          'x-user-id': widget.username,
          'x-user-role': widget.role.label,
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: UiText.sectionTitle),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: UiText.helper),
          ],
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
    this.summaryContent,
    required this.actionLabel,
    required this.enabled,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String summary;
  final Widget? summaryContent;
  final String actionLabel;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return UiCard(
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
                if (summaryContent != null)
                  summaryContent!
                else
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
                  height: 38,
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
                      width: 34,
                      height: 34,
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
                width: 34,
                height: 34,
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
    );
  }
}

class _ThresholdSummary extends StatelessWidget {
  const _ThresholdSummary({
    required this.warningCritical,
    required this.basis,
  });

  final String warningCritical;
  final String basis;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          warningCritical,
          style: UiText.body.copyWith(fontWeight: FontWeight.w500),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        Text(
          basis,
          style: UiText.helper,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
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
  final void Function(double warning, double critical) onSave;

  @override
  State<_ThresholdEditorPage> createState() => _ThresholdEditorPageState();
}

class _ThresholdEditorPageState extends State<_ThresholdEditorPage> {
  late double _warning;
  late double _critical;

  @override
  void initState() {
    super.initState();
    _warning = widget.warning;
    _critical = widget.critical;
  }

  @override
  Widget build(BuildContext context) {
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
                  onPressed: widget.editable ? _save : null,
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

  void _save() {
    if (_critical <= _warning) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Critical threshold must be higher than warning threshold.')),
      );
      return;
    }
    widget.onSave(_warning, _critical);
    Navigator.of(context).pop();
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
  final void Function(String name, String description) onSave;

  @override
  State<_SiteProfilePage> createState() => _SiteProfilePageState();
}

class _SiteProfilePageState extends State<_SiteProfilePage> {
  late final TextEditingController _nameController;
  late final TextEditingController _descController;

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
                  onPressed: widget.editable ? _save : null,
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

  void _save() {
    final name = _nameController.text.trim();
    final description = _descController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Site name cannot be empty.')),
      );
      return;
    }
    widget.onSave(name, description);
    Navigator.of(context).pop();
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
