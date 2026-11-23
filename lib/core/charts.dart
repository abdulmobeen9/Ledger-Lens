import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../domain/analytics.dart';
import 'format.dart';
import 'theme.dart';

class CashFlowChart extends StatelessWidget {
  const CashFlowChart({super.key, required this.points, this.height = 180});
  final List<MonthPoint> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    var maxValue = 0.0;
    for (final p in points) {
      if (p.income > maxValue) maxValue = p.income;
      if (p.expense > maxValue) maxValue = p.expense;
    }
    final maxY = maxValue <= 0 ? 1.0 : maxValue * 1.2;
    final labelStyle = TextStyle(fontSize: 11, color: context.mutedText, fontWeight: FontWeight.w600);
    final hidden = const AxisTitles(sideTitles: SideTitles(showTitles: false));

    BarChartRodData rod(double value, Color color) => BarChartRodData(
          toY: value,
          color: color,
          width: 9,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
        );

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          alignment: BarChartAlignment.spaceAround,
          barTouchData: BarTouchData(enabled: false),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY / 4,
            getDrawingHorizontalLine: (_) => FlLine(color: context.borderColor, strokeWidth: 1, dashArray: [4, 4]),
          ),
          titlesData: FlTitlesData(
            show: true,
            leftTitles: hidden,
            rightTitles: hidden,
            topTitles: hidden,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= points.length) return const SizedBox.shrink();
                  return SideTitleWidget(
                    meta: meta,
                    space: 6,
                    child: Text(Dates.monthShort(points[index].month), style: labelStyle),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < points.length; i++)
              BarChartGroupData(
                x: i,
                barsSpace: 4,
                barRods: [rod(points[i].income, AppColors.income), rod(points[i].expense, AppColors.expense)],
              ),
          ],
        ),
      ),
    );
  }
}

class DonutSlice {
  const DonutSlice(this.label, this.value, this.color);
  final String label;
  final double value;
  final Color color;
}

class CategoryDonut extends StatelessWidget {
  const CategoryDonut({super.key, required this.slices, required this.centerTop, required this.centerBottom, this.size = 190});
  final List<DonutSlice> slices;
  final String centerTop, centerBottom;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: size,
        width: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            PieChart(
              PieChartData(
                startDegreeOffset: -90,
                sectionsSpace: 3,
                centerSpaceRadius: size * 0.31,
                borderData: FlBorderData(show: false),
                pieTouchData: PieTouchData(enabled: false),
                sections: [
                  for (final s in slices)
                    PieChartSectionData(
                      value: s.value <= 0 ? 0.0001 : s.value,
                      color: s.color,
                      radius: size * 0.13,
                      showTitle: false,
                    ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(centerTop, style: TextStyle(fontSize: 11, color: context.mutedText, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(centerBottom, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ],
            ),
          ],
        ),
      );
}
