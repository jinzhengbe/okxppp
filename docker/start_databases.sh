#!/bin/bash

# 切换到docker-compose.yml所在目录
cd "$(dirname "$0")"

# 启动数据库服务
docker-compose up -d

# 等待服务启动
echo "等待数据库服务启动..."
sleep 10

# 检查服务状态
docker-compose ps

echo "数据库服务已启动。"
echo "InfluxDB UI: http://localhost:8086"
echo "InfluxDB 用户名: admin"
echo "InfluxDB 密码: password"
echo "PostgreSQL 连接信息: postgresql://admin:password@localhost:5432/crypto_trading" 