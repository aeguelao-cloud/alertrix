import 'package:flutter/material.dart';

import '../models/monitoring_models.dart';
import '../theme/severity_colors.dart';
import 'ui_kit.dart';

class AlertCard extends StatelessWidget {
  const AlertCard({
    super.key,
    required this.alertType,
    required this.deviceId,
    required this.zone,
    required this.measuredValue,
    required this.threshold,
    required this.timestamp,
    required this.status,
    required this.severity,
    this.occurrences,
    this.onOpen,
    this.onAcknowledge,
    this.acknowledgeBusy = false,
    this.compact = false,
  });

  final String alertType;
  final String deviceId;
  final String zone;
  final String measuredValue;
  final String threshold;
  final String timestamp;
  final String status;
  final SensorLevel severity;
  final int? occurrences;
  final VoidCallback? onOpen;
  final VoidCallback? onAcknowledge;
  final bool acknowledgeBusy;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final critical = severity == SensorLevel.critical;
    final tone = critical ? UiBadgeTone.critical : UiBadgeTone.warning;
    final accent = critical ? SeverityColors.critical : SeverityColors.warning;
    final valueColor =
        critical ? SeverityColors.criticalText : SeverityColors.warningText;
    final cardPadding = compact ? 10.0 : 14.0;
    final title = '$zone - $deviceId';
    final detailBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          measuredValue,
          style: UiText.body.copyWith(
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '$alertType - Threshold: $threshold',
          style: UiText.helper,
          maxLines: compact ? 3 : 2,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          timestamp,
          style: UiText.helper,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
    final actionButtons = Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        if (onOpen != null)
          TextButton(
            onPressed: onOpen,
            style: uiLinkButton(),
            child: const Text('View Details'),
          ),
        if (onAcknowledge != null)
          TextButton(
            onPressed: acknowledgeBusy ? null : onAcknowledge,
            style: uiLinkButton(),
            child: acknowledgeBusy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Acknowledge Incident'),
          ),
      ],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: accent, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(cardPadding, 6, cardPadding, cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (compact) ...[
              const SizedBox(height: 8),
              Text(
                title,
                style: UiText.cardTitle.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: UiColors.textStrong,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  UiSeverityPill(
                    label: critical ? 'Critical' : 'Warning',
                    tone: tone,
                  ),
                  Text(
                    status,
                    style: UiText.helper.copyWith(
                      fontWeight: FontWeight.w700,
                      color: UiColors.textBody,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              detailBlock,
            ] else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                minVerticalPadding: 8,
                title: Text(
                  title,
                  style: UiText.cardTitle.copyWith(
                    fontWeight: FontWeight.w800,
                    color: UiColors.textStrong,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: detailBlock,
                ),
                trailing: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      UiSeverityPill(
                        label: critical ? 'Critical' : 'Warning',
                        tone: tone,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: UiText.helper.copyWith(
                          fontWeight: FontWeight.w700,
                          color: UiColors.textBody,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (onOpen != null || onAcknowledge != null) ...[
              const SizedBox(height: 8),
              if (compact)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (occurrences != null) ...[
                      Text(
                        'Occurrences: $occurrences events',
                        style: UiText.helper,
                      ),
                      const SizedBox(height: 4),
                    ],
                    actionButtons,
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                        child: occurrences == null
                            ? const SizedBox.shrink()
                            : Text(
                                'Occurrences: $occurrences events',
                                style: UiText.helper,
                              )),
                    actionButtons,
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}
