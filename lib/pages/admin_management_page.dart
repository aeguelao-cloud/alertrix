import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../widgets/ui_kit.dart';

class AdminManagementPage extends StatefulWidget {
  const AdminManagementPage({
    super.key,
    required this.apiBaseUrl,
    required this.adminHeaderUserId,
  });

  final String? apiBaseUrl;
  final String adminHeaderUserId;

  @override
  State<AdminManagementPage> createState() => _AdminManagementPageState();
}

class _AdminManagementPageState extends State<AdminManagementPage> {
  bool _loading = false;
  String? _error;
  List<AdminItem> _items = const <AdminItem>[];

  bool get _hasApi => (widget.apiBaseUrl ?? '').trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadAdmins();
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _items.where((item) => item.status == 'active').length;
    final inactiveCount = _items.length - activeCount;

    return ListView(
      padding: const EdgeInsets.all(UiSpace.page),
      children: [
        UiPageHeader(
          systemName: 'Alertrix',
          title: 'Admin Management',
          subtitle:
              '$activeCount active admin\nEmail notifications are sent to active administrators only',
          trailing: Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _loading ? null : _openCreateDialog,
                style: uiPrimaryButton(),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Add Admin'),
              ),
              IconButton(
                onPressed: _loading ? null : _loadAdmins,
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
        const SizedBox(height: UiSpace.section),
        _AdminSummaryRow(
          total: _items.length,
          active: activeCount,
          inactive: inactiveCount,
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEFEF),
              borderRadius: BorderRadius.circular(UiRadius.input),
            ),
            child: Text(_error!, style: UiText.helper),
          ),
        ],
        const SizedBox(height: UiSpace.section),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          )
        else if (!_hasApi)
          const UiCard(
            child: UiEmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'API base URL missing',
              subtitle: 'Start app with --dart-define=API_BASE_URL=...',
            ),
          )
        else if (_items.isEmpty)
          UiCard(
            child: UiEmptyState(
              icon: Icons.admin_panel_settings_outlined,
              title: 'No admins yet',
              subtitle: 'Click Add Admin to create the first admin recipient.',
              primaryAction: FilledButton(
                onPressed: _loading ? null : _openCreateDialog,
                style: uiPrimaryButton(),
                child: const Text('Add Admin'),
              ),
            ),
          )
        else
          ..._items.map(_buildAdminCard),
      ],
    );
  }

  Widget _buildAdminCard(AdminItem item) {
    final active = item.status == 'active';

    return UiCard(
      big: true,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(item.name, style: UiText.sectionTitle),
              ),
              UiBadge(
                label: active ? 'Active' : 'Inactive',
                tone: active ? UiBadgeTone.healthy : UiBadgeTone.noTelemetry,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(item.email, style: UiText.body),
          const SizedBox(height: 8),
          Text(
            'Role: ${item.role}  ?  Created: ${item.createdAt ?? '—'}  ?  Updated: ${item.updatedAt ?? '—'}',
            style: UiText.helper,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _loading ? null : () => _openEditDialog(item),
                style: uiSecondaryButton(),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
              OutlinedButton.icon(
                onPressed: _loading
                    ? null
                    : () => _setStatus(
                          item: item,
                          status: active ? 'inactive' : 'active',
                        ),
                style: uiSecondaryButton(),
                icon: Icon(active
                    ? Icons.pause_circle_outline
                    : Icons.play_circle_outline),
                label: Text(active ? 'Deactivate' : 'Activate'),
              ),
              OutlinedButton.icon(
                onPressed: _loading ? null : () => _confirmDelete(item),
                style: uiDangerButton(),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _loadAdmins() async {
    if (!_hasApi) {
      setState(() {
        _items = const <AdminItem>[];
        _error = 'API base URL missing.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final resp = await http.get(
        Uri.parse('${widget.apiBaseUrl}/api/admins'),
        headers: _adminHeaders(),
      );

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception(
            _extractError(resp.body, fallback: 'Failed to load admins'));
      }

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = (json['items'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(AdminItem.fromJson)
          .toList(growable: false);

      if (!mounted) return;
      setState(() => _items = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openCreateDialog() async {
    final result = await _showAdminFormDialog();
    if (result == null) return;
    await _createAdmin(result);
  }

  Future<void> _openEditDialog(AdminItem item) async {
    final result = await _showAdminFormDialog(existing: item);
    if (result == null) return;
    await _updateAdmin(adminId: item.adminId, data: result);
  }

  Future<AdminFormData?> _showAdminFormDialog({AdminItem? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final emailCtrl = TextEditingController(text: existing?.email ?? '');
    String role = existing?.role ?? 'admin';

    final data = await showDialog<AdminFormData>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(existing == null ? 'Add Admin' : 'Edit Admin'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: role,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: const [
                      DropdownMenuItem(value: 'admin', child: Text('admin')),
                      DropdownMenuItem(
                          value: 'super_admin', child: Text('super_admin')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => role = value);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    final email = emailCtrl.text.trim();
                    if (name.isEmpty || email.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Name and email are required.')),
                      );
                      return;
                    }
                    Navigator.of(context).pop(
                        AdminFormData(name: name, email: email, role: role));
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    nameCtrl.dispose();
    emailCtrl.dispose();
    return data;
  }

  Future<void> _createAdmin(AdminFormData data) async {
    await _runAction(() async {
      final resp = await http.post(
        Uri.parse('${widget.apiBaseUrl}/api/admins'),
        headers: _adminHeaders(contentTypeJson: true),
        body: jsonEncode({
          'name': data.name,
          'email': data.email,
          'role': data.role,
          'status': 'active',
        }),
      );

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception(
            _extractError(resp.body, fallback: 'Failed to create admin'));
      }
      await _loadAdmins();
    });
  }

  Future<void> _updateAdmin(
      {required String adminId, required AdminFormData data}) async {
    await _runAction(() async {
      final resp = await http.post(
        Uri.parse('${widget.apiBaseUrl}/api/admins/$adminId'),
        headers: _adminHeaders(contentTypeJson: true),
        body: jsonEncode({
          'name': data.name,
          'email': data.email,
          'role': data.role,
        }),
      );

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception(
            _extractError(resp.body, fallback: 'Failed to update admin'));
      }
      await _loadAdmins();
    });
  }

  Future<void> _setStatus(
      {required AdminItem item, required String status}) async {
    await _runAction(() async {
      final resp = await http.post(
        Uri.parse('${widget.apiBaseUrl}/api/admins/${item.adminId}/status'),
        headers: _adminHeaders(contentTypeJson: true),
        body: jsonEncode({'status': status}),
      );

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception(
            _extractError(resp.body, fallback: 'Failed to update status'));
      }
      await _loadAdmins();
    });
  }

  Future<void> _confirmDelete(AdminItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Admin'),
        content: Text('Delete ${item.name} (${item.email})?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await _runAction(() async {
      final resp = await http.delete(
        Uri.parse('${widget.apiBaseUrl}/api/admins/${item.adminId}'),
        headers: _adminHeaders(),
      );

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception(
            _extractError(resp.body, fallback: 'Failed to delete admin'));
      }
      await _loadAdmins();
    });
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Map<String, String> _adminHeaders({bool contentTypeJson = false}) {
    return {
      if (contentTypeJson) 'Content-Type': 'application/json',
      'x-user-role': 'Admin',
      'x-user-id': widget.adminHeaderUserId,
    };
  }

  String _extractError(String body, {required String fallback}) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return json['error']?.toString() ??
          json['message']?.toString() ??
          fallback;
    } catch (_) {
      return fallback;
    }
  }
}

class _AdminSummaryRow extends StatelessWidget {
  const _AdminSummaryRow({
    required this.total,
    required this.active,
    required this.inactive,
  });

  final int total;
  final int active;
  final int inactive;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 980
            ? (constraints.maxWidth - UiSpace.gap * 2) / 3
            : constraints.maxWidth >= 680
                ? (constraints.maxWidth - UiSpace.gap) / 2
                : constraints.maxWidth;
        return Wrap(
          spacing: UiSpace.gap,
          runSpacing: UiSpace.gap,
          children: [
            _summaryCard('Total admins', '$total', UiBadgeTone.stable, width),
            _summaryCard(
                'Active admins', '$active', UiBadgeTone.healthy, width),
            _summaryCard(
                'Inactive admins', '$inactive', UiBadgeTone.noTelemetry, width),
          ],
        );
      },
    );
  }

  Widget _summaryCard(
      String label, String value, UiBadgeTone tone, double width) {
    return SizedBox(
      width: width,
      child: UiCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: UiText.helper),
                  const SizedBox(height: 6),
                  Text(value, style: UiText.sectionTitle),
                ],
              ),
            ),
            UiBadge(label: label, tone: tone),
          ],
        ),
      ),
    );
  }
}

class AdminItem {
  const AdminItem({
    required this.adminId,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    this.createdAt,
    this.updatedAt,
  });

  final String adminId;
  final String name;
  final String email;
  final String role;
  final String status;
  final String? createdAt;
  final String? updatedAt;

  factory AdminItem.fromJson(Map<String, dynamic> json) {
    return AdminItem(
      adminId: json['adminId']?.toString() ?? '',
      name: json['name']?.toString() ?? '—',
      email: json['email']?.toString() ?? '—',
      role: json['role']?.toString() ?? 'admin',
      status: json['status']?.toString() ?? 'inactive',
      createdAt: json['createdAt']?.toString(),
      updatedAt: json['updatedAt']?.toString(),
    );
  }
}

class AdminFormData {
  const AdminFormData({
    required this.name,
    required this.email,
    required this.role,
  });

  final String name;
  final String email;
  final String role;
}
