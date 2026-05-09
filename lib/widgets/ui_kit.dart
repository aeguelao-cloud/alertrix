import 'package:flutter/material.dart';

class UiColors {
  static const pageBg = Color(0xFFF2F5F7);
  static const surface = Colors.white;
  static const textStrong = Color(0xFF142229);
  static const textBody = Color(0xFF425962);
  static const textMuted = Color(0xFF6D818A);
  static const border = Color(0xFFD9E3E8);
  static const tableHeader = Color(0xFFEAF1F4);
  static const tableRow = Color(0xFFF8FBFC);

  static const brand = Color(0xFF0A7E8C);
  static const danger = Color(0xFFC93C3C);
  static const warning = Color(0xFFE09D25);
  static const healthy = Color(0xFF2D8D4D);
  static const neutral = Color(0xFF657A83);
}

class UiSpace {
  static const page = 24.0;
  static const section = 24.0;
  static const card = 20.0;
  static const gap = 12.0;
}

const double _uiCompactBreakpoint = 760;

bool uiIsCompactLayout(BuildContext context) {
  return MediaQuery.sizeOf(context).width < _uiCompactBreakpoint;
}

EdgeInsets uiPagePadding(BuildContext context) {
  final compact = uiIsCompactLayout(context);
  return EdgeInsets.all(compact ? 12 : UiSpace.page);
}

double uiSectionSpacing(BuildContext context) {
  return uiIsCompactLayout(context) ? 16 : UiSpace.section;
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
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: UiColors.textStrong,
    height: 1.1,
  );
  static const sectionTitle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: UiColors.textStrong,
    height: 1.2,
  );
  static const cardTitle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: UiColors.textStrong,
  );
  static const body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: UiColors.textBody,
    height: 1.4,
  );
  static const helper = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: UiColors.textMuted,
    height: 1.35,
  );
  static const bigNumber = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.w700,
    color: UiColors.textStrong,
    height: 1.05,
  );
}

ButtonStyle uiPrimaryButton() {
  return FilledButton.styleFrom(
    backgroundColor: UiColors.brand,
    foregroundColor: Colors.white,
    minimumSize: const Size(0, 44),
    padding: const EdgeInsets.symmetric(horizontal: 14),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(UiRadius.button),
    ),
    textStyle: UiText.cardTitle,
  );
}

ButtonStyle uiSecondaryButton() {
  return OutlinedButton.styleFrom(
    foregroundColor: UiColors.textStrong,
    side: const BorderSide(color: UiColors.border),
    minimumSize: const Size(0, 44),
    padding: const EdgeInsets.symmetric(horizontal: 14),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(UiRadius.button),
    ),
    textStyle: UiText.cardTitle,
  );
}

ButtonStyle uiDangerButton() {
  return OutlinedButton.styleFrom(
    foregroundColor: UiColors.danger,
    side: const BorderSide(color: Color(0xFFF2B2B2)),
    minimumSize: const Size(0, 44),
    padding: const EdgeInsets.symmetric(horizontal: 14),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(UiRadius.button),
    ),
    textStyle: UiText.cardTitle,
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
    final (bg, fg) = switch (tone) {
      UiBadgeTone.healthy => (const Color(0xFFE7F7EE), UiColors.healthy),
      UiBadgeTone.stable => (const Color(0xFFE9F1EE), const Color(0xFF49645A)),
      UiBadgeTone.warning => (const Color(0xFFFFF4E2), UiColors.warning),
      UiBadgeTone.critical => (const Color(0xFFFFEBEB), UiColors.danger),
      UiBadgeTone.offline => (const Color(0xFFF2EAEB), const Color(0xFF8E5C5C)),
      UiBadgeTone.noTelemetry => (const Color(0xFFF0F4F6), UiColors.neutral),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(UiRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: fg,
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
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: UiColors.surface,
        borderRadius: BorderRadius.circular(big ? UiRadius.big : UiRadius.card),
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
      fontSize: compact ? 24 : UiText.pageTitle.fontSize,
      height: compact ? 1.16 : UiText.pageTitle.height,
    );
    return Row(
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
        if (trailing != null) trailing!,
      ],
    );
  }
}

class UiTableHeaderRow extends StatelessWidget {
  const UiTableHeaderRow({
    super.key,
    required this.children,
    this.height = 44,
  });

  final List<Widget> children;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: UiColors.tableHeader,
        borderRadius: BorderRadius.circular(UiRadius.input),
      ),
      child: Row(children: children),
    );
  }
}

class UiTableBodyRow extends StatelessWidget {
  const UiTableBodyRow({
    super.key,
    required this.children,
    this.height = 46,
    this.margin,
  });

  final List<Widget> children;
  final double height;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      margin: margin ?? const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: UiColors.tableRow,
        borderRadius: BorderRadius.circular(UiRadius.input),
      ),
      child: Row(children: children),
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
