FROM whyour/qinglong:latest

# 安装 cron 服务用于定时备份（Alpine Linux 使用 apk）
RUN apk add --no-cache dcron

# 将自定义脚本和 requirements.txt 复制到容器中的 /ql/custom 目录
COPY main.sh backup-to-github.sh requirements.txt /ql/custom/

WORKDIR /ql

# 给所有 .sh 脚本添加执行权限
RUN chmod 777 /ql/custom/*.sh

# 安装 requirements.txt 中列出的所有 Python 依赖
RUN pip install -r /ql/custom/requirements.txt

# 设置容器的入口点
ENTRYPOINT ["/ql/custom/main.sh"]


