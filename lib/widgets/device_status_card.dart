import 'package:flutter/material.dart';

import 'status_badge.dart';
import 'ui_kit.dart';

class DeviceStatusCard extends StatelessWidget {
  const DeviceStatusCard({
    super.key,
    required this.deviceName,
    required this.deviceId,
    required this.zone,
    required this.statusLabel,
    required this.statusTone,
    required this.latestTelemetry,
    this.readingSummary,
    this.icon = Icons.sensors_rounded,
    this.primaryActionLabel,
    this.onPrimaryAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  final String deviceName;
  final String deviceId;
  final String zone;
  final String statusLabel;
  final UiBadgeTone statusTone;
  final String latestTelemetry;
  final String? readingSummary;
  final IconData icon;
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final color = uiToneColor(statusTone);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: UiColors.surface,
        borderRadius: BorderRadius.circular(UiRadius.card),
        border: Border.all(
          color: uiToneBorderColor(statusTone).withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: uiToneSoftColor(statusTone),
                  borderRadius: BorderRadius.circular(UiRadius.input),
                ),
                child: Icon(icon, size: 19, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(deviceName, style: UiText.cardTitle),
                    const SizedBox(height: 3),
                    Text('$deviceId | $zone', style: UiText.helper),
                  ],
                ),
              ),
              StatusBadge(
                label: statusLabel,
                tone: statusTone,
                icon: statusTone == UiBadgeTone.offline
                    ? Icons.wifi_off_rounded
                    : Icons.wifi_rounded,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _DeviceFact(label: 'Latest telemetry', value: latestTelemetry),
              if (readingSummary != null)
                _DeviceFact(label: 'Reading', value: readingSummary!),
            ],
          ),
          if (primaryActionLabel != null || secondaryActionLabel != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (primaryActionLabel != null)
                  TextButton(
                    onPressed: onPrimaryAction,
                    style: uiLinkButton(),
                    child: Text(primaryActionLabel!),
                  ),
                if (secondaryActionLabel != null)
                  TextButton(
                    onPressed: onSecondaryAction,
                    style: uiLinkButton(),
                    child: Text(secondaryActionLabel!),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DeviceFact extends StatelessWidget {
  const _DeviceFact({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 130),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: UiText.label),
          const SizedBox(height: 3),
          Text(value, style: UiText.body.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
