import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class DatabaseManagementService {
  static final DatabaseManagementService _instance =
      DatabaseManagementService._internal();

  // 单例模式
  factory DatabaseManagementService() {
    return _instance;
  }

  DatabaseManagementService._internal();

  // 启动数据库服务
  Future<bool> startDatabases() async {
    try {
      // 获取脚本路径
      final scriptPath = await _getScriptPath('start_databases.sh');

      // 执行脚本
      final result = await Process.run('bash', [scriptPath]);

      if (result.exitCode != 0) {
        debugPrint('启动数据库失败: ${result.stderr}');
        return false;
      }

      debugPrint('数据库启动成功: ${result.stdout}');
      return true;
    } catch (e) {
      debugPrint('启动数据库时发生错误: $e');
      return false;
    }
  }

  // 停止数据库服务
  Future<bool> stopDatabases() async {
    try {
      // 获取脚本路径
      final scriptPath = await _getScriptPath('stop_databases.sh');

      // 执行脚本
      final result = await Process.run('bash', [scriptPath]);

      if (result.exitCode != 0) {
        debugPrint('停止数据库失败: ${result.stderr}');
        return false;
      }

      debugPrint('数据库停止成功: ${result.stdout}');
      return true;
    } catch (e) {
      debugPrint('停止数据库时发生错误: $e');
      return false;
    }
  }

  // 检查数据库状态
  Future<bool> checkDatabaseStatus() async {
    try {
      // 检查InfluxDB
      final influxResult =
          await Process.run('curl', ['-s', 'http://localhost:8086/ping']);

      // 检查PostgreSQL
      final postgresResult =
          await Process.run('pg_isready', ['-h', 'localhost', '-p', '5432']);

      // 如果两个数据库都正常运行，返回true
      return influxResult.exitCode == 0 && postgresResult.exitCode == 0;
    } catch (e) {
      debugPrint('检查数据库状态时发生错误: $e');
      return false;
    }
  }

  // 备份数据库
  Future<bool> backupDatabases(String backupPath) async {
    try {
      // 创建备份目录
      final directory = Directory(backupPath);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      // 备份PostgreSQL
      final postgresBackupPath =
          '$backupPath/postgres_backup_${DateTime.now().millisecondsSinceEpoch}.sql';
      final postgresResult = await Process.run('pg_dump', [
        '-h',
        'localhost',
        '-p',
        '5432',
        '-U',
        dotenv.env['POSTGRES_USER'] ?? 'admin',
        '-f',
        postgresBackupPath,
        dotenv.env['POSTGRES_DB'] ?? 'crypto_trading'
      ], environment: {
        'PGPASSWORD': dotenv.env['POSTGRES_PASSWORD'] ?? 'password'
      });

      // 备份InfluxDB (使用influx备份命令)
      final influxBackupPath =
          '$backupPath/influx_backup_${DateTime.now().millisecondsSinceEpoch}';
      final influxResult = await Process.run('influx', [
        'backup',
        '-t',
        dotenv.env['INFLUXDB_TOKEN'] ?? 'my-super-secret-auth-token',
        '-o',
        dotenv.env['INFLUXDB_ORG'] ?? 'crypto',
        '-b',
        dotenv.env['INFLUXDB_BUCKET'] ?? 'crypto_data',
        influxBackupPath
      ]);

      return postgresResult.exitCode == 0 && influxResult.exitCode == 0;
    } catch (e) {
      debugPrint('备份数据库时发生错误: $e');
      return false;
    }
  }

  // 导出数据
  Future<bool> exportData(
      String symbol, DateTime start, DateTime end, String exportPath) async {
    try {
      // 创建导出目录
      final directory = Directory(exportPath);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      // 从PostgreSQL导出交易数据
      final tradeExportPath =
          '$exportPath/${symbol}_trades_${start.millisecondsSinceEpoch}_${end.millisecondsSinceEpoch}.csv';
      final tradeQuery = '''
        COPY (
          SELECT * FROM trades 
          WHERE symbol = '$symbol' 
          AND timestamp BETWEEN '${start.toIso8601String()}' AND '${end.toIso8601String()}'
        ) TO '$tradeExportPath' WITH CSV HEADER;
      ''';

      final tradeResult = await Process.run('psql', [
        '-h',
        'localhost',
        '-p',
        '5432',
        '-U',
        dotenv.env['POSTGRES_USER'] ?? 'admin',
        '-d',
        dotenv.env['POSTGRES_DB'] ?? 'crypto_trading',
        '-c',
        tradeQuery
      ], environment: {
        'PGPASSWORD': dotenv.env['POSTGRES_PASSWORD'] ?? 'password'
      });

      // 从InfluxDB导出价格数据
      final priceExportPath =
          '$exportPath/${symbol}_prices_${start.millisecondsSinceEpoch}_${end.millisecondsSinceEpoch}.csv';
      final priceQuery = '''
        from(bucket: "${dotenv.env['INFLUXDB_BUCKET'] ?? 'crypto_data'}")
          |> range(start: ${start.toUtc().toIso8601String()}, stop: ${end.toUtc().toIso8601String()})
          |> filter(fn: (r) => r._measurement == "price_data")
          |> filter(fn: (r) => r.symbol == "$symbol")
          |> pivot(rowKey:["_time"], columnKey: ["_field"], valueColumn: "_value")
      ''';

      final priceResult = await Process.run('influx', [
        'query',
        '-t',
        dotenv.env['INFLUXDB_TOKEN'] ?? 'my-super-secret-auth-token',
        '-o',
        dotenv.env['INFLUXDB_ORG'] ?? 'crypto',
        '--raw',
        priceQuery,
        '-f',
        'csv',
        '>',
        priceExportPath
      ]);

      return tradeResult.exitCode == 0 && priceResult.exitCode == 0;
    } catch (e) {
      debugPrint('导出数据时发生错误: $e');
      return false;
    }
  }

  // 获取脚本路径
  Future<String> _getScriptPath(String scriptName) async {
    // 在macOS和Linux上，脚本位于docker目录下
    return '${Directory.current.path}/docker/$scriptName';
  }
}
