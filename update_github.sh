#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}===== OKX Trading App GitHub 更新脚本 =====${NC}"
echo

# 检查是否在正确的目录
if [ ! -d "lib" ] || [ ! -f "pubspec.yaml" ]; then
  echo -e "${YELLOW}错误: 请在okx_trading_app目录下运行此脚本${NC}"
  exit 1
fi

# 检查git是否已初始化
if [ ! -d ".git" ]; then
  echo -e "${YELLOW}Git仓库未初始化，正在初始化...${NC}"
  git init
  echo
fi

# 检查远程仓库是否已配置
REMOTE_URL=$(git config --get remote.origin.url)
if [ -z "$REMOTE_URL" ]; then
  echo -e "${YELLOW}远程仓库未配置${NC}"
  echo -e "请输入GitHub仓库URL (例如: https://github.com/username/okx_trading_app.git):"
  read REPO_URL
  git remote add origin $REPO_URL
  echo -e "${GREEN}远程仓库已配置: $REPO_URL${NC}"
  echo
else
  echo -e "${GREEN}远程仓库已配置: $REMOTE_URL${NC}"
  echo
fi

# 添加所有文件
echo -e "${YELLOW}添加所有文件到Git...${NC}"
git add .
echo

# 提交更改
echo -e "${YELLOW}提交更改...${NC}"
echo -e "请输入提交信息 (例如: '添加数据库管理功能'):"
read COMMIT_MESSAGE
git commit -m "$COMMIT_MESSAGE"
echo

# 推送到GitHub
echo -e "${YELLOW}推送到GitHub...${NC}"
echo -e "请输入分支名称 (默认: main):"
read BRANCH_NAME
if [ -z "$BRANCH_NAME" ]; then
  BRANCH_NAME="main"
fi

git push -u origin $BRANCH_NAME
PUSH_RESULT=$?

if [ $PUSH_RESULT -eq 0 ]; then
  echo -e "${GREEN}成功推送到GitHub!${NC}"
  echo -e "仓库URL: $REMOTE_URL"
else
  echo -e "${YELLOW}推送失败，可能需要先拉取远程更改${NC}"
  echo -e "尝试执行: git pull origin $BRANCH_NAME --rebase"
  echo -e "然后再次运行此脚本"
fi

echo
echo -e "${GREEN}===== 脚本执行完成 =====${NC}" 