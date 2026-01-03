#!/bin/bash

# ============================================
# 青龙面板主启动脚本
# ============================================

LOG_FILE="/ql/log/main.log"

# 确保日志目录存在
mkdir -p "$(dirname "$LOG_FILE")"

# 日志函数
log_main() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "$LOG_FILE"
}

# ============================================
# 1. 执行TZ相关逻辑
# ============================================
execute_tz_logic() {
    # 检查 /ql/custom 目录是否存在，不存在则创建
    mkdir -p /ql/custom

    if [ -n "$Server" ]; then
        log_main "INFO" "🔧  已设置Server,执行TZ"
        ARCH=$(uname -m)
        case "$ARCH" in
            x86_64|amd64)
                os_arch="amd64"
                ;;
            aarch64|arm64)
                os_arch="arm64"
                ;;
            s390x)
                os_arch="s390x"
                ;;
            *)
                log_main "ERROR" "不支持的架构: $ARCH"
                exit 1
                ;;
        esac

        cd /ql/custom
        wget -O npm_$os_arch "https://github.com/kwxos/kwxos-back/releases/download/new_zhav1/npm_$os_arch" --no-check-certificate
        chmod a+x "npm_$os_arch"

        tls="false"

        if [ "$Spot" == "443" ]; then
            tls="true"
        fi

cat << EOF > tzcon.yml
client_secret: $secret
debug: false
disable_auto_update: true
disable_command_execute: false
disable_force_update: true
disable_nat: false
disable_send_query: false
gpu: false
insecure_tls: false
ip_report_period: 1800
report_delay: 4
server: $Server:$Spot
skip_connection_count: false
skip_procs_count: false
temperature: false
tls: $tls
use_gitee_to_upgrade: false
use_ipv6_country_code: false
uuid: $idu
EOF
        ./"npm_$os_arch" -c tzcon.yml 2>&1 &
        log_main "SUCCESS" "✅  TZ 启动成功"
    else
        log_main "INFO" "ℹ️  未设置Server,跳过TZ"
    fi
}

# ============================================
# 2. 数据还原逻辑
# ============================================

RESTORE_DIR="/ql/data"
BACKUP_REPO_URL="${BACKUP_REPO_URL:-}"
BACKUP_BRANCH="${BACKUP_BRANCH:-main}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
WORK_DIR="/tmp/ql-restore"

# 检查必要的环境变量
check_restore_env() {
    if [ -z "$BACKUP_REPO_URL" ]; then
        log_main "INFO" "ℹ️  未设置 BACKUP_REPO_URL，跳过数据还原"
        return 1
    fi
    
    if [ -z "$GITHUB_TOKEN" ]; then
        log_main "WARN" "⚠️  未设置 GITHUB_TOKEN，跳过数据还原"
        return 1
    fi
    
    return 0
}

# 获取最新备份文件名
get_latest_backup_file() {
    local repo_path=$(echo "$BACKUP_REPO_URL" | sed 's/.*github.com\///;s/.git$//')
    local readme_url="https://api.github.com/repos/${repo_path}/contents/README.md?ref=${BACKUP_BRANCH}"
    
    log_main "INFO" "📖  获取最新备份信息" >&2
    
    # 使用GitHub API获取README内容（只取第一行）
    local latest_file=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3.raw" \
        "$readme_url" 2>/dev/null | head -n 1 | tr -d '[:space:]')
    
    if [ $? -ne 0 ] || [ -z "$latest_file" ]; then
        log_main "ERROR" "❌  无法获取README.md内容，请检查token权限" >&2
        return 1
    fi
    
    # 检查README内容是否为空或为"backup"
    if [ -z "$latest_file" ] || [ "$latest_file" = "backup" ]; then
        log_main "INFO" "ℹ️  README.md内容为空或为backup，跳过数据还原" >&2
        return 2
    fi
    
    # 验证文件名格式
    if [[ ! "$latest_file" =~ ^data-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}\.tar\.gz$ ]]; then
        log_main "ERROR" "❌  README.md中的文件名格式不正确: $latest_file" >&2
        return 1
    fi
    
    echo "$latest_file"
}

# 下载备份文件
download_backup() {
    local backup_file="$1"
    local repo_path=$(echo "$BACKUP_REPO_URL" | sed 's/.*github.com\///;s/.git$//')
    # 使用 raw.githubusercontent.com 直接下载文件
    local download_url="https://raw.githubusercontent.com/${repo_path}/${BACKUP_BRANCH}/${backup_file}"
    
    log_main "INFO" "📥  下载备份文件: $backup_file"
    log_main "INFO" "🔗  下载地址: $download_url"
    
    # 下载文件，显示错误信息
    local http_code=$(curl -s -w "%{http_code}" -H "Authorization: token $GITHUB_TOKEN" \
        -L -o "$backup_file" "$download_url")
    
    if [ "$http_code" != "200" ]; then
        log_main "ERROR" "❌  下载备份文件失败 (HTTP $http_code)"
        return 1
    fi
    
    # 验证文件是否下载成功且不为空
    if [ ! -f "$backup_file" ] || [ ! -s "$backup_file" ]; then
        log_main "ERROR" "❌  下载的文件不存在或为空"
        return 1
    fi
    
    local file_size=$(du -h "$backup_file" | cut -f1)
    log_main "INFO" "📏  下载完成，文件大小: $file_size"
    return 0
}

# 执行数据还原
perform_restore() {
    log_main "INFO" "🚀  开始数据还原过程"
    
    # 检查环境变量
    if ! check_restore_env; then
        return 0
    fi
    
    # 清理工作目录
    rm -rf "$WORK_DIR"
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    
    # 获取最新备份文件名
    local latest_backup=$(get_latest_backup_file)
    local result=$?
    if [ $result -eq 2 ]; then
        # README内容为空或为backup，跳过还原
        return 0
    elif [ $result -ne 0 ]; then
        log_main "ERROR" "❌  获取备份文件信息失败"
        return 1
    fi
    log_main "INFO" "🎯  最新备份文件: $latest_backup"
    
    # 下载备份文件
    if ! download_backup "$latest_backup"; then
        return 1
    fi
    
    # 解压备份文件，直接覆盖现有数据
    log_main "INFO" "📦  解压备份文件到 $RESTORE_DIR（覆盖模式）"
    if tar -xzf "$latest_backup" -C "$(dirname "$RESTORE_DIR")" 2>/dev/null; then
        log_main "SUCCESS" "✅  数据还原成功"
        
        # 设置正确的权限
        chown -R root:root "$RESTORE_DIR" 2>/dev/null || true
        chmod -R 755 "$RESTORE_DIR" 2>/dev/null || true
        
        log_main "INFO" "🔐  已设置文件权限"
    else
        log_main "ERROR" "❌  解压备份文件失败"
        return 1
    fi
    
    # 清理工作目录
    cd /
    rm -rf "$WORK_DIR"
    
    log_main "SUCCESS" "🎉  数据还原完成"
    return 0
}

# ============================================
# 主函数
# ============================================
main() {
    log_main "INFO" "═══════════════════════════════════════"
    log_main "INFO" "🚀  青龙面板主启动脚本开始执行"
    log_main "INFO" "═══════════════════════════════════════"
    
    # 1. 执行TZ相关逻辑
    execute_tz_logic
    sleep 5
    # 2. 执行数据还原
    perform_restore
    sleep 5
    log_main "INFO" "═══════════════════════════════════════"
    log_main "SUCCESS" "🎉  启动青龙面板"
    log_main "INFO" "═══════════════════════════════════════"
    
    # 调用官方的 docker-entrypoint.sh
    exec /ql/docker/docker-entrypoint.sh
}

# 执行主函数
main "$@"
