#!/bin/bash

BACKUP_DIR="/ql/data"
BACKUP_REPO_URL="${BACKUP_REPO_URL:-}"
BACKUP_BRANCH="${BACKUP_BRANCH:-main}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
WORK_DIR="/tmp/ql-backup"
LOG_FILE="/ql/log/backup.log"

log_backup() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "$LOG_FILE"
}

check_env() {
    if [ -z "$BACKUP_REPO_URL" ]; then
        log_backup "ERROR" "未设置 BACKUP_REPO_URL 环境变量"
        exit 1
    fi
    
    if [ -z "$GIT_USER_NAME" ] || [ -z "$GIT_USER_EMAIL" ]; then
        log_backup "ERROR" "未设置 GIT_USER_NAME 或 GIT_USER_EMAIL 环境变量"
        exit 1
    fi
    
    if [ -z "$GITHUB_TOKEN" ]; then
        log_backup "ERROR" "未设置 GITHUB_TOKEN 环境变量，私密仓库需要此令牌"
        exit 1
    fi
}

init_git() {
    git config --global user.name "$GIT_USER_NAME"
    git config --global user.email "$GIT_USER_EMAIL"
    git config --global init.defaultBranch "$BACKUP_BRANCH"
    
    if [[ $BACKUP_REPO_URL == https://github.com/* ]]; then
        BACKUP_REPO_URL_WITH_TOKEN=$(echo "$BACKUP_REPO_URL" | sed "s|https://github.com/|https://${GITHUB_TOKEN}@github.com/|")
        log_backup "INFO" "🔐  已配置 GitHub Token 身份验证"
    else
        log_backup "ERROR" "仅支持 GitHub HTTPS 仓库格式"
        exit 1
    fi
}

update_readme() {
    local backup_file="$1"
    local backup_date=$(date '+%Y-%m-%d %H:%M:%S')
    echo "${backup_file}" > README.md
}

perform_backup() {
    local date_str=$(date '+%Y-%m-%d-%H-%M-%S')
    local backup_file="data-${date_str}.tar.gz"
   
    log_backup "INFO" "🗂️ 开始备份 $BACKUP_DIR"
   
    rm -rf "$WORK_DIR"
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
   
    if [ ! -d "$BACKUP_DIR" ]; then
        log_backup "ERROR" "备份目录 $BACKUP_DIR 不存在"
        exit 1
    fi
   
    log_backup "INFO" "📦 创建压缩包 $backup_file"
    tar -czf "$backup_file" \
        --exclude="*.tmp" \
        --exclude="*.log" \
        --exclude="node_modules" \
        --exclude=".git" \
        --exclude="dep_cache" \
        -C "$(dirname "$BACKUP_DIR")" \
        "$(basename "$BACKUP_DIR")" 2>/dev/null
   
    if [ $? -ne 0 ]; then
        log_backup "ERROR" "创建压缩包失败"
        exit 1
    fi
   
    local file_size=$(du -h "$backup_file" | cut -f1)
    log_backup "INFO" "📏 备份文件大小: $file_size"
   
    if git clone "$BACKUP_REPO_URL_WITH_TOKEN" repo 2>/dev/null; then
        log_backup "INFO" "📥 成功克隆现有仓库"
        cd repo
        git remote set-url origin "$BACKUP_REPO_URL"
    else
        log_backup "INFO" "🆕 初始化新仓库"
        mkdir repo && cd repo
        git init
        git remote add origin "$BACKUP_REPO_URL"
    fi
   
    mv "../$backup_file" .
   
    log_backup "INFO" "📝 更新 README.md"
    update_readme "$backup_file"
   
    mapfile -t backups < <(ls -1 data-*.tar.gz 2>/dev/null | sort -r)
    
    local total=${#backups[@]}
    local keep=3
    
    if [ $total -gt $keep ]; then
        log_backup "INFO" "当前有 $total 个备份，删除 $(($total - $keep)) 个最旧的"
        for ((i=$keep; i<$total; i++)); do
            rm -f "${backups[$i]}"
            log_backup "INFO" "🗑️ 删除旧备份: ${backups[$i]}"
        done
    fi
   
    git rm -f --cached data-*.tar.gz 2>/dev/null || true
    git add data-*.tar.gz
    git checkout --orphan latest_backup_temp 2>/dev/null
    git add .
    git commit -m "Latest backups (keep top 3): $(date '+%Y-%m-%d %H:%M:%S')"
   
    git remote set-url origin "$BACKUP_REPO_URL_WITH_TOKEN"
    if git push origin latest_backup_temp:"$BACKUP_BRANCH" --force-with-lease 2>/dev/null; then
        log_backup "SUCCESS" "✅ 最新备份已全新推送（保留最新 3 个，无历史）"
    else
        log_backup "ERROR" "❌ 强制推送失败"
        git remote set-url origin "$BACKUP_REPO_URL"
        exit 1
    fi
   
    git remote set-url origin "$BACKUP_REPO_URL"
    git checkout "$BACKUP_BRANCH" 2>/dev/null || true
    git branch -D latest_backup_temp 2>/dev/null || true
   
    log_backup "SUCCESS" "🎉 备份任务完成"
}

main() {
    log_backup "INFO" "🚀  开始执行青龙数据备份任务"
    
    check_env
    init_git
    perform_backup
    
    cd /
    rm -rf "$WORK_DIR"
    
    log_backup "SUCCESS" "🎉  备份任务完成"
}

main "$@"
