import 'dart:async';
import 'package:flutter/material.dart';
import '../api/okx_api.dart';
import '../models/order.dart';

class OrderList extends StatefulWidget {
  final String symbol;

  const OrderList({Key? key, required this.symbol}) : super(key: key);

  @override
  State<OrderList> createState() => _OrderListState();
}

class _OrderListState extends State<OrderList> {
  final OkxApi _api = OkxApi();
  List<Order> _orders = [];
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchOrders();

    // 每30秒刷新一次订单列表
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _fetchOrders();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchOrders() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final orders = await _api.getOrderHistory(widget.symbol);

      setState(() {
        _orders = orders;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '获取订单失败: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _fetchOrders, child: const Text('重试')),
          ],
        ),
      );
    }

    if (_orders.isEmpty) {
      return const Center(child: Text('暂无订单记录'));
    }

    return RefreshIndicator(
      onRefresh: _fetchOrders,
      child: ListView.builder(
        itemCount: _orders.length,
        itemBuilder: (context, index) {
          final order = _orders[index];
          return _buildOrderItem(order);
        },
      ),
    );
  }

  Widget _buildOrderItem(Order order) {
    final isBuy = order.side == 'buy';
    final isCompleted = order.isCompleted;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color:
                            isBuy
                                ? Colors.green.withOpacity(0.2)
                                : Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        order.sideDescription,
                        style: TextStyle(
                          color: isBuy ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        order.orderTypeDescription,
                        style: const TextStyle(color: Colors.blue),
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(order.state).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    order.stateDescription,
                    style: TextStyle(color: _getStatusColor(order.state)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '价格',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      order.price,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '数量',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      order.size,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '成交量',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      order.filledSize,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '成交均价',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      order.avgPrice == '0' ? '-' : order.avgPrice,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '订单ID: ${_shortenOrderId(order.orderId)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (!isCompleted)
                  TextButton(
                    onPressed: () => _cancelOrder(order),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(50, 30),
                    ),
                    child: const Text('取消'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 获取订单状态对应的颜色
  Color _getStatusColor(String state) {
    switch (state) {
      case 'live':
        return Colors.blue;
      case 'canceled':
        return Colors.grey;
      case 'partially_filled':
        return Colors.orange;
      case 'filled':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  // 缩短订单ID显示
  String _shortenOrderId(String orderId) {
    if (orderId.length > 12) {
      return '${orderId.substring(0, 6)}...${orderId.substring(orderId.length - 6)}';
    }
    return orderId;
  }

  // 取消订单
  Future<void> _cancelOrder(Order order) async {
    try {
      final success = await _api.cancelOrder(order.orderId, widget.symbol);

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('订单已取消'), backgroundColor: Colors.green),
        );

        // 刷新订单列表
        _fetchOrders();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('取消订单失败'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('取消订单失败: $e'), backgroundColor: Colors.red),
      );
    }
  }
}
