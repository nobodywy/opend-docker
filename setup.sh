# 安装脚本 — 飞牛 NAS 上一键部署
# 用法: bash setup.sh

set -e

echo "============================================"
echo "  🚀 OpenD Docker 一键部署"
echo "============================================"

# ── 1. 检查 Docker ────────────────────────────────
echo ""
echo "1/5 检查 Docker..."
if ! command -v docker &>/dev/null; then
    echo "❌ 未安装 Docker，请在飞牛 App Center 安装 Docker"
    exit 1
fi
echo "   ✅ Docker 已安装"

if ! docker compose version &>/dev/null 2>&1; then
    echo "   ⚠️  未检测到 docker compose 插件，尝试 docker-compose..."
    COMPOSE="docker-compose"
else
    COMPOSE="docker compose"
fi
echo "   ✅ 使用: $COMPOSE"

# ── 2. 创建 macvlan 网络（如果不存在）──────────────
echo ""
echo "2/5 检查 macvlan 网络..."
if docker network ls --format '{{.Name}}' | grep -q "^macvlan_net$"; then
    echo "   ✅ macvlan_net 已存在"
else
    echo "   ⚠️  macvlan_net 不存在，正在创建..."
    echo ""
    echo "   请输入你飞牛 NAS 的网卡名称（如 ovs_eth0 / eth0 / ens18）:"
    echo "   不知道的话，在飞牛 SSH 执行: ip route show default"
    echo ""
    read -p "   网卡名称: " IFACE
    if [ -z "$IFACE" ]; then
        echo "   ❌ 未输入网卡名，跳过"
    else
        SUBNET=$(ip route show default | awk '{print $3}' | head -1 | sed 's/\.[0-9]*$/.0\/24/')
        GATEWAY=$(ip route show default | awk '{print $3}' | head -1)
        echo "   网卡: $IFACE, 子网: $SUBNET, 网关: $GATEWAY"
        docker network create \
            -d macvlan \
            --subnet="$SUBNET" \
            --gateway="$GATEWAY" \
            -o parent="$IFACE" \
            macvlan_net
        echo "   ✅ macvlan_net 已创建"
    fi
fi

# ── 3. 构建镜像 ────────────────────────────────────
echo ""
echo "3/5 构建 Docker 镜像（首次约 3-5 分钟）..."
$COMPOSE build --no-cache

# ── 4. 启动容器 ────────────────────────────────────
echo ""
echo "4/5 启动 OpenD 容器..."
mkdir -p ./opend-config
$COMPOSE up -d

# ── 5. 等待启动并检查状态 ─────────────────────────
echo ""
echo "5/5 等待 OpenD 启动..."
sleep 10

if docker ps --format '{{.Names}}' | grep -q "^opend$"; then
    echo ""
    echo "============================================"
    echo "  ✅ 部署成功！"
    echo ""
    echo "  🌐 Web 桌面:  http://<OPEND_IP>:6080"
    echo "  📡 API 连接:  host=<OPEND_IP> port=11111"
    echo ""
    echo "  📋 查看日志:  docker logs -f opend"
    echo "  🔄 重启容器:  docker restart opend"
    echo "============================================"
else
    echo ""
    echo "❌ 容器未成功启动，查看日志："
    echo "   docker logs opend"
fi
