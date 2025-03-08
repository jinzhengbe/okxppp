import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io';
import 'dart:async';
import 'screens/home_screen.dart';
import 'screens/network_settings_screen.dart';
import 'screens/crypto_list_screen.dart';
import 'screens/news_impact_screen.dart';
import 'screens/database_management_screen.dart';
import 'services/database_management_service.dart';

// 全局变量，用于指示HomeScreen是否应该打开代理设置
bool shouldOpenProxySettings = false;

void main() async {
  // 确保Flutter绑定初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 加载环境变量
  await dotenv.load(fileName: '.env');

  // 检查网络状态
  final networkStatus = await checkNetworkStatus();

  // 检查数据库状态
  final dbManagementService = DatabaseManagementService();
  final isDatabaseRunning = await dbManagementService.checkDatabaseStatus();

  // 如果数据库未运行，尝试启动
  if (!isDatabaseRunning) {
    debugPrint('数据库未运行，尝试启动...');
    await dbManagementService.startDatabases();
  }

  // 运行应用
  runApp(MyApp(networkStatus: networkStatus));
}

// 网络状态枚举
enum NetworkStatus {
  ok, // 网络正常
  needsProxy, // 需要代理
  systemPermission, // 系统权限问题
  connectionFailed // 连接失败
}

// 检查网络状态
Future<NetworkStatus> checkNetworkStatus() async {
  print('正在检查网络状态...');

  // 检查系统环境变量中是否已设置代理
  final hasProxy = Platform.environment['HTTP_PROXY']?.isNotEmpty == true ||
      Platform.environment['HTTPS_PROXY']?.isNotEmpty == true;

  if (hasProxy) {
    print(
        '检测到系统已配置代理: ${Platform.environment['HTTP_PROXY'] ?? Platform.environment['HTTPS_PROXY']}');
  }

  try {
    // 尝试连接OKX WebSocket端口
    print('尝试连接OKX WebSocket端口...');
    await Socket.connect('wsaws.okx.com', 8443, timeout: Duration(seconds: 3));
    print('WebSocket连接成功');
    return NetworkStatus.ok; // 连接成功，网络正常
  } catch (e) {
    print('WebSocket连接失败: $e');

    if (e.toString().contains('Operation not permitted')) {
      print('检测到系统权限问题');
      return NetworkStatus.systemPermission; // 系统权限问题
    }

    // 尝试连接REST API
    try {
      print('尝试连接OKX REST API...');
      final httpClient = HttpClient();
      httpClient.connectionTimeout = Duration(seconds: 3);
      final request = await httpClient.getUrl(Uri.parse('https://www.okx.com'));
      final response = await request.close();
      httpClient.close();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        print('REST API连接成功');
        return NetworkStatus.ok; // REST API连接成功
      } else {
        print('REST API连接失败，状态码: ${response.statusCode}');
      }
    } catch (e) {
      print('REST API连接失败: $e');

      if (e.toString().contains('Operation not permitted')) {
        return NetworkStatus.systemPermission; // 系统权限问题
      }
    }

    // 如果已经配置了代理但仍然失败
    if (hasProxy) {
      return NetworkStatus.connectionFailed; // 代理配置可能有问题
    }

    return NetworkStatus.needsProxy; // 建议使用代理
  }
}

class MyApp extends StatelessWidget {
  final NetworkStatus networkStatus;

  const MyApp({Key? key, required this.networkStatus}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OKX Trading App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
      ),
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (context) => networkStatus != NetworkStatus.ok
            ? NetworkWarningScreen(networkStatus: networkStatus)
            : const HomeScreen(),
        '/network_settings': (context) => const NetworkSettingsScreen(),
        '/crypto_list': (context) => const CryptoListScreen(),
        '/news_impact': (context) => const NewsImpactScreen(),
        '/database_management': (context) => const DatabaseManagementScreen(),
      },
    );
  }
}

// 网络警告屏幕
class NetworkWarningScreen extends StatelessWidget {
  final NetworkStatus networkStatus;

  const NetworkWarningScreen({Key? key, required this.networkStatus})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    String title;
    String message;
    IconData iconData;
    Color iconColor;

    switch (networkStatus) {
      case NetworkStatus.systemPermission:
        title = '系统网络权限问题';
        message = '应用被系统安全策略阻止连接到OKX服务器。这是macOS的安全特性，有以下解决方案：\n\n'
            '1. 配置代理服务器（推荐）\n'
            '2. 在系统偏好设置中允许网络连接\n'
            '3. 为应用程序签名\n\n'
            '您可以选择使用REST API模式继续使用应用，或者配置代理服务器来解决连接问题。';
        iconData = Icons.security;
        iconColor = Colors.orange;
        break;

      case NetworkStatus.needsProxy:
        title = '网络连接受限';
        message = '应用无法连接到OKX服务器。这可能是由于以下原因：\n\n'
            '1. 网络环境限制了加密货币交易所连接\n'
            '2. 防火墙或安全软件拦截了连接\n'
            '3. 您所在地区可能需要使用代理服务\n\n'
            '您可以选择使用REST API模式继续使用应用，或者配置代理服务器来解决连接问题。';
        iconData = Icons.wifi_off;
        iconColor = Colors.red;
        break;

      case NetworkStatus.connectionFailed:
        title = '连接失败';
        message = '尽管检测到系统已配置代理，但应用仍无法连接到OKX服务器。这可能是由于以下原因：\n\n'
            '1. 代理服务器配置不正确\n'
            '2. 代理服务器不可用\n'
            '3. OKX服务器暂时不可达\n\n'
            '您可以选择使用REST API模式继续使用应用，或者检查并重新配置代理设置。';
        iconData = Icons.cloud_off;
        iconColor = Colors.grey;
        break;

      default:
        title = '网络连接问题';
        message = '应用无法连接到OKX服务器。请检查您的网络连接。';
        iconData = Icons.warning_amber_rounded;
        iconColor = Colors.yellow;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              iconData,
              size: 80,
              color: iconColor,
            ),
            SizedBox(height: 24),
            Text(
              title,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                      builder: (_) => HomeScreen(useWebSocket: false)),
                );
              },
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: Text('使用REST API模式继续'),
            ),
            SizedBox(height: 16),
            if (networkStatus == NetworkStatus.systemPermission ||
                networkStatus == NetworkStatus.needsProxy)
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                        builder: (_) => HomeScreen(useWebSocket: false)),
                  );
                  // 注意：由于导航替换，我们无法直接访问新页面的状态
                  // 因此，我们使用一个全局标志来指示HomeScreen应该打开代理设置
                  shouldOpenProxySettings = true;
                },
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: Text('配置代理设置'),
              ),
            SizedBox(height: 16),
            TextButton(
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                      builder: (_) => HomeScreen(useWebSocket: true)),
                );
              },
              child: Text('仍然尝试使用WebSocket模式'),
            ),
            if (networkStatus == NetworkStatus.systemPermission)
              Padding(
                padding: const EdgeInsets.only(top: 24.0),
                child: Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'macOS系统权限解决方案:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      Text('在终端中执行以下命令:'),
                      SizedBox(height: 4),
                      SelectableText(
                        'sudo codesign --force --deep --sign - /Users/yijin/Desktop/bitcoin/okx_trading_app/build/macos/Build/Products/Debug/okx_trading_app.app',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
