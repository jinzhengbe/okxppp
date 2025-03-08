# OKX Trading App

一个功能强大的加密货币交易和数据分析应用，基于Flutter开发，支持OKX交易所API。

## 主要功能

- **实时价格监控**：通过WebSocket或REST API实时获取加密货币价格
- **自动交易**：基于预设条件的自动买入和卖出
- **技术分析**：价格图表和技术指标
- **新闻影响分析**：分析新闻对加密货币价格的影响
- **数据收集与存储**：收集价格、交易、订单簿和情绪数据
- **数据库管理**：管理InfluxDB和PostgreSQL数据库

## 快速安装

我们提供了一个简单的安装脚本，帮助你快速设置环境：

```bash
# 克隆仓库
git clone https://github.com/jinzhengbe/okxppp.git
cd okxppp

# 运行安装脚本
chmod +x setup.sh
./setup.sh
```

详细的安装和配置说明请参考 [安装指南](INSTALL.md)。

## 最新功能：数据库管理

我们新增了数据库管理功能，使用InfluxDB和PostgreSQL存储和管理加密货币数据：

- **InfluxDB**：存储时间序列数据，如价格和订单簿数据
- **PostgreSQL**：存储结构化数据，如交易记录和情绪分析

### 数据库管理界面

新的数据库管理界面提供以下功能：

- 启动和停止数据库服务
- 查看数据库连接状态
- 启动和停止数据收集
- 查询和显示价格数据
- 查询和显示交易数据
- 查询和显示情绪数据
- 备份数据库
- 导出数据为CSV格式

### 数据模型

应用使用以下数据模型：

- **PriceData**：价格数据，包括开盘价、收盘价、最高价、最低价和成交量
- **TradeData**：交易数据，包括交易ID、价格、数量、方向和手续费
- **OrderBookData**：订单簿数据，包括买单和卖单
- **SentimentData**：情绪数据，包括情绪分数和提及次数

## 安装与配置

### 前提条件

- Flutter SDK
- Docker (用于运行数据库)
- OKX API密钥 (可选)

### 安装步骤

1. 克隆仓库：
   ```
   git clone https://github.com/jinzhengbe/okxppp.git
   cd okxppp
   ```

2. 安装依赖：
   ```
   flutter pub get
   ```

3. 配置环境变量：
   复制`.env.example`为`.env`并填写必要的配置信息。

4. 启动数据库：
   ```
   cd docker
   ./start_databases.sh
   ```

5. 运行应用：
   ```
   flutter run -d macos
   ```

## 数据库设置

### Docker容器

应用使用Docker容器运行InfluxDB和PostgreSQL：

```yaml
# docker-compose.yml
version: '3'
services:
  influxdb:
    image: influxdb:latest
    ports:
      - "8086:8086"
    volumes:
      - influxdb-data:/var/lib/influxdb2
    environment:
      - DOCKER_INFLUXDB_INIT_MODE=setup
      - DOCKER_INFLUXDB_INIT_USERNAME=admin
      - DOCKER_INFLUXDB_INIT_PASSWORD=password
      - DOCKER_INFLUXDB_INIT_ORG=crypto
      - DOCKER_INFLUXDB_INIT_BUCKET=crypto_data
      - DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=my-super-secret-auth-token

  postgres:
    image: postgres:latest
    ports:
      - "5432:5432"
    volumes:
      - postgres-data:/var/lib/postgresql/data
    environment:
      - POSTGRES_USER=admin
      - POSTGRES_PASSWORD=password
      - POSTGRES_DB=crypto_trading
```

### 数据库管理脚本

- `start_databases.sh`：启动数据库服务
- `stop_databases.sh`：停止数据库服务
- `check_database_health.sh`：检查数据库健康状态

## 更新到GitHub

使用提供的脚本更新代码到GitHub：

```
./update_github.sh
```

## 技术栈

- **前端**：Flutter
- **API**：OKX REST API和WebSocket API
- **数据库**：InfluxDB和PostgreSQL
- **容器化**：Docker

## 交易策略

默认交易策略：
- 当币种涨幅达到3%时买入
- 当涨幅超过5%时卖出50%持仓
- 当涨幅超过100%时全部卖出

## 贡献

欢迎提交Pull Request或Issue来改进应用。

## 许可证

[MIT License](LICENSE)


获取币种的api

分析每个 币种的涨幅，

确认能涨3% 就买，涨幅超过5% 卖出50%  ，剩余涨幅超过100% 全部卖掉
zhi

