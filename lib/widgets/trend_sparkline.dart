import 'dart:math' as math;

import 'package:flutter/material.dart';

class TrendSparkline extends StatefulWidget {
  const TrendSparkline({
    super.key,
    required this.values,
    required this.color,
    this.timestamps,
    this.xTicks,
    this.warningThreshold,
    this.criticalThreshold,
    this.metricLabel = 'Value',
    this.yAxisUnit = '',
    this.showPoints = true,
    this.timeLabelBuilder,
    this.valueLabelBuilder,
  });

  final List<double> values;
  final Color color;
  final List<DateTime>? timestamps;
  final List<DateTime>? xTicks;
  final double? warningThreshold;
  final double? criticalThreshold;
  final String metricLabel;
  final String yAxisUnit;
  final bool showPoints;
  final String Function(DateTime value)? timeLabelBuilder;
  final String Function(double value)? valueLabelBuilder;

  @override
  State<TrendSparkline> createState() => _TrendSparklineState();
}

class _TrendSparklineState extends State<TrendSparkline> {
  int? _hoverIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.values.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 320.0;
        final height =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 220.0;
        final size = Size(width, math.max(150.0, height));
        final timestamps = _resolveTimestamps(widget.values.length);
        final geometry = _TrendGeometry.build(
          size: size,
          values: widget.values,
          timestamps: timestamps,
          warningThreshold: widget.warningThreshold,
          criticalThreshold: widget.criticalThreshold,
        );
        final xTicks = widget.xTicks ?? _defaultTicks(timestamps);
        final index = _hoverIndex;
        final activeIndex =
            index == null || index < 0 || index >= geometry.points.length
                ? null
                : index;
        final point = activeIndex == null ? null : geometry.points[activeIndex];

        return MouseRegion(
          onHover: (event) {
            final next = _nearestIndex(geometry, event.localPosition);
            if (next != _hoverIndex) {
              setState(() => _hoverIndex = next);
            }
          },
          onExit: (_) => setState(() => _hoverIndex = null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              final next = _nearestIndex(geometry, details.localPosition);
              setState(() => _hoverIndex = next);
            },
            child: Stack(
              children: [
                RepaintBoundary(
                  child: CustomPaint(
                    size: size,
                    painter: _SparklinePainter(
                      geometry: geometry,
                      color: widget.color,
                      xTicks: xTicks,
                      xTickLabelBuilder: (dt) => _formatTime(dt),
                      yAxisUnit: widget.yAxisUnit,
                      warningThreshold: widget.warningThreshold,
                      criticalThreshold: widget.criticalThreshold,
                      showPoints: widget.showPoints,
                      highlightIndex: _hoverIndex,
                    ),
                  ),
                ),
                if (point != null)
                  Positioned(
                    left: _tooltipLeft(size.width, point.dx),
                    top: _tooltipTop(point.dy),
                    child: _TrendTooltip(
                      timeLabel: _formatTime(timestamps[activeIndex!]),
                      metricLine:
                          '${widget.metricLabel}: ${_formatValue(widget.values[activeIndex])}',
                      status: _statusFor(widget.values[activeIndex]),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<DateTime> _resolveTimestamps(int count) {
    final provided = widget.timestamps;
    if (provided != null && provided.length == count) {
      return provided;
    }
    final end = DateTime.now();
    if (count == 1) return <DateTime>[end];
    return List<DateTime>.generate(
      count,
      (i) => end.subtract(Duration(minutes: (count - 1 - i) * 5)),
      growable: false,
    );
  }

  List<DateTime> _defaultTicks(List<DateTime> timestamps) {
    if (timestamps.isEmpty) return const <DateTime>[];
    if (timestamps.length <= 6) return timestamps;
    final step = (timestamps.length - 1) / 5;
    return List<DateTime>.generate(
      6,
      (i) {
        final idx = (i * step).round().clamp(0, timestamps.length - 1);
        return timestamps[idx];
      },
      growable: false,
    );
  }

  int _nearestIndex(_TrendGeometry geometry, Offset local) {
    var nearest = 0;
    var best = double.infinity;
    for (var i = 0; i < geometry.points.length; i++) {
      final dx = (geometry.points[i].dx - local.dx).abs();
      if (dx < best) {
        best = dx;
        nearest = i;
      }
    }
    return nearest;
  }

  String _formatTime(DateTime value) {
    final builder = widget.timeLabelBuilder;
    if (builder != null) return builder(value);
    final hh = value.hour.toString().padLeft(2, '0');
    final mm = value.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _formatValue(double value) {
    final builder = widget.valueLabelBuilder;
    if (builder != null) return builder(value);
    return value.toStringAsFixed(1);
  }

  String _statusFor(double value) {
    final critical = widget.criticalThreshold;
    final warning = widget.warningThreshold;
    if (critical != null && value >= critical) return 'Critical';
    if (warning != null && value >= warning) return 'Warning';
    return 'Stable';
  }

  double _tooltipLeft(double width, double x) {
    const tooltipWidth = 220.0;
    final preferred = x + 12;
    final max = width - tooltipWidth - 8;
    if (preferred <= max) return preferred.clamp(8, max);
    return (x - tooltipWidth - 12).clamp(8, max);
  }

  double _tooltipTop(double y) {
    final top = y - 104;
    return top < 8 ? 8 : top;
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.geometry,
    required this.color,
    required this.xTicks,
    required this.xTickLabelBuilder,
    required this.yAxisUnit,
    required this.warningThreshold,
    required this.criticalThreshold,
    required this.showPoints,
    required this.highlightIndex,
  });

  final _TrendGeometry geometry;
  final Color color;
  final List<DateTime> xTicks;
  final String Function(DateTime value) xTickLabelBuilder;
  final String yAxisUnit;
  final double? warningThreshold;
  final double? criticalThreshold;
  final bool showPoints;
  final int? highlightIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final plotRect = geometry.plotRect;
    _drawGrid(canvas, plotRect);
    _drawThresholds(canvas, plotRect);
    _drawAxes(canvas, plotRect);
    _drawAreaAndLine(canvas, plotRect);
    if (showPoints) {
      _drawPoints(canvas);
    }
    _drawYLabels(canvas, plotRect);
    _drawXTicks(canvas, plotRect);
    _drawHoverGuide(canvas, plotRect);
  }

  void _drawGrid(Canvas canvas, Rect plotRect) {
    final gridPaint = Paint()
      ..color = const Color(0xFFE5EEF2)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final t = i / 4;
      final y = plotRect.top + (plotRect.height * t);
      canvas.drawLine(
        Offset(plotRect.left, y),
        Offset(plotRect.right, y),
        gridPaint,
      );
    }
  }

  void _drawThresholds(Canvas canvas, Rect plotRect) {
    if (warningThreshold != null) {
      final y = geometry.yForValue(warningThreshold!);
      final warningPaint = Paint()
        ..color = const Color(0xFFE09D25).withValues(alpha: 0.82)
        ..strokeWidth = 1.2;
      canvas.drawLine(
          Offset(plotRect.left, y), Offset(plotRect.right, y), warningPaint);
    }
    if (criticalThreshold != null) {
      final y = geometry.yForValue(criticalThreshold!);
      final criticalPaint = Paint()
        ..color = const Color(0xFFC93C3C).withValues(alpha: 0.82)
        ..strokeWidth = 1.2;
      canvas.drawLine(
          Offset(plotRect.left, y), Offset(plotRect.right, y), criticalPaint);
    }
  }

  void _drawAxes(Canvas canvas, Rect plotRect) {
    final axisPaint = Paint()
      ..color = const Color(0xFFCCDAE1)
      ..strokeWidth = 1.2;
    canvas.drawLine(
      Offset(plotRect.left, plotRect.top),
      Offset(plotRect.left, plotRect.bottom),
      axisPaint,
    );
    canvas.drawLine(
      Offset(plotRect.left, plotRect.bottom),
      Offset(plotRect.right, plotRect.bottom),
      axisPaint,
    );
  }

  void _drawAreaAndLine(Canvas canvas, Rect plotRect) {
    final points = geometry.points;
    if (points.isEmpty) return;

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      linePath.lineTo(point.dx, point.dy);
    }

    final fillPath = Path.from(linePath)
      ..lineTo(plotRect.right, plotRect.bottom)
      ..lineTo(plotRect.left, plotRect.bottom)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.02)],
      ).createShader(plotRect);

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(linePath, linePaint);
  }

  void _drawPoints(Canvas canvas) {
    final points = geometry.points;
    for (var i = 0; i < points.length; i++) {
      final value = geometry.values[i];
      final isHover = i == highlightIndex;
      final tone = _toneForValue(value);
      final pointPaint = Paint()..color = tone;
      final strokePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = isHover ? 2.4 : 1.8;
      final radius = isHover ? 4.8 : 3.8;
      canvas.drawCircle(points[i], radius, pointPaint);
      canvas.drawCircle(points[i], radius, strokePaint);
    }
  }

  void _drawYLabels(Canvas canvas, Rect plotRect) {
    final labels = <MapEntry<double, String>>[
      MapEntry(geometry.maxVal, _formatYAxisValue(geometry.maxVal)),
      MapEntry((geometry.maxVal + geometry.minVal) / 2,
          _formatYAxisValue((geometry.maxVal + geometry.minVal) / 2)),
      MapEntry(geometry.minVal, _formatYAxisValue(geometry.minVal)),
    ];
    for (final item in labels) {
      final y = geometry.yForValue(item.key);
      _paintText(
        canvas,
        text: item.value,
        offset: Offset(6, y - 8),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: Color(0xFF60757F),
        ),
      );
    }
  }

  void _drawXTicks(Canvas canvas, Rect plotRect) {
    final tickPaint = Paint()
      ..color = const Color(0xFFCCDAE1)
      ..strokeWidth = 1;
    for (final tick in xTicks) {
      final x = geometry.xForTime(tick);
      if (x < plotRect.left - 0.5 || x > plotRect.right + 0.5) continue;
      canvas.drawLine(
        Offset(x, plotRect.bottom),
        Offset(x, plotRect.bottom + 4),
        tickPaint,
      );
      final label = xTickLabelBuilder(tick);
      final textSpan = TextSpan(
        text: label,
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFF60757F),
          fontWeight: FontWeight.w500,
        ),
      );
      final painter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(x - painter.width / 2, plotRect.bottom + 8));
    }
  }

  void _drawHoverGuide(Canvas canvas, Rect plotRect) {
    final idx = highlightIndex;
    if (idx == null || idx < 0 || idx >= geometry.points.length) return;
    final point = geometry.points[idx];
    final guidePaint = Paint()
      ..color = const Color(0xFF8DA2AC)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(point.dx, plotRect.top),
      Offset(point.dx, plotRect.bottom),
      guidePaint,
    );
  }

  Color _toneForValue(double value) {
    if (criticalThreshold != null && value >= criticalThreshold!) {
      return const Color(0xFFC93C3C);
    }
    if (warningThreshold != null && value >= warningThreshold!) {
      return const Color(0xFFE09D25);
    }
    return color;
  }

  String _formatYAxisValue(double value) {
    final withUnit = yAxisUnit.trim().isNotEmpty;
    final number = value.abs() >= 100
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return withUnit ? '$number $yAxisUnit' : number;
  }

  void _paintText(
    Canvas canvas, {
    required String text,
    required Offset offset,
    required TextStyle style,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.geometry != geometry ||
        oldDelegate.color != color ||
        oldDelegate.warningThreshold != warningThreshold ||
        oldDelegate.criticalThreshold != criticalThreshold ||
        oldDelegate.showPoints != showPoints ||
        oldDelegate.highlightIndex != highlightIndex ||
        oldDelegate.yAxisUnit != yAxisUnit ||
        oldDelegate.xTicks != xTicks;
  }
}

class _TrendTooltip extends StatelessWidget {
  const _TrendTooltip({
    required this.timeLabel,
    required this.metricLine,
    required this.status,
  });

  final String timeLabel;
  final String metricLine;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 220,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFDCE8EE)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A2A3940),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: DefaultTextStyle(
          style: const TextStyle(
            color: Color(0xFF24343C),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Time: $timeLabel'),
              const SizedBox(height: 2),
              Text(metricLine),
              const SizedBox(height: 2),
              Text('Status: $status'),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendGeometry {
  _TrendGeometry({
    required this.plotRect,
    required this.points,
    required this.values,
    required this.timestamps,
    required this.minVal,
    required this.maxVal,
    required this.spread,
  });

  final Rect plotRect;
  final List<Offset> points;
  final List<double> values;
  final List<DateTime> timestamps;
  final double minVal;
  final double maxVal;
  final double spread;

  static _TrendGeometry build({
    required Size size,
    required List<double> values,
    required List<DateTime> timestamps,
    required double? warningThreshold,
    required double? criticalThreshold,
  }) {
    const leftPad = 56.0;
    const topPad = 10.0;
    const rightPad = 12.0;
    const bottomPad = 36.0;
    final plotRect = Rect.fromLTWH(
      leftPad,
      topPad,
      math.max(1.0, size.width - leftPad - rightPad),
      math.max(1.0, size.height - topPad - bottomPad),
    );

    var minVal = values.reduce(math.min);
    var maxVal = values.reduce(math.max);
    if (warningThreshold != null) {
      minVal = math.min(minVal, warningThreshold);
      maxVal = math.max(maxVal, warningThreshold);
    }
    if (criticalThreshold != null) {
      minVal = math.min(minVal, criticalThreshold);
      maxVal = math.max(maxVal, criticalThreshold);
    }
    var spread = maxVal - minVal;
    if (spread.abs() < 0.001) {
      spread = 1;
      minVal -= 0.5;
      maxVal += 0.5;
    }
    final pad = spread * 0.08;
    minVal -= pad;
    maxVal += pad;
    spread = maxVal - minVal;

    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final t = values.length == 1 ? 0.0 : i / (values.length - 1);
      final x = plotRect.left + plotRect.width * t;
      final y =
          plotRect.bottom - ((values[i] - minVal) / spread) * plotRect.height;
      points.add(Offset(x, y));
    }

    return _TrendGeometry(
      plotRect: plotRect,
      points: points,
      values: values,
      timestamps: timestamps,
      minVal: minVal,
      maxVal: maxVal,
      spread: spread,
    );
  }

  double xForTime(DateTime time) {
    if (timestamps.isEmpty) return plotRect.left;
    final firstMs = timestamps.first.millisecondsSinceEpoch.toDouble();
    final lastMs = timestamps.last.millisecondsSinceEpoch.toDouble();
    if ((lastMs - firstMs).abs() < 1) return plotRect.left + plotRect.width;
    final xRatio =
        ((time.millisecondsSinceEpoch - firstMs) / (lastMs - firstMs))
            .clamp(0.0, 1.0);
    return plotRect.left + plotRect.width * xRatio;
  }

  double yForValue(double value) {
    final ratio = ((value - minVal) / spread).clamp(0.0, 1.0);
    return plotRect.bottom - ratio * plotRect.height;
  }
}
