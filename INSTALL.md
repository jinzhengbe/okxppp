# OKX Trading App 安装指南

本文档提供了OKX Trading App的详细安装、配置和使用说明。

## 目录

1. [系统要求](#系统要求)
2. [安装步骤](#安装步骤)
3. [配置说明](#配置说明)
4. [数据库设置](#数据库设置)
5. [启动应用](#启动应用)
6. [功能使用指南](#功能使用指南)
7. [更新代码](#更新代码)
8. [常见问题](#常见问题)

## 系统要求

- **操作系统**: macOS, Windows 或 Linux
- **Flutter SDK**: 3.0.0 或更高版本
- **Dart SDK**: 2.17.0 或更高版本
- **Docker**: 20.10.0 或更高版本 (用于运行数据库)
- **Git**: 2.30.0 或更高版本

## 安装步骤

### 1. 克隆仓库

```bash
git clone https://github.com/jinzhengbe/okxppp.git
cd okxppp
```

### 2. 安装Flutter依赖

```bash
flutter pub get
```

### 3. 配置环境变量

复制示例环境变量文件并根据需要修改:

```bash
cp .env.example .env
```

使用文本编辑器打开`.env`文件，填写必要的配置信息:

```
# OKX API配置
API_KEY=your_api_key_here
SECRET_KEY=your_secret_key_here
PASSPHRASE=your_passphrase_here

# 其他配置...
```

## 配置说明

### OKX API配置

要使用OKX API功能，你需要在OKX官网创建API密钥:

1. 登录OKX账户
2. 进入"API管理"页面
3. 创建新的API密钥
4. 将API密钥、Secret Key和Passphrase填入`.env`文件

### 交易配置

在`.env`文件中，你可以配置以下交易参数:

- `TRADE_SYMBOL`: 交易对，例如"BTC-USDT"
- `TRADE_AMOUNT`: 每次交易的数量
- `BUY_THRESHOLD`: 买入阈值
- `SELL_THRESHOLD`: 卖出阈值

### 风险控制

- `MAX_TRADES_PER_DAY`: 每日最大交易次数
- `STOP_LOSS_PERCENTAGE`: 止损百分比

## 数据库设置

### 1. 安装Docker

如果尚未安装Docker，请按照[Docker官方文档](https://docs.docker.com/get-docker/)安装。

### 2. 启动数据库服务

```bash
cd docker
chmod +x start_databases.sh
./start_databases.sh
```

这将启动两个Docker容器:
- **InfluxDB**: 用于存储时间序列数据(价格、订单簿数据)
- **PostgreSQL**: 用于存储结构化数据(交易记录、情绪分析)

### 3. 验证数据库状态

```bash
chmod +x check_database_health.sh
./check_database_health.sh
```

如果一切正常，你将看到"所有数据库服务运行正常"的消息。

### 4. 数据库访问信息

- **InfluxDB UI**: http://localhost:8086
  - 用户名: admin
  - 密码: password
  - 组织: crypto
  - 存储桶: crypto_data

- **PostgreSQL**:
  - 主机: localhost
  - 端口: 5432
  - 数据库: crypto_trading
  - 用户名: admin
  - 密码: password

## 启动应用

### 在macOS上运行

```bash
flutter run -d macos
```

### 在Windows上运行

```bash
flutter run -d windows
```

### 在Linux上运行

```bash
flutter run -d linux
```

### 在移动设备上运行

连接设备后:

```bash
flutter run
```

## 功能使用指南

### 主界面

主界面显示当前选定交易对的实时价格和图表。你可以:
- 切换交易对
- 查看价格图表
- 开启/关闭自动交易

### 数据库管理界面

数据库管理界面可以通过点击主界面上的"数据库管理"按钮访问。在这里你可以:

1. **数据库控制**:
   - 启动/停止数据库服务
   - 查看数据库连接状态

2. **数据收集**:
   - 启动/停止数据收集服务
   - 查看数据收集状态

3. **数据查询**:
   - 查询价格数据
   - 查询交易数据
   - 查询情绪数据

4. **数据管理**:
   - 备份数据库
   - 导出数据为CSV格式

### 新闻影响分析

新闻影响分析界面可以查看加密货币相关新闻及其对价格的潜在影响。

## 更新代码

当你需要更新代码或将本地更改推送到GitHub时，可以使用提供的更新脚本:

```bash
chmod +x update_github.sh
./update_github.sh
```

脚本会引导你完成以下步骤:
1. 添加所有更改的文件
2. 输入提交信息
3. 选择分支名称
4. 推送到GitHub

## 常见问题

### 数据库连接失败

如果应用无法连接到数据库，请检查:

1. Docker容器是否正在运行:
   ```bash
   docker ps
   ```

2. 数据库端口是否被占用:
   ```bash
   lsof -i :8086  # 检查InfluxDB端口
   lsof -i :5432  # 检查PostgreSQL端口
   ```

3. 环境变量配置是否正确:
   检查`.env`文件中的数据库连接信息

### OKX API连接问题

如果应用无法连接到OKX API，可能是由于:

1. 网络限制: 某些地区可能需要使用代理
2. API密钥无效: 检查API密钥、Secret Key和Passphrase是否正确
3. 系统权限问题: 在macOS上，可能需要在系统偏好设置中允许网络连接

解决方案:
- 配置代理服务器
- 重新生成API密钥
- 使用REST API模式而非WebSocket模式

### 自动交易不执行

如果自动交易功能不工作，请检查:

1. 是否已启用自动交易功能
2. API密钥是否有交易权限
3. 交易参数是否合理
4. 账户余额是否充足

## 附录

### 数据库架构

#### InfluxDB

- **price_data**: 价格数据
- **orderbook_data**: 订单簿数据

#### PostgreSQL

- **trades**: 交易数据
- **sentiment**: 情绪数据

### 交易策略

默认交易策略:
- 当币种涨幅达到3%时买入
- 当涨幅超过5%时卖出50%持仓
- 当涨幅超过100%时全部卖出 