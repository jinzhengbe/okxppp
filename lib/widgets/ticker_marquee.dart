import 'dart:async';
import 'package:flutter/material.dart';
import '../models/ticker.dart';

class TickerMarquee extends StatefulWidget {
  final List<Ticker> tickers;
  final double height;
  final double speed;

  const TickerMarquee({
    Key? key,
    required this.tickers,
    this.height = 40,
    this.speed = 50.0, // 像素/秒
  }) : super(key: key);

  @override
  State<TickerMarquee> createState() => _TickerMarqueeState();
}

class _TickerMarqueeState extends State<TickerMarquee> {
  late ScrollController _scrollController;
  Timer? _timer;
  double _offset = 0.0;
  double _maxOffset = 0.0;
  final GlobalKey _listKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();

    // 在下一帧渲染完成后开始滚动
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScrolling();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TickerMarquee oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tickers != oldWidget.tickers) {
      // 如果数据更新了，重新计算并开始滚动
      _timer?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startScrolling();
      });
    }
  }

  void _startScrolling() {
    // 获取列表的总宽度
    final RenderBox? renderBox =
        _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    _maxOffset = renderBox.size.width;

    // 如果列表宽度小于屏幕宽度，不需要滚动
    if (_maxOffset <= MediaQuery.of(context).size.width) return;

    // 设置滚动定时器
    const fps = 60.0; // 每秒帧数
    final pixelsPerFrame = widget.speed / fps; // 每帧滚动的像素数

    _timer =
        Timer.periodic(Duration(milliseconds: (1000 / fps).round()), (timer) {
      _offset += pixelsPerFrame;

      // 当滚动到最右侧时，重置到开始位置
      if (_offset >= _maxOffset) {
        _offset = 0.0;
      }

      _scrollController.jumpTo(_offset);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: NeverScrollableScrollPhysics(), // 禁用用户滚动
        child: Row(
          key: _listKey,
          children: widget.tickers.map((ticker) {
            final isPositive = ticker.changePercentage >= 0;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                children: [
                  Text(
                    ticker.symbol,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(width: 4),
                  Text(
                    ticker.currentPrice.toStringAsFixed(
                      ticker.currentPrice < 1 ? 6 : 2,
                    ),
                    style: TextStyle(fontSize: 14),
                  ),
                  SizedBox(width: 4),
                  Text(
                    '${isPositive ? '+' : ''}${ticker.changePercentage.toStringAsFixed(2)}%',
                    style: TextStyle(
                      color: isPositive ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(width: 16),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
