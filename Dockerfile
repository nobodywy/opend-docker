FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:1
ENV VNC_RESOLUTION=1280x720x16

# ── 系统依赖 ──────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl wget unzip xz-utils \
    xvfb x11vnc novnc websockify \
    openbox xterm x11-xserver-utils \
    libglib2.0-0 libnss3 libgconf-2-4 libxss1 \
    libasound2 libatk-bridge2.0-0 libgtk-3-0 \
    libxkbcommon0 libgbm1 libdrm2 \
    libxcomposite1 libxcursor1 libxi6 libxrandr2 \
    libxtst6 libxdamage1 libva2 libva-drm2 \
    libnspr4 \
    && rm -rf /var/lib/apt/lists/*

# ── noVNC 设置 ────────────────────────────────────
RUN ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html

# ── 下载安装 OpenD ─────────────────────────────────
WORKDIR /opt
RUN curl -sL -o /tmp/opend.tar.gz \
    "https://www.futunn.com/download/fetch-lasted-link?name=opend-ubuntu" \
    && mkdir -p /tmp/opend_extract \
    && tar xzf /tmp/opend.tar.gz -C /tmp/opend_extract --strip-components=1 2>/dev/null \
    || tar xzf /tmp/opend.tar.gz -C /tmp/opend_extract \
    && mkdir -p /opt/FutuOpenD \
    && find /tmp/opend_extract -name "FutuOpenD" -type f -exec cp {} /opt/FutuOpenD/ \; \
    && find /tmp/opend_extract -name "*.so*" -exec cp {} /opt/FutuOpenD/ \; 2>/dev/null || true \
    && find /tmp/opend_extract -name "OpenD.xml" -exec cp {} /opt/FutuOpenD/ \; 2>/dev/null || true \
    && ls -la /tmp/opend_extract \
    && chmod +x /opt/FutuOpenD/FutuOpenD \
    && rm -rf /tmp/opend.tar.gz /tmp/opend_extract \
    && echo "✅ OpenD installed at /opt/FutuOpenD/"

# ── 默认 OpenD 配置 ────────────────────────────────
# 如果解压时没有拿到 OpenD.xml，创建一个默认的
RUN if [ ! -f /opt/FutuOpenD/OpenD.xml ]; then \
    echo '<?xml version="1.0" encoding="utf-8"?>' > /opt/FutuOpenD/OpenD.xml; \
    echo '<config>' >> /opt/FutuOpenD/OpenD.xml; \
    echo '  <login_account></login_account>' >> /opt/FutuOpenD/OpenD.xml; \
    echo '  <login_pwd></login_pwd>' >> /opt/FutuOpenD/OpenD.xml; \
    echo '  <ip>0.0.0.0</ip>' >> /opt/FutuOpenD/OpenD.xml; \
    echo '  <port>11111</port>' >> /opt/FutuOpenD/OpenD.xml; \
    echo '  <telnet_ip>0.0.0.0</telnet_ip>' >> /opt/FutuOpenD/OpenD.xml; \
    echo '  <telnet_port>22222</telnet_port>' >> /opt/FutuOpenD/OpenD.xml; \
    echo '  <log_level>info</log_level>' >> /opt/FutuOpenD/OpenD.xml; \
    echo '</config>' >> /opt/FutuOpenD/OpenD.xml; \
    fi

# ── 复制入口脚本 ───────────────────────────────────
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# ── 端口 ──────────────────────────────────────────
# 11111: OpenD API
# 6080:  noVNC Web 界面
EXPOSE 11111 6080

ENTRYPOINT ["/entrypoint.sh"]
