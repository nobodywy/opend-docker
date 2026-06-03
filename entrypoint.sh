#!/bin/bash
set -e

OPEND_HOME="/opt/FutuOpenD"
CONFIG="${OPEND_HOME}/OpenD.xml"
LOG_DIR="${OPEND_HOME}/log"

mkdir -p "$LOG_DIR"

echo "============================================"
echo "  🚀 OpenD Docker Container"
echo "============================================"

# ── 1. 配置文件处理 ──────────────────────────────
if [ -f /config/OpenD.xml ]; then
    echo "📄 使用挂载的自定义配置: /config/OpenD.xml"
    cp /config/OpenD.xml "$CONFIG"
fi

# 强制监听 0.0.0.0（Docker 内必须）
sed -i 's|<ip>127.0.0.1</ip>|<ip>0.0.0.0</ip>|' "$CONFIG" 2>/dev/null || true
sed -i 's|<ip>localhost</ip>|<ip>0.0.0.0</ip>|' "$CONFIG" 2>/dev/null || true
sed -i 's|<telnet_ip>127.0.0.1</telnet_ip>|<telnet_ip>0.0.0.0</telnet_ip>|' "$CONFIG" 2>/dev/null || true

# 如果设了环境变量，自动填入账号密码
if [ -n "$FUTU_LOGIN_ACCOUNT" ]; then
    echo "🔐 配置登录账号: $FUTU_LOGIN_ACCOUNT"
    sed -i "s|<login_account>.*</login_account>|<login_account>${FUTU_LOGIN_ACCOUNT}</login_account>|" "$CONFIG"
fi
if [ -n "$FUTU_LOGIN_PWD" ]; then
    echo "🔐 配置登录密码: ****"
    sed -i "s|<login_pwd>.*</login_pwd>|<login_pwd>${FUTU_LOGIN_PWD}</login_pwd>|" "$CONFIG"
fi

echo "📋 当前 OpenD 配置:"
grep -E "(login_account|ip>|port>)" "$CONFIG" | sed 's/<login_pwd>.*<\/login_pwd>/<login_pwd>****<\/login_pwd>/'
echo ""

# ── 2. 清理残留锁文件 + 启动虚拟显示器 ──────────────
echo "🖥️  启动 Xvfb (虚拟显示器 :1)..."
# 清理可能残留的 X 锁文件（容器重启导致）
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null
Xvfb :1 -screen 0 ${VNC_RESOLUTION:-1280x720x16} -ac +extension GLX +render &
XVFB_PID=$!
sleep 1

if ! kill -0 $XVFB_PID 2>/dev/null; then
    echo "❌ Xvfb 启动失败！"
    exit 1
fi
echo "✅ Xvfb 已启动 (PID: $XVFB_PID)"

# ── 3. 启动轻量窗口管理器 ──────────────────────────
echo "🪟 启动 Openbox..."
openbox --replace &
sleep 1

# ── 4. 启动 OpenD GUI ─────────────────────────────
echo "📈 启动 FutuOpenD..."
cd "$OPEND_HOME"
DISPLAY=:1 ./FutuOpenD &
OPEND_PID=$!
sleep 5

if ! kill -0 $OPEND_PID 2>/dev/null; then
    echo "❌ OpenD 启动失败！检查日志:"
    tail -50 "$LOG_DIR"/*.log 2>/dev/null || echo "  无日志文件"
    exit 1
fi
echo "✅ FutuOpenD 已启动 (PID: $OPEND_PID)"

# ── 5. 启动 VNC 服务 ───────────────────────────────
echo "🖥️  启动 x11vnc..."
x11vnc -display :1 -forever -nopw -quiet -shared -listen 127.0.0.1 &
X11VNC_PID=$!
sleep 2

if ! kill -0 $X11VNC_PID 2>/dev/null; then
    echo "⚠️  x11vnc 启动失败！Web GUI 将不可用"
fi
echo "✅ x11vnc 已启动 (PID: $X11VNC_PID)"

# ── 6. 启动 noVNC Web 服务 ─────────────────────────
echo "🌐 启动 noVNC (Web GUI → 端口 6080)..."
websockify --web /usr/share/novnc/ 0.0.0.0:6080 127.0.0.1:5900 &
NOVNC_PID=$!
sleep 1

if kill -0 $NOVNC_PID 2>/dev/null; then
    echo "✅ noVNC 已启动 (PID: $NOVNC_PID)"
    echo "   🌍 浏览器打开 http://<容器IP>:6080 即可看到 OpenD 桌面"
else
    echo "⚠️  noVNC 启动失败！"
fi

echo ""
echo "============================================"
echo "  ✅ 所有服务已启动"
echo ""
echo "  📡 OpenD API  : 端口 11111"
echo "  🌐 桌面 GUI   : http://<ip>:6080"
echo "  🔑 首次登录   : 在 Web GUI 中扫码/输入密码"
echo "  🔓 实盘交易   : 在 Web GUI 中点「解锁交易」"
echo "============================================"

# ── 保持容器运行 + 健康监控 ─────────────────────
# 如果 OpenD 挂了，容器也跟着退出
trap "echo '🛑 收到退出信号，清理...'; kill $OPEND_PID $XVFB_PID $X11VNC_PID $NOVNC_PID 2>/dev/null; exit 0" SIGTERM SIGINT

while true; do
    if ! kill -0 $OPEND_PID 2>/dev/null; then
        echo "❌ OpenD 进程已退出！检查日志 ↓"
        tail -30 "$LOG_DIR"/*.log 2>/dev/null
        exit 1
    fi
    sleep 10
done
