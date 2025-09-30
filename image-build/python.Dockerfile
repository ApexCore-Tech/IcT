
FROM python:3.8.20-slim-bookworm AS builder

ARG HTTP_PROXY=""
ARG PYPI_REGISTRY=""

# - DEBIAN_FRONTEND=noninteractive 避免 apt-get 安装过程中出现配置对话框，保证自动化构建
# - PYTHONUNBUFFERED=1 禁用 Python 输出缓存，直接输出日志和打印内容，便于在 Docker 容器内实时查看
# - PYTHONDONTWRITEBYTECODE=1 禁止 Python 生成 .pyc 字节码文件
# - PIP_NO_CACHE_DIR=1 禁用 pip 缓存
# - PIP_DISABLE_PIP_VERSION_CHECK=1 禁用 pip 版本检查警告
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN rm -f /etc/apt/sources.list /etc/apt/sources.list.d/* && \
    echo "deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm main contrib non-free non-free-firmware" > /etc/apt/sources.list && \
    echo "deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-updates main contrib non-free non-free-firmware" >> /etc/apt/sources.list && \
    echo "deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-backports main contrib non-free non-free-firmware" >> /etc/apt/sources.list && \
    echo "deb https://mirrors.tuna.tsinghua.edu.cn/debian-security bookworm-security main contrib non-free non-free-firmware" >> /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        gcc \
        python3-dev \
        build-essential && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /app

COPY requirement-ops.txt .
RUN python -m venv /opt/venv && \
    /opt/venv/bin/pip install ${HTTP_PROXY:+--proxy $HTTP_PROXY} --no-cache-dir -r requirement-ops.txt ${PYPI_REGISTRY:+-i $PYPI_REGISTRY} || exit 1 && \
    /opt/venv/bin/pip list | grep -E "gunicorn|gevent" || (echo "Missing required packages" && exit 1) && \
    find /opt/venv -name "*.pyc" -delete && \
    find /opt/venv -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

COPY requirements-prod.txt .
RUN /opt/venv/bin/pip install ${HTTP_PROXY:+--proxy $HTTP_PROXY} --no-cache-dir -r requirement-prod.txt ${PYPI_REGISTRY:+-i $PYPI_REGISTRY} || exit 1 && \
    find /opt/venv -name "*.pyc" -delete && \
    find /opt/venv -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

FROM python:3.8.20-slim-bookworm AS runtime

ARG VERSION_DATE="20250930"
ARG BUILD_DATE="2025-09-30T23:00:00Z"
ARG COMMIT_HASH=""
ARG COMMIT_HASH_SHORT=""
ARG OS_ARCH="amd64"
ARG OS_SYS="linux"
ARG GIT_URL="https://github.com/ApexCore-Tech"
ARG BUILD_ENV="prod"
ARG EXPOSE_PORT="8000"

LABEL org.opencontainers.image.title="Demo Python App" \
      org.opencontainers.image.description="Demo Python App" \
      org.opencontainers.image.authors="jinhang<hang.j@foxmail.com>" \
      org.opencontainers.image.vendor="ApexCore Co, Ltd." \
      org.opencontainers.image.ref.name="1.0.0" \
      org.opencontainers.image.version="v1.0.0-release+${VERSION_DATE}.${COMMIT_HASH_SHORT}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${COMMIT_HASH}" \
      org.opencontainers.image.architecture="${OS_ARCH}" \
      org.opencontainers.image.os="${OS_SYS}" \
      org.opencontainers.image.source="${GIT_URL}" \
      tech.apexcore.environment="${BUILD_ENV}" \
      tech.apexcore.team="DevOps" \
      tech.apexcore.business.unit="Algorithm Division"

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    TZ=Asia/Shanghai \
    PATH="/opt/venv/bin:$PATH" \
    EXPOSE_PORT=${EXPOSE_PORT:-8000}

WORKDIR /app

RUN rm -f /etc/apt/sources.list /etc/apt/sources.list.d/* && \
    echo "deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm main contrib non-free non-free-firmware" > /etc/apt/sources.list && \
    echo "deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-updates main contrib non-free non-free-firmware" >> /etc/apt/sources.list && \
    echo "deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-backports main contrib non-free non-free-firmware" >> /etc/apt/sources.list && \
    echo "deb https://mirrors.tuna.tsinghua.edu.cn/debian-security bookworm-security main contrib non-free non-free-firmware" >> /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        gettext && \
    apt-get autoremove -y && \
    apt-get autoclean -y && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/cache/apt/archives/* && \
    addgroup -S app && \
    adduser -S app -G app

COPY --from=builder --chown=app:app /opt/venv /opt/venv
COPY --chown=app:app . /app


USER app

EXPOSE ${EXPOSE_PORT:-8000}

ENTRYPOINT ["gunicorn"]
CMD ["myapp.wsgi:application", "--bind", "0.0.0.0", "--workers", "4"]

HEALTHCHECK --start-period=30s CMD ["sh", "-c", "curl -fSs http://127.0.0.1:$EXPOSE_PORT/health || exit 1"]
