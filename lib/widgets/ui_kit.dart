import 'package:flutter/material.dart';

import '../theme/severity_colors.dart';

class UiColors {
  static const pageBg = Color(0xFFEDF4F8);
  static const surface = Colors.white;
  static const surfaceAlt = Color(0xFFF6FAFC);
  static const surfaceTint = Color(0xFFE7F2F7);
  static const textStrong = Color(0xFF0E2832);
  static const textBody = Color(0xFF34505D);
  static const textMuted = Color(0xFF637B86);
  static const border = Color(0xFFD3E0E8);
  static const borderStrong = Color(0xFFB6C9D4);
  static const tableHeader = Color(0xFFE9F1F6);
  static const tableRow = Color(0xFFF8FBFD);

  static const brand = Color(0xFF0A6E83);
  static const brandDark = Color(0xFF122F3A);
  static const brandSoft = Color(0xFFE2F2F6);
  static const info = Color(0xFF3464C7);
  static const danger = SeverityColors.critical;
  static const warning = SeverityColors.warning;
  static const healthy = SeverityColors.normal;
  static const neutral = Color(0xFF627985);
}

class UiSpace {
  static const page = 24.0;
  static const section = 24.0;
  static const card = 16.0;
  static const gap = 14.0;
}

const double _uiCompactBreakpoint = 1024;

bool uiIsCompactLayout(BuildContext context) {
  return MediaQuery.sizeOf(context).width < _uiCompactBreakpoint;
}

EdgeInsets uiPagePadding(BuildContext context) {
  final compact = uiIsCompactLayout(context);
  return EdgeInsets.all(compact ? 14 : UiSpace.page);
}

double uiSectionSpacing(BuildContext context) {
  return uiIsCompactLayout(context) ? 18 : UiSpace.section;
}

class UiRadius {
  static const big = 20.0;
  static const card = 16.0;
  static const input = 12.0;
  static const button = 12.0;
  static const pill = 999.0;
}

class UiText {
  static const pageTitle = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w800,
    color: UiColors.textStrong,
    height: 1.08,
  );
  static const sectionTitle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    color: UiColors.textStrong,
    height: 1.15,
  );
  static const cardTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: UiColors.textStrong,
  );
  static const body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: UiColors.textBody,
    height: 1.45,
  );
  static const helper = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: UiColors.textMuted,
    height: 1.4,
  );
  static const bigNumber = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.w800,
    color: UiColors.textStrong,
    height: 1.02,
  );
  static const label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w800,
    color: UiColors.textMuted,
    letterSpacing: 0,
    height: 1.2,
  );
}

ButtonStyle uiPrimaryButton() {
  return FilledButton.styleFrom(
    backgroundColor: UiColors.brand,
    foregroundColor: Colors.white,
    minimumSize: const Size(0, 48),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(UiRadius.button),
    ),
    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
  );
}

ButtonStyle uiSecondaryButton() {
  return OutlinedButton.styleFrom(
    foregroundColor: UiColors.textStrong,
    backgroundColor: Colors.white,
    side: const BorderSide(color: UiColors.borderStrong),
    minimumSize: const Size(0, 46),
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(UiRadius.button),
    ),
    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
  );
}

ButtonStyle uiDangerButton() {
  return OutlinedButton.styleFrom(
    foregroundColor: UiColors.danger,
    backgroundColor: Colors.white,
    side: const BorderSide(color: Color(0xFFF2B2B2)),
    minimumSize: const Size(0, 46),
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(UiRadius.button),
    ),
    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
  );
}

ButtonStyle uiLinkButton() {
  return TextButton.styleFrom(
    foregroundColor: UiColors.brand,
    minimumSize: const Size(0, 0),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
  );
}

enum UiBadgeTone {
  healthy,
  stable,
  warning,
  critical,
  offline,
  noTelemetry,
}

Color uiToneColor(UiBadgeTone tone) {
  return switch (tone) {
    UiBadgeTone.healthy => UiColors.healthy,
    UiBadgeTone.stable => UiColors.brand,
    UiBadgeTone.warning => UiColors.warning,
    UiBadgeTone.critical => UiColors.danger,
    UiBadgeTone.offline => const Color(0xFF8D5353),
    UiBadgeTone.noTelemetry => UiColors.neutral,
  };
}

Color uiToneSoftColor(UiBadgeTone tone) {
  return switch (tone) {
    UiBadgeTone.healthy => SeverityColors.normalSoft,
    UiBadgeTone.stable => const Color(0xFFE5F1F3),
    UiBadgeTone.warning => SeverityColors.warningSoft,
    UiBadgeTone.critical => SeverityColors.criticalSoft,
    UiBadgeTone.offline => const Color(0xFFF4E8E8),
    UiBadgeTone.noTelemetry => const Color(0xFFF0F4F6),
  };
}

Color uiToneBorderColor(UiBadgeTone tone) {
  return switch (tone) {
    UiBadgeTone.healthy => SeverityColors.normalBorder,
    UiBadgeTone.stable => const Color(0xFFB9D7DD),
    UiBadgeTone.warning => SeverityColors.warningBorder,
    UiBadgeTone.critical => SeverityColors.criticalBorder,
    UiBadgeTone.offline => const Color(0xFFD7BABA),
    UiBadgeTone.noTelemetry => const Color(0xFFD8E1E6),
  };
}

class UiBadge extends StatelessWidget {
  const UiBadge({
    super.key,
    required this.label,
    required this.tone,
  });

  final String label;
  final UiBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: uiToneSoftColor(tone),
        borderRadius: BorderRadius.circular(UiRadius.pill),
        border:
            Border.all(color: uiToneBorderColor(tone).withValues(alpha: 0.7)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: uiToneColor(tone),
        ),
      ),
    );
  }
}

class UiCard extends StatelessWidget {
  const UiCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(UiSpace.card),
    this.big = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final borderAlpha = big ? 0.74 : 0.62;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: UiColors.surface,
        borderRadius: BorderRadius.circular(big ? UiRadius.big : UiRadius.card),
        border: Border.all(
          color: UiColors.border.withValues(alpha: borderAlpha),
        ),
        boxShadow: [
          BoxShadow(
            color:
                const Color(0xFF15303A).withValues(alpha: big ? 0.085 : 0.055),
            blurRadius: big ? 24 : 14,
            offset: big ? const Offset(0, 10) : const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class UiEmptyState extends StatelessWidget {
  const UiEmptyState({
    super.key,
    required this.title,
    required this.subtitle,
    this.reasons = const <String>[],
    this.primaryAction,
    this.secondaryAction,
    this.icon = Icons.inbox_outlined,
  });

  final String title;
  final String subtitle;
  final List<String> reasons;
  final Widget? primaryAction;
  final Widget? secondaryAction;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 34,
              color: const Color(0xFF7B8D95),
            ),
            const SizedBox(height: 10),
            Text(title, style: UiText.cardTitle),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: UiText.body,
              textAlign: TextAlign.center,
            ),
            if (reasons.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...reasons.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text('- $item', style: UiText.helper),
                ),
              ),
            ],
            if (primaryAction != null || secondaryAction != null) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (primaryAction != null) primaryAction!,
                  if (secondaryAction != null) secondaryAction!,
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class UiPageHeader extends StatelessWidget {
  const UiPageHeader({
    super.key,
    required this.systemName,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String systemName;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final compact = uiIsCompactLayout(context);
    final titleStyle = UiText.pageTitle.copyWith(
      fontSize: compact ? 25 : UiText.pageTitle.fontSize,
      height: compact ? 1.16 : UiText.pageTitle.height,
    );
    if (compact && trailing != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: UiColors.surface,
              borderRadius: BorderRadius.circular(UiRadius.card),
              border: Border.all(color: UiColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(systemName, style: UiText.helper),
                const SizedBox(height: 4),
                Text(title, style: titleStyle),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(subtitle!, style: UiText.body),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          trailing!,
        ],
      );
    }
    return Container(
      width: double.infinity,
      padding:
          EdgeInsets.fromLTRB(compact ? 14 : 16, 14, compact ? 14 : 16, 14),
      decoration: BoxDecoration(
        color: UiColors.surface,
        borderRadius: BorderRadius.circular(UiRadius.big),
        border: Border.all(color: UiColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(systemName, style: UiText.helper),
                const SizedBox(height: 4),
                Text(title, style: titleStyle),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(subtitle!, style: UiText.body),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 14),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class UiTableHeaderRow extends StatelessWidget {
  const UiTableHeaderRow({
    super.key,
    required this.children,
    this.height = 46,
  });

  final List<Widget> children;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(
        color: UiColors.tableHeader,
        borderRadius: BorderRadius.circular(UiRadius.input),
        border: Border.all(color: UiColors.border.withValues(alpha: 0.8)),
      ),
      child: Row(children: children),
    );
  }
}

class UiTableBodyRow extends StatefulWidget {
  const UiTableBodyRow({
    super.key,
    required this.children,
    this.height = 50,
    this.margin,
  });

  final List<Widget> children;
  final double height;
  final EdgeInsetsGeometry? margin;

  @override
  State<UiTableBodyRow> createState() => _UiTableBodyRowState();
}

class _UiTableBodyRowState extends State<UiTableBodyRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        height: widget.height,
        margin: widget.margin ?? EdgeInsets.zero,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        decoration: BoxDecoration(
          color: _hovering ? Colors.grey.shade50 : Colors.white,
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade200, width: 1),
          ),
        ),
        child: Row(children: widget.children),
      ),
    );
  }
}

class UiSeverityPill extends StatelessWidget {
  const UiSeverityPill({
    super.key,
    required this.label,
    required this.tone,
  });

  final String label;
  final UiBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final critical = tone == UiBadgeTone.critical;
    final bg =
        critical ? SeverityColors.criticalSoft : SeverityColors.warningSoft;
    final fg =
        critical ? SeverityColors.criticalText : SeverityColors.warningText;
    final border =
        critical ? SeverityColors.criticalBorder : SeverityColors.warningBorder;

    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(UiRadius.pill),
        border: Border.all(color: border),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: fg,
          height: 1,
        ),
      ),
    );
  }
}

class UiResponsiveTable extends StatelessWidget {
  const UiResponsiveTable({
    super.key,
    required this.child,
    required this.minWidth,
  });

  final Widget child;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= minWidth) return child;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: minWidth,
            child: child,
          ),
        );
      },
    );
  }
}
