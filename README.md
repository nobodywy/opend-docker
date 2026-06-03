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
飞牛 NAS
  ├─ OpenClaw ── Python SDK → 调 OpenD API
  ├─ OpenD (macvlan 独立 IP) ← 新增
  │    ├─ :11111  API 端口
  │    └─ :6080   Web GUI (浏览器打开看桌面)
  └─ NPM 反代 → 外网访问（可选）
```

## 📦 部署（4 步）

### 第 1 步：设置静态 IP

编辑 `docker-compose.yml`，修改 OpenD 的 macvlan 静态 IP：

```yaml
networks:
  openclaw_lan_net:
    ipv4_address: <你的 OpenD IP>
```

### 第 2 步：把项目拉到飞牛

```bash
# SSH 进飞牛
ssh <用户名>@<NAS_IP>

# 克隆（替换为你的仓库地址）
cd ~
git clone https://github.com/<YOUR_GITHUB>/opend-docker.git
cd opend-docker
```

### 第 3 步：一键安装

```bash
chmod +x setup.sh
bash setup.sh
```

脚本会自动：
1. 检测 Docker 环境
2. 检测/创建 macvlan 网络（如果已存在则跳过）
3. 构建镜像（首次 ~3-5 分钟）
4. 启动容器

### 第 4 步：打开 Web GUI 登录

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
| 域名 | `opend.<你的域名>` |
| 目标 | `http://<OPEND_IP>:6080` |
| WebSocket | ✅ 开启 |

然后手机/外网浏览器访问 `https://opend.<你的域名>` 就能远程操作 OpenD。

---

## ⚙️ 配置说明

### 自动登录（可选）

编辑 `docker-compose.yml`，添加环境变量：

```yaml
environment:
  FUTU_LOGIN_ACCOUNT: "你的牛牛号"
  FUTU_LOGIN_PWD: "你的密码"
```

然后 `docker compose up -d` 重建，容器启动时会自动填入账号密码。

> ⚠️ 自动填入密码后仍需手动完成手机验证码（见下方[排障章节](#-常见问题--排障)）。

### 自定义 OpenD 配置

把自定义 `OpenD.xml` 放到 `opend-config/` 目录，容器启动时自动使用它。

---

## 🔧 常见问题 & 排障

### GUI 桌面打开但看不到 OpenD 窗口

**症状**：浏览器打开 `http://<OPEND_IP>:6080` 能看到 noVNC 灰色桌面，但上面没有 OpenD 登录窗口。

**原因**：OpenD GUI 在 Docker 软件渲染环境下可能无法正确绘制窗口（Qt/X11 兼容性问题），但 OpenD 进程本身正常运行，API 端口 `11111` 和 Telnet 端口 `22222` 都已就绪。

**解决**：**不要依赖 GUI，直接用 Telnet CLI 完成首次登录。**

#### 🔑 通过 Telnet CLI 完成登录

```bash
# 进入容器
docker exec -it opend bash

# 安装 socat（如果 Dockerfile 版本较旧未预装）
apt-get install -y socat

# 查看 OpenD 日志，确认进入了验证码阶段
cat /root/.com.futunn.FutuOpenD/Log/GTWLog_0_*.log | grep "phone_verify_code" | tail -3
# → 看到 "req_phone_verify_code" 说明在等验证码

# 发送验证码（⚠️ 必须用 \r\n 结尾！\n 不够）
printf 'input_phone_verify_code -code=123456\r\n' | socat -t10 - TCP:localhost:22222
```

#### ⚠️ 踩坑记录

| 方法 | 结果 | 原因 |
|------|------|------|
| `echo ... \| nc` | ❌ RecvFailed | `nc` 在管道模式下连接后立即关闭，来不及发数据 |
| `printf '...\n' \| socat` | ❌ 无响应 | OpenD Telnet 需要 `\r\n`，仅 `\n` 不识别 |
| `bash /dev/tcp` | ❌ 发不出去 | Docker 容器内 `/dev/tcp` 伪设备不稳定 |
| `printf '...\r\n' \| socat` | ✅ 成功 | **唯一可靠方式** |

#### 📋 常用 Telnet 命令

| 命令 | 说明 |
|------|------|
| `req_phone_verify_code` | 请求发送手机验证码 |
| `input_phone_verify_code -code=123456` | 输入验证码完成登录 |
| `help` | 查看所有可用命令 |

### 登录成功后验证

```bash
# OpenD 日志应显示 "登录成功"
docker logs opend 2>&1 | grep -E "登录成功|LoginSuccess"

# API 端口应正常监听
docker exec opend ss -tlnp | grep 11111
# 或
docker exec opend netstat -tlnp | grep 11111
```

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
