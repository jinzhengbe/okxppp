class SentimentData {
  final DateTime timestamp;
  final String source; // 'twitter', 'reddit', 'news', 等
  final String symbol;
  final double sentimentScore; // -1.0 到 1.0 的分数，负值表示负面情绪，正值表示正面情绪
  final int mentionCount; // 提及次数
  final Map<String, dynamic>? additionalData; // 可选的额外数据

  SentimentData({
    required this.timestamp,
    required this.source,
    required this.symbol,
    required this.sentimentScore,
    required this.mentionCount,
    this.additionalData,
  });

  // 从JSON创建
  factory SentimentData.fromJson(Map<String, dynamic> json) {
    return SentimentData(
      timestamp: DateTime.parse(json['timestamp']),
      source: json['source'],
      symbol: json['symbol'],
      sentimentScore: json['sentiment_score'].toDouble(),
      mentionCount: json['mention_count'],
      additionalData: json['additional_data'],
    );
  }

  // 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'source': source,
      'symbol': symbol,
      'sentiment_score': sentimentScore,
      'mention_count': mentionCount,
      'additional_data': additionalData,
    };
  }

  // 转换为InfluxDB点
  Map<String, dynamic> toInfluxPoint() {
    Map<String, dynamic> fields = {
      'sentiment_score': sentimentScore,
      'mention_count': mentionCount,
    };

    // 添加额外数据
    if (additionalData != null) {
      additionalData!.forEach((key, value) {
        if (value is num || value is bool || value is String) {
          fields[key] = value;
        }
      });
    }

    return {
      'measurement': 'sentiment_data',
      'tags': {
        'symbol': symbol,
        'source': source,
      },
      'fields': fields,
      'time': timestamp.toUtc().millisecondsSinceEpoch * 1000000, // 纳秒时间戳
    };
  }

  // 转换为PostgreSQL插入格式
  Map<String, dynamic> toPostgresInsert() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'source': source,
      'symbol': symbol,
      'sentiment_score': sentimentScore,
      'mention_count': mentionCount,
      'additional_data':
          additionalData != null ? additionalData.toString() : null,
      'created_at': DateTime.now().toIso8601String(),
    };
  }

  // 获取情绪类别
  String get sentimentCategory {
    if (sentimentScore > 0.3) return 'positive';
    if (sentimentScore < -0.3) return 'negative';
    return 'neutral';
  }
}
