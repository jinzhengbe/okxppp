#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}===== OKX Trading App GitHub 更新脚本 =====${NC}"
echo

# 检查是否在正确的目录
if [ ! -d "lib" ] || [ ! -f "pubspec.yaml" ]; then
  echo -e "${RED}错误: 请在okx_trading_app目录下运行此脚本${NC}"
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
  
  # 检查输入是否为空
  if [ -z "$REPO_URL" ]; then
    echo -e "${RED}错误: 仓库URL不能为空${NC}"
    exit 1
  fi
  
  git remote add origin $REPO_URL
  echo -e "${GREEN}远程仓库已配置: $REPO_URL${NC}"
  echo
else
  echo -e "${GREEN}远程仓库已配置: $REMOTE_URL${NC}"
  echo
fi

# 检查是否有更改需要提交
if git diff-index --quiet HEAD --; then
  echo -e "${YELLOW}没有检测到文件更改，是否继续? (y/n)${NC}"
  read CONTINUE
  if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then
    echo -e "${YELLOW}操作已取消${NC}"
    exit 0
  fi
fi

# 添加所有文件
echo -e "${YELLOW}添加所有文件到Git...${NC}"
git add .
echo

# 提交更改
echo -e "${YELLOW}提交更改...${NC}"
COMMIT_MESSAGE=""
while [ -z "$COMMIT_MESSAGE" ]; do
  echo -e "请输入提交信息 (例如: '添加数据库管理功能'):"
  read COMMIT_MESSAGE
  
  if [ -z "$COMMIT_MESSAGE" ]; then
    echo -e "${RED}错误: 提交信息不能为空，请重新输入${NC}"
  fi
done

git commit -m "$COMMIT_MESSAGE"
COMMIT_RESULT=$?

if [ $COMMIT_RESULT -ne 0 ]; then
  echo -e "${RED}提交失败，可能没有更改需要提交${NC}"
  exit 1
fi

echo

# 推送到GitHub
echo -e "${YELLOW}推送到GitHub...${NC}"
echo -e "请输入分支名称 (默认: main):"
read BRANCH_NAME
if [ -z "$BRANCH_NAME" ]; then
  BRANCH_NAME="main"
fi

# 检查分支是否存在
if ! git show-ref --verify --quiet refs/heads/$BRANCH_NAME; then
  echo -e "${YELLOW}分支 $BRANCH_NAME 不存在，是否创建? (y/n)${NC}"
  read CREATE_BRANCH
  if [ "$CREATE_BRANCH" = "y" ] || [ "$CREATE_BRANCH" = "Y" ]; then
    git checkout -b $BRANCH_NAME
  else
    echo -e "${YELLOW}操作已取消${NC}"
    exit 0
  fi
fi

# 尝试推送
git push -u origin $BRANCH_NAME
PUSH_RESULT=$?

if [ $PUSH_RESULT -eq 0 ]; then
  echo -e "${GREEN}成功推送到GitHub!${NC}"
  echo -e "仓库URL: $REMOTE_URL"
  echo -e "分支: $BRANCH_NAME"
else
  echo -e "${YELLOW}推送失败，尝试拉取远程更改...${NC}"
  git pull origin $BRANCH_NAME --rebase
  PULL_RESULT=$?
  
  if [ $PULL_RESULT -eq 0 ]; then
    echo -e "${YELLOW}再次尝试推送...${NC}"
    git push -u origin $BRANCH_NAME
    
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}成功推送到GitHub!${NC}"
      echo -e "仓库URL: $REMOTE_URL"
      echo -e "分支: $BRANCH_NAME"
    else
      echo -e "${RED}推送失败，请手动解决冲突${NC}"
      echo -e "可能需要执行以下命令:"
      echo -e "git pull origin $BRANCH_NAME --rebase"
      echo -e "git push -u origin $BRANCH_NAME"
    fi
  else
    echo -e "${RED}拉取失败，请手动解决冲突${NC}"
  fi
fi

echo
echo -e "${GREEN}===== 脚本执行完成 =====${NC}" 