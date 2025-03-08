#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}===== OKX Trading App 安装脚本 =====${NC}"
echo

# 检查是否在正确的目录
if [ ! -d "lib" ] || [ ! -f "pubspec.yaml" ]; then
  echo -e "${RED}错误: 请在okx_trading_app目录下运行此脚本${NC}"
  exit 1
fi

# 检查Flutter是否已安装
if ! command -v flutter &> /dev/null; then
  echo -e "${RED}错误: Flutter未安装，请先安装Flutter SDK${NC}"
  echo -e "访问 https://flutter.dev/docs/get-started/install 获取安装指南"
  exit 1
fi

# 检查Docker是否已安装
if ! command -v docker &> /dev/null; then
  echo -e "${YELLOW}警告: Docker未安装，数据库功能将无法使用${NC}"
  echo -e "访问 https://docs.docker.com/get-docker/ 获取安装指南"
  
  echo -e "${YELLOW}是否继续安装? (y/n)${NC}"
  read CONTINUE
  if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then
    echo -e "${YELLOW}安装已取消${NC}"
    exit 0
  fi
fi

# 安装Flutter依赖
echo -e "${GREEN}安装Flutter依赖...${NC}"
flutter pub get

# 检查.env文件
if [ ! -f ".env" ]; then
  echo -e "${YELLOW}未找到.env文件，正在从.env.example创建...${NC}"
  cp .env.example .env
  echo -e "${GREEN}.env文件已创建，请根据需要修改配置${NC}"
fi

# 设置脚本执行权限
echo -e "${GREEN}设置脚本执行权限...${NC}"
chmod +x docker/start_databases.sh
chmod +x docker/stop_databases.sh
chmod +x docker/check_database_health.sh
chmod +x update_github.sh

# 询问是否启动数据库
echo -e "${YELLOW}是否现在启动数据库? (y/n)${NC}"
read START_DB
if [ "$START_DB" = "y" ] || [ "$START_DB" = "Y" ]; then
  echo -e "${GREEN}启动数据库...${NC}"
  cd docker && ./start_databases.sh
  cd ..
  
  # 等待数据库启动
  echo -e "${YELLOW}等待数据库启动...${NC}"
  sleep 10
  
  # 检查数据库状态
  echo -e "${GREEN}检查数据库状态...${NC}"
  cd docker && ./check_database_health.sh
  cd ..
fi

# 询问是否启动应用
echo -e "${YELLOW}是否现在启动应用? (y/n)${NC}"
read START_APP
if [ "$START_APP" = "y" ] || [ "$START_APP" = "Y" ]; then
  echo -e "${GREEN}启动应用...${NC}"
  flutter run -d macos
fi

echo
echo -e "${GREEN}===== 安装完成 =====${NC}"
echo -e "请参考 ${YELLOW}INSTALL.md${NC} 获取更多信息" 