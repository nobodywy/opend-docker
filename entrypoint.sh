#!/bin/bash
set -e

OPEND_HOME="/opt/FutuOpenD"
# 优先使用 FutuOpenD.xml（OpenD 10.x 默认），回退到 OpenD.xml
if [ -f "${OPEND_HOME}/FutuOpenD.xml" ]; then
    CONFIG="${OPEND_HOME}/FutuOpenD.xml"
else
    CONFIG="${OPEND_HOME}/OpenD.xml"
fi
LOG_DIR="${OPEND_HOME}/log"

mkdir -p "$LOG_DIR"

echo "============================================"
echo "  🚀 OpenD Docker Container"
echo "============================================"

# ── 1. 配置文件处理 ──────────────────────────────
# 如果挂载了自定义配置，覆盖默认
if [ -f /config/FutuOpenD.xml ]; then
    echo "📄 使用挂载的自定义配置: /config/FutuOpenD.xml"
    cp /config/FutuOpenD.xml "$CONFIG"
elif [ -f /config/OpenD.xml ]; then
    echo "📄 使用挂载的自定义配置: /config/OpenD.xml"
    cp /config/OpenD.xml "$CONFIG"
fi

# 强制监听 0.0.0.0（Docker 内必须）—— 兼容前后空格
sed -i 's|^[[:space:]]*<ip>[0-9.]*</ip>|  <ip>0.0.0.0</ip>|' "$CONFIG" 2>/dev/null || true
sed -i 's|^[[:space:]]*<telnet_ip>[0-9.]*</telnet_ip>|  <telnet_ip>0.0.0.0</telnet_ip>|' "$CONFIG" 2>/dev/null || true

# 删除所有 login_pwd_md5 行（注释/非注释），避免 MD5 格式错误导致 OpenD 退出
sed -i '/login_pwd_md5/d' "$CONFIG" 2>/dev/null || true

# 清掉 tarball 自带的假账号密码
if [ -z "$FUTU_LOGIN_ACCOUNT" ]; then
    # 检查当前 xml 是否有非空账户（比如自带的假账号 100000）
    CURRENT_ACCT=$(grep -oP '<login_account>\K[^<]*' "$CONFIG" 2>/dev/null || echo "")
    if [ -n "$CURRENT_ACCT" ] && [ "$CURRENT_ACCT" = "100000" ]; then
        echo "🧹 清除 tarball 自带假账号"
        sed -i 's|<login_account>[^<]*</login_account>|<login_account></login_account>|' "$CONFIG"
        sed -i 's|<login_pwd>[^<]*</login_pwd>|<login_pwd></login_pwd>|' "$CONFIG"
    fi
fi

# 环境变量自动填入账号密码
if [ -n "$FUTU_LOGIN_ACCOUNT" ]; then
    echo "🔐 配置登录账号: $FUTU_LOGIN_ACCOUNT"
    sed -i "s|<login_account>[^<]*</login_account>|<login_account>${FUTU_LOGIN_ACCOUNT}</login_account>|" "$CONFIG"
fi
if [ -n "$FUTU_LOGIN_PWD" ]; then
    echo "🔐 配置登录密码: ****"
    sed -i "s|<login_pwd>[^<]*</login_pwd>|<login_pwd>${FUTU_LOGIN_PWD}</login_pwd>|" "$CONFIG"
fi

echo "📋 当前 OpenD 配置:"
grep -E '(login_account|login_pwd|ip>|api_port)' "$CONFIG" | sed 's/<login_pwd>[^<]*<\/login_pwd>/<login_pwd>****<\/login_pwd>/'
echo ""

# ── 2. 启动 TigerVNC X 服务器（自带 VNC）───────────
echo "🖥️  启动 TigerVNC X 服务器 :1..."
# 清理残留
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null
# TigerVNC: 内建 X 服务器 + VNC，显示 :1 = 端口 5901，仅本地
Xtigervnc :1 \
    -geometry 1280x720 -depth 24 \
    -localhost -SecurityTypes None \
    -AlwaysShared -AcceptSetDesktopSize=0 \
    &>/tmp/tigervnc.log &
sleep 4

# 检查是否启动成功
if ! pgrep Xtigervnc >/dev/null; then
    echo "❌ TigerVNC 启动失败！日志:"
    cat /tmp/tigervnc.log
    exit 1
fi
echo "✅ TigerVNC X 服务器已启动 (DISPLAY=:1, VNC=5901)"

# ── 3. 启动窗口管理器 + 桌面 ───────────────────────
echo "🪟 启动 Openbox..."
DISPLAY=:1 openbox &
sleep 1

echo "🎨 设置桌面背景..."
DISPLAY=:1 xsetroot -solid "#2e3440" 2>/dev/null || true

# ── 4. 启动 OpenD GUI ─────────────────────────────
echo "📈 启动 FutuOpenD..."
cd "$OPEND_HOME"
export LD_LIBRARY_PATH="${OPEND_HOME}:${LD_LIBRARY_PATH}"
export LIBGL_ALWAYS_SOFTWARE=1
DISPLAY=:1 ./FutuOpenD &
OPEND_PID=$!
sleep 5

if ! kill -0 $OPEND_PID 2>/dev/null; then
    echo "❌ OpenD 启动失败！检查日志:"
    tail -50 "$LOG_DIR"/*.log 2>/dev/null || echo "  无日志文件"
    exit 1
fi
echo "✅ FutuOpenD 已启动 (PID: $OPEND_PID)"

# ── 5. 启动 noVNC Web 服务 ─────────────────────────
echo "🌐 启动 noVNC (Web GUI → 端口 6080)..."
websockify --web /usr/share/novnc/ 0.0.0.0:6080 127.0.0.1:5901 &
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
echo "  📞 Telnet CLI : 端口 22222 (无需 GUI 也能登录)"
echo "  🌐 桌面 GUI   : http://<ip>:6080"
echo "  🔑 首次登录   : 在 Web GUI 扫码/输密码"
echo "  🔑 备选方案   : Telnet CLI (GUI 不显示时可用)"
echo "      docker exec -it opend bash"
echo "      printf 'input_phone_verify_code -code=XXXXXX\\\r\\\n' | socat -t10 - TCP:localhost:22222"
echo "  🔓 实盘交易   : 在 Web GUI 中点「解锁交易」"
echo "============================================"

# ── 保持容器运行 + 健康监控 ─────────────────────
trap "echo '🛑 收到退出信号，清理...'; kill $OPEND_PID $NOVNC_PID 2>/dev/null; exit 0" SIGTERM SIGINT

while true; do
    if ! kill -0 $OPEND_PID 2>/dev/null; then
        echo "❌ OpenD 进程已退出！检查日志 ↓"
        tail -30 "$LOG_DIR"/*.log 2>/dev/null
        exit 1
    fi
    sleep 10
done
