# 青龙面板 Docker 镜像

> 基于 `whyour/qinglong:latest` 构建，集成自动备份/还原与监控功能

**镜像地址**: `kwxos/qldocker`

## ✨ 功能特性

- 🔄 **自动备份**: 支持定时备份青龙数据到 GitHub 私有仓库
- 📦 **智能还原**: 容器启动时自动从 GitHub 还原最新备份数据
- 🗂️ **版本管理**: 自动保留最新 3 个备份版本，节省存储空间
- 📊 **监控支持**: 可选集成服务器监控功能
- 🚀 **一键部署**: 简单配置环境变量即可启动

## 🚀 快速开始

### Docker Run 方式

```bash
docker run -d \
  --name qinglong \
  -p 5700:5700 \
  -v $PWD/ql/data:/ql/data \
  -v $PWD/ql/log:/ql/log \
  -e BACKUP_REPO_URL="https://github.com/username/ql-backup.git" \
  -e GITHUB_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxx" \
  -e GIT_USER_NAME="Your Name" \
  -e GIT_USER_EMAIL="your.email@example.com" \
  kwxos/qldocker
```

### Docker Compose 方式

```yaml
version: '3'
services:
  qinglong:
    image: kwxos/qldocker
    container_name: qinglong
    ports:
      - "5700:5700"
    volumes:
      - ./ql/data:/ql/data
      - ./ql/log:/ql/log
    environment:
      - BACKUP_REPO_URL=https://github.com/username/ql-backup.git
      - GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
      - GIT_USER_NAME=Your Name
      - GIT_USER_EMAIL=your.email@example.com
    restart: unless-stopped
```

## ⚙️ 环境变量配置

### GitHub 备份配置（必需）

| 变量名 | 说明 | 示例 |
|--------|------|------|
| `BACKUP_REPO_URL` | GitHub 备份仓库地址 | `https://github.com/username/ql-backup.git` |
| `GITHUB_TOKEN` | GitHub Personal Access Token | `ghp_xxxxxxxxxxxxxxxxxxxx` |
| `GIT_USER_NAME` | Git 提交用户名 | `Your Name` |
| `GIT_USER_EMAIL` | Git 提交邮箱 | `your.email@example.com` |
| `BACKUP_BRANCH` | 备份分支名（可选，默认 main） | `main` |

### 监控配置（可选）

| 变量名 | 说明 | 示例 |
|--------|------|------|
| `Server` | 监控服务器地址 | `your.server.com` |
| `Spot` | 监控服务端口 | `443` |
| `secret` | 监控密钥 | `your_secret` |
| `idu` | 设备 UUID | `your_uuid` |

## 📋 设置自动备份任务

在青龙面板中添加定时任务，执行以下命令：

```bash
/bin/bash /ql/custom/backup-to-github.sh
```

**建议定时规则**: `0 3 * * *` (每天凌晨 2 点执行)

<img width="396" height="319" alt="青龙面板定时任务配置" src="https://github.com/user-attachments/assets/46ea17c7-4e92-4d37-a860-1cc50e875ce2" />

## 📖 使用说明

### GitHub Token 权限要求

创建 Personal Access Token 时需要授予以下权限：
- ✅ `repo` (完整的仓库访问权限)
- ✅ `workflow` (如果仓库使用了 GitHub Actions)

### 备份机制

- 每次备份会创建 `data-YYYY-MM-DD-HH-MM-SS.tar.gz` 格式的压缩包
- 自动排除临时文件、日志文件、node_modules 等无需备份的内容
- 保留最新 3 个备份版本，自动清理旧版本
- 使用 `--force-with-lease` 安全推送，避免覆盖他人提交

### 还原机制

- 容器启动时自动检测是否配置备份
- 如已配置，则从 GitHub 下载并还原最新备份
- 还原失败不影响容器正常启动

## 📝 注意事项

1. 首次使用建议先手动执行一次备份脚本，确保配置正确
2. 备份仓库建议使用私有仓库，避免敏感信息泄露
3. GitHub Token 务必妥善保管，不要泄露给他人
4. 如果不需要自动还原功能，可以不配置环境变量

## 📄 License

MIT
