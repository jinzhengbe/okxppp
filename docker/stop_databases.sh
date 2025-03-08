#!/bin/bash

# 切换到docker-compose.yml所在目录
cd "$(dirname "$0")"

# 停止数据库服务
docker-compose down

echo "数据库服务已停止。" 