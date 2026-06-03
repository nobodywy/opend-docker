# OpenD Docker — 飞牛 NAS 一键部署

> 把富途 OpenD 跑在飞牛 NAS 的 Docker 里，**带 Web 图形桌面**，24h 运行，不需要开你电脑。

## 🎯 这是什么

一个 Docker 化的 OpenD（富途 OpenAPI 网关），包含：

| 组件 | 作用 |
|------|------|
| **OpenD** | 富途行情+交易 API 网关，端口 `11111` |
| **Xvfb** | 虚拟显示器，让 OpenD GUI 在无头服务器上运行 |
| **x11vnc + noVNC** | Web 浏览器访问 OpenD 桌面，端口 `6080` |
| **一键部署脚本** | 自动创建 macvlan 网络、构建、启动 |

## 🏠 在你的网络里长什么样

```
飞牛 NAS (<NAS_IP>)
  ├─ OpenClaw (<OPENCLAW_IP>) ── Python SDK → 调 OpenD API
  ├─ 小红书 MCP (<MCP_IP>)
  ├─ OpenD (<OPEND_IP>) ← 新增
  │    ├─ :11111  API 端口
  │    └─ :6080   Web GUI (浏览器打开看桌面)
  └─ NPM 反代 → 外网访问
```

## 📦 部署（3 步）

### 第 1 步：把项目拉到飞牛

```bash
# SSH 进飞牛
ssh admin@<NAS_IP>

# 克隆
cd ~
git clone https://github.com/<YOUR_GITHUB>/opend-docker.git
cd opend-docker
```

### 第 2 步：一键安装

```bash
chmod +x setup.sh
bash setup.sh
```

脚本会自动：
1. 检测 Docker 环境
2. 检测/创建 macvlan 网络（如果已存在则跳过）
3. 构建镜像（首次 ~3-5 分钟）
4. 启动容器

### 第 3 步：打开 Web GUI 登录

浏览器打开：**`http://<OPEND_IP>:6080`**

你会看到 OpenD 的桌面界面：
1. 🔑 **首次登录**：在桌面上 OpenD GUI 窗口里扫码或输入密码登录
2. 🔓 **实盘交易**：需要点了「解锁交易」后才能通过 API 下单
3. 登录态会持久化到 `opend-config/` 目录，重启容器不用重新登录

---

## 🧪 验证 API 连通性

```bash
# 从 OpenClaw 容器测试
docker exec openclaw python3 -c "
from futu import OpenQuoteContext
ctx = OpenQuoteContext(host='<OPEND_IP>', port=11111)
ret, data = ctx.get_market_snapshot(['US.NVDA'])
print(f'NVDA: {data[\"last_price\"].iloc[0]}')
ctx.close()
"
```

能打印出 NVDA 价格就 OK。

---

## 🛠 日常操作

```bash
# 查看日志
docker logs -f opend

# 查看容器状态
docker ps -f name=opend

# 重启
docker restart opend

# 停止
docker stop opend

# 完全重建
docker compose down && docker compose up -d --build
```

---

## 🔧 可选：外网访问 Web GUI

在 Nginx Proxy Manager 中添加反代规则：

| 项目 | 值 |
|------|-----|
| 域名 | `opend.<YOUR_DOMAIN>` |
| 目标 | `http://<OPEND_IP>:6080` |
| WebSocket | ✅ 开启 |

然后手机/外网浏览器访问 `https://opend.<YOUR_DOMAIN>` 就能远程操作 OpenD。

---

## ⚙️ 配置说明

### 自动登录（可选）

编辑 `docker-compose.yml`，取消注释：

```yaml
environment:
  FUTU_LOGIN_ACCOUNT: "你的牛牛号"
  FUTU_LOGIN_PWD: "你的密码"
```

然后 `docker compose up -d` 重建，容器启动时会自动填入账号密码。

### 自定义 OpenD 配置

把自定义 `OpenD.xml` 放到 `opend-config/` 目录，容器启动时自动使用它。

---

## 📁 文件说明

```
opend-docker/
├── Dockerfile          # Docker 镜像定义（Ubuntu + OpenD + VNC）
├── docker-compose.yml  # 容器编排（macvlan 网络 + 持久化）
├── entrypoint.sh       # 容器入口脚本（启动 Xvfb → OpenD → VNC → Web）
├── setup.sh            # 一键部署脚本
└── README.md           # 本文件
```
