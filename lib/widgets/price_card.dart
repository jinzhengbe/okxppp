import 'package:flutter/material.dart';
import '../models/ticker.dart';

class PriceCard extends StatelessWidget {
  final Ticker ticker;

  const PriceCard({Key? key, required this.ticker}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16.0),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ticker.symbol,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '24h量: ${_formatVolume(ticker.volume)}',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      ticker.currentPrice > 0
                          ? '${ticker.currentPrice}'
                          : '加载中...',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: ticker.isPriceUp ? Colors.green : Colors.red,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          ticker.isPriceUp
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          color: ticker.isPriceUp ? Colors.green : Colors.red,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${ticker.changePercentage.toStringAsFixed(2)}%',
                          style: TextStyle(
                            fontSize: 14,
                            color: ticker.isPriceUp ? Colors.green : Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildInfoItem('最高', ticker.highPrice.toString(), Colors.green),
                _buildInfoItem('最低', ticker.lowPrice.toString(), Colors.red),
                _buildInfoItem('买一', ticker.bidPx, Colors.blue),
                _buildInfoItem('卖一', ticker.askPx, Colors.orange),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  String _formatVolume(double volume) {
    if (volume > 1000000) {
      return '${(volume / 1000000).toStringAsFixed(2)}M';
    } else if (volume > 1000) {
      return '${(volume / 1000).toStringAsFixed(2)}K';
    } else {
      return volume.toStringAsFixed(2);
    }
  }
}
