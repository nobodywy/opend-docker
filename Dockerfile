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
    libgtk2.0-0 libcanberra-gtk-module libcanberra-gtk3-module \
    libx11-xcb1 libxcb1 libxcb-util1 \
    && rm -rf /var/lib/apt/lists/*

# ── noVNC 设置 ────────────────────────────────────
RUN ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html

# ── 下载安装 OpenD ─────────────────────────────────
# 先下载到 /tmp，再解压到 /opt/
# OpenD tarball 结构可能是 Futu_OpenD_x.x.x/ 或嵌套多层
WORKDIR /opt
COPY <<'DOCKEREOF' /tmp/install_opend.sh
#!/bin/bash
set -e

echo "📥 下载 OpenD..."
curl -fsSL -o /tmp/opend.tar.gz \
    "https://www.futunn.com/download/fetch-lasted-link?name=opend-ubuntu"

echo "📦 解压..."
tar xzf /tmp/opend.tar.gz -C /opt/
rm /tmp/opend.tar.gz

# 找到 FutuOpenD 可执行文件所在目录
OPEND_BIN=$(find /opt -maxdepth 4 -name "FutuOpenD" -type f 2>/dev/null | head -1)

if [ -z "$OPEND_BIN" ]; then
    echo "❌ 未找到 FutuOpenD 可执行文件！"
    echo "   解压后目录结构:"
    find /opt -maxdepth 3 -type d | head -20
    exit 1
fi

OPEND_DIR=$(dirname "$OPEND_BIN")
echo "✅ 找到 OpenD: $OPEND_DIR"

# 把内层目录整体移到 /opt/FutuOpenD/
# （OpenD tarball 可能是 Futu_OpenD_x.x/Futu_OpenD_x.x/FutuOpenD 双层嵌套）
if [ "$OPEND_DIR" != "/opt/FutuOpenD" ]; then
    rm -rf /opt/FutuOpenD 2>/dev/null || true
    mv "$OPEND_DIR" /opt/FutuOpenD
    echo "✅ 移至 /opt/FutuOpenD"
fi

# 清理外层残余空目录
find /opt -maxdepth 1 -type d -name "Futu_OpenD*" ! -name FutuOpenD -exec rm -rf {} \; 2>/dev/null || true

chmod +x /opt/FutuOpenD/FutuOpenD

# 确保有配置文件（可能叫 OpenD.xml 或 FutuOpenD.xml）
if [ ! -f /opt/FutuOpenD/OpenD.xml ] && [ ! -f /opt/FutuOpenD/FutuOpenD.xml ]; then
    echo "📝 创建默认 OpenD.xml ..."
    cat > /opt/FutuOpenD/OpenD.xml << 'XML'
<?xml version="1.0" encoding="utf-8"?>
<config>
  <login_account></login_account>
  <login_pwd></login_pwd>
  <ip>0.0.0.0</ip>
  <port>11111</port>
  <telnet_ip>0.0.0.0</telnet_ip>
  <telnet_port>22222</telnet_port>
  <log_level>info</log_level>
</config>
XML
fi

echo "📋 /opt/FutuOpenD/ 内容:"
ls -la /opt/FutuOpenD/
echo "✅ OpenD 安装完成"
DOCKEREOF

RUN bash /tmp/install_opend.sh && rm /tmp/install_opend.sh

# ── 复制入口脚本 ───────────────────────────────────
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# ── 端口 ──────────────────────────────────────────
EXPOSE 11111 6080

ENTRYPOINT ["/entrypoint.sh"]
