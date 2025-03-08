import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/ticker.dart';

class ChartWidget extends StatelessWidget {
  final List<Ticker> tickerHistory;

  const ChartWidget({Key? key, required this.tickerHistory}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 确保有足够的数据点
    if (tickerHistory.length < 2) {
      return const Center(child: Text('等待更多数据...'));
    }

    // 获取价格范围，用于设置图表Y轴范围
    final prices = tickerHistory.map((ticker) => ticker.currentPrice).toList();
    final minY = prices.reduce((a, b) => a < b ? a : b) * 0.999;
    final maxY = prices.reduce((a, b) => a > b ? a : b) * 1.001;

    // 确定价格是上涨还是下跌
    final firstPrice = tickerHistory.first.currentPrice;
    final lastPrice = tickerHistory.last.currentPrice;
    final isPriceUp = lastPrice >= firstPrice;

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: (maxY - minY) / 5,
          verticalInterval: 1,
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval:
                  tickerHistory.length > 20 ? tickerHistory.length / 5 : 1,
              getTitlesWidget: (value, meta) {
                if (value.toInt() % 5 != 0 && tickerHistory.length > 20) {
                  return const SizedBox();
                }

                if (value.toInt() >= 0 &&
                    value.toInt() < tickerHistory.length) {
                  // 简化显示，只显示部分时间点
                  return const SizedBox();
                }
                return const SizedBox();
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: (maxY - minY) / 5,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toStringAsFixed(2),
                  style: const TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                );
              },
              reservedSize: 42,
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: const Color(0xff37434d), width: 1),
        ),
        minX: 0,
        maxX: tickerHistory.length.toDouble() - 1,
        minY: minY,
        maxY: maxY,
        lineBarsData: [
          LineChartBarData(
            spots: List.generate(
              tickerHistory.length,
              (index) =>
                  FlSpot(index.toDouble(), tickerHistory[index].currentPrice),
            ),
            isCurved: true,
            color: isPriceUp ? Colors.green : Colors.red,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color:
                  isPriceUp
                      ? Colors.green.withOpacity(0.2)
                      : Colors.red.withOpacity(0.2),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: Colors.blueGrey.withOpacity(0.8),
            getTooltipItems: (List<LineBarSpot> touchedSpots) {
              return touchedSpots.map((spot) {
                final ticker = tickerHistory[spot.x.toInt()];
                return LineTooltipItem(
                  '${ticker.currentPrice}',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                );
              }).toList();
            },
          ),
          handleBuiltInTouches: true,
        ),
      ),
    );
  }
}
