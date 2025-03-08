class NewsSymbolRelation {
  final String symbol;
  final double? priceAtPublish;
  final double? priceChange24h;

  NewsSymbolRelation({
    required this.symbol,
    this.priceAtPublish,
    this.priceChange24h,
  });

  factory NewsSymbolRelation.fromJson(Map<String, dynamic> json) {
    return NewsSymbolRelation(
      symbol: json['symbol'] as String,
      priceAtPublish: json['price_at_publish'] != null
          ? (json['price_at_publish'] as num).toDouble()
          : null,
      priceChange24h: json['price_change_24h'] != null
          ? (json['price_change_24h'] as num).toDouble()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'symbol': symbol,
      'price_at_publish': priceAtPublish,
      'price_change_24h': priceChange24h,
    };
  }
}

class News {
  final String id;
  final String title;
  final String content;
  final String source;
  final String publishedAt;
  final String? url;
  final List<NewsSymbolRelation> relatedSymbols;

  News({
    required this.id,
    required this.title,
    required this.content,
    required this.source,
    required this.publishedAt,
    this.url,
    required this.relatedSymbols,
  });

  factory News.fromJson(Map<String, dynamic> json) {
    return News(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      source: json['source'] as String,
      publishedAt: json['published_at'] as String,
      url: json['url'] as String?,
      relatedSymbols: (json['related_symbols'] as List<dynamic>)
          .map((e) => NewsSymbolRelation.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'source': source,
      'published_at': publishedAt,
      'url': url,
      'related_symbols': relatedSymbols.map((e) => e.toJson()).toList(),
    };
  }

  // 创建一个带有关联虚拟币的新闻
  News copyWithRelatedSymbol(String symbol, String? price) {
    final existingRelations = List<NewsSymbolRelation>.from(relatedSymbols);

    // 检查是否已经存在该关联
    final existingIndex =
        existingRelations.indexWhere((r) => r.symbol == symbol);

    if (existingIndex >= 0) {
      // 更新现有关联
      existingRelations[existingIndex] = NewsSymbolRelation(
        symbol: symbol,
        priceAtPublish: price != null ? double.parse(price) : null,
        priceChange24h: null,
      );
    } else {
      // 添加新关联
      existingRelations.add(NewsSymbolRelation(
        symbol: symbol,
        priceAtPublish: price != null ? double.parse(price) : null,
        priceChange24h: null,
      ));
    }

    return News(
      id: id,
      title: title,
      content: content,
      source: source,
      publishedAt: publishedAt,
      url: url,
      relatedSymbols: existingRelations,
    );
  }
}
