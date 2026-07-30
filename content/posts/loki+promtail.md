---
title: '使用Loki + Promtail搭建日志系统'
date: 2026-07-30T01:00:00+08:00
tags: ['Loki', 'Protail', 'grafana']
categories: ['Linux运维', '日志系统']
---

### 日志系统搭建（Loki + Promtail）

对 **日志系统（Loki + Promtail）的完整搭建过程** 做一份从头到尾的总结，包含所有操作命令、关键配置和踩坑记录。

---

### 一、整体架构

- **日志来源**：`mysite` 容器的标准输出（stdout）。
- **重定向层**：`docker logs -f mysite` 将容器日志实时追加到宿主机文件 `/var/log/mysite/access.log`。
- **采集层**：Promtail 以 `host` 网络模式运行，采集该普通文本文件。
- **存储查询层**：Loki 接收 Promtail 推送的日志，并提供查询 API。
- **展示层**：Grafana 通过 Loki 数据源查询日志。

**优势**：彻底绕开 Docker JSON 日志文件的时间戳解析问题，稳定可靠。

---

### 二、前置条件

- 已部署 `mysite` 容器（Nginx + Hugo 静态站），映射端口 8080/8081。
- 宿主机时区为 CST（UTC+8），且 `mysite` 容器已挂载 `/etc/localtime`。
- 确保防火墙放行端口 3100（Loki）和 9080（Promtail，可选）。

---

### 三、部署步骤

#### 1. 创建 Loki 配置和数据目录

```bash
mkdir -p /root/monitoring/loki/data
cat > /root/monitoring/loki/loki-config.yaml << 'EOF'
auth_enabled: false

server:
  http_listen_port: 3100

common:
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: inmemory
  replication_factor: 1

schema_config:
  configs:
    - from: 2024-01-01
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: /loki/index
    cache_location: /loki/index_cache
  filesystem:
    directory: /loki/chunks

limits_config:
  retention_period: 24h
  allow_structured_metadata: false
  ingestion_rate_mb: 20          # 防止速率限制
  ingestion_burst_size_mb: 40

ingester:
  wal:
    dir: /loki/wal

compactor:
  working_directory: /loki/compactor
EOF
```

**关键点**：

- 显式指定 `ingester.wal.dir` 和 `compactor.working_directory`，避免权限错误。
- 提高 `ingestion_rate_mb` 和 `burst_size`，防止大量日志被丢弃。
- 设置 `allow_structured_metadata: false`，兼容旧版本 schema。

#### 2. 启动 Loki（挂载时区）

```bash
chmod -R 777 /root/monitoring/loki/data
docker run -d \
  --name loki \
  -p 3100:3100 \
  -v /root/monitoring/loki/loki-config.yaml:/etc/loki/config.yaml \
  -v /root/monitoring/loki/data:/loki \
  -v /etc/localtime:/etc/localtime:ro \
  --restart=always \
  grafana/loki:latest \
  -config.file=/etc/loki/config.yaml
```

`chmod 777`给所有人开了绿灯，不安全，生产环境的做法
宿主机创建一个 UID 同样是 10001 的用户，然后把目录所有权交给它，这样容器进程就能合法写入，且无需开放其他用户权限。

```# 1. 创建 UID 为 10001 的用户和组（名称随意，关键是指定 UID）
groupadd -g 10001 loki-group
useradd -u 10001 -g loki-group loki-user

# 2. 创建数据目录并改变属主（递归修改）
mkdir -p /root/monitoring/loki/data
chown -R 10001:10001 /root/monitoring/loki/data

# 3. 设置权限：属主（UID 10001）有完整读写权限（7），同组用户可读（5），其他人无权限（0）
chmod 750 /root/monitoring/loki/data
```

**验证**：`docker logs loki` 应显示 `Loki started`，无错误。

#### 3. 创建日志目录并启动重定向进程

```bash
mkdir -p /var/log/mysite
# 先产生一条日志，确保文件存在
curl -s http://192.168.0.200:8080 > /dev/null
nohup docker logs -f mysite >> /var/log/mysite/access.log 2>&1 &
```

**验证**：`tail -1 /var/log/mysite/access.log` 应显示 Nginx 访问日志行。
nohup 虽然能脱离终端运行，但虚拟机重启后进程就没了。这里升级为 Systemd。

- 创建Systemd服务文件

  ```
    cat > /etc/systemd/system/nginx-log-redirect.service << 'EOF'
    [Unit]
    Description=Redirect mysite container logs to host file
    After=docker.service
    Requires=docker.service

    [Service]
    Type=simple
    ExecStart=/usr/bin/docker logs -f mysite >> /var/log/mysite/access.log 2>&1
    Restart=always
    RestartSec=10

    [Install]
    WantedBy=multi-user.target
    EOF
  ```

- 启动并设置开机自启
  ```
  systemctl daemon-reload
  systemctl enable nginx-log-redirect.service
  systemctl start nginx-log-redirect.service
  ```

#### 4. 配置 Promtail

```bash
cat > /root/monitoring/promtail/promtail-config.yaml << 'EOF'
server:
  http_listen_port: 9080
  grpc_listen_port: 0
  log_level: info

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://127.0.0.1:3100/loki/api/v1/push

scrape_configs:
  - job_name: nginx_logs
    static_configs:
      - targets: [localhost]
        labels:
          job: nginx
          __path__: /var/log/mysite/access.log
EOF
```

**说明**：

- 使用 `127.0.0.1` 因为 Promtail 将采用 `host` 网络模式。
- 无任何 JSON 解析或过滤，直接发送原始日志行。

#### 5. 启动 Promtail（使用 host 网络，挂载时区）

```bash
docker run -d \
  --name promtail \
  --network host \
  --user root \
  -v /var/log/mysite:/var/log/mysite:ro \
  -v /etc/localtime:/etc/localtime:ro \
  -v /root/monitoring/promtail/promtail-config.yaml:/etc/promtail/config.yaml \
  -v /tmp:/tmp \
  --restart=always \
  grafana/promtail:latest \
  -config.file=/etc/promtail/config.yaml
```

**验证**：

- `docker ps | grep promtail` 显示 `Up`。
- `docker logs promtail | grep -E "send|batch"` 显示发送成功日志。

#### 6. 在 Grafana 中添加 Loki 数据源

- 登录 Grafana（`http://192.168.0.200:3000`，默认 admin/admin）。
- 左侧菜单 → Configuration → Data Sources → Add data source → 选择 Loki。
- URL 填写：`http://192.168.0.200:3100`。
- 点击 Save & Test，应显示绿色对勾。

#### 7. 验证查询

- 进入 Explore，选择 Loki 数据源。
- 时间范围选 **Last 1 minute**。
- 输入 `{job="nginx"}` 或 `{}`，点击 Run query。
- 应能立即看到访问日志。

---

### 四、部署中遇到的问题及解决方案

| 序号 | 问题现象                                                | 根本原因                                                               | 解决方案                                                                          |
| ---- | ------------------------------------------------------- | ---------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| 1    | Loki 容器启动失败，报 `field shared_store not found`    | 新版 Loki 移除了 `compactor.shared_store` 字段                         | 删除配置中的 `shared_store` 行                                                    |
| 2    | Loki 报权限错误 `mkdir /loki/chunks: permission denied` | 容器内用户（UID 10001）无权写入宿主目录                                | `chmod -R 777 /root/monitoring/loki/data`；在配置中明确指定 WAL 和 compactor 目录 |
| 3    | Loki 报 `allow_structured_metadata: false` 错误         | schema v11 需要关闭结构化元数据                                        | 在 `limits_config` 中添加该参数                                                   |
| 4    | Promtail 报 `connection refused` 连接 Loki              | 容器内无法通过宿主机 IP（192.168.0.200）访问                           | 改用 `--network host` 和 `127.0.0.1`，并调整 `clients.url`                        |
| 5    | Promtail 频繁重启（`invalid drop stage config`）        | 尝试使用 `drop` 或 `match` 阶段过滤日志，语法错误                      | 完全移除过滤阶段，采用最简配置（只采集，不解析）                                  |
| 6    | Grafana 查询一直加载，无数据返回                        | Loki 速率限制（4MB/s）被大日志源压垮；容器时间不同步导致 JSON 解析失败 | 改用 `docker logs` 重定向到普通文本文件，配合 Nginx JSON 格式输出，实现稳定采集。 |
| 7    | 重定向进程在虚拟机重启后丢失                            | `nohup` 进程不持久                                                     | 将命令添加到 `/etc/rc.local` 或写成 systemd 服务                                  |
| 8    | 日志时间显示 UTC 而非北京时间                           | Loki 和 Promtail 容器未挂载 `/etc/localtime`                           | 启动容器时增加 `-v /etc/localtime:/etc/localtime:ro`，并确保 `mysite` 也挂载      |

---

### 五、当前稳定运行状态

- **Loki 容器**：正常运行，端口 3100，时区正确。
- **Promtail 容器**：正常运行，host 网络模式，采集 `/var/log/mysite/access.log`，时区正确。
- **重定向进程**：后台运行（`nohup`），实时将 `mysite` 的 stdout 追加到日志文件。
- **Grafana 查询**：`{job="nginx"}` 查询秒级响应，时间与宿主机一致。

---

### 六、维护和故障排查

- **检查重定向进程是否存活**：`ps aux | grep "docker logs -f mysite"`，若无则重新执行 `nohup ...`。
- **清除 Promtail 位置文件（强制重读全部日志）**：`docker exec promtail rm -f /tmp/positions.yaml && docker restart promtail`。
- **查看 Promtail 是否发送成功**：`docker logs promtail | grep "subbatch sent successfully"`。
- **Loki 是否接收请求**：`docker logs loki | grep "push"`。
- **查看 Grafana 查询是否超时**：检查数据源 Timeout 设置（可调大至 60s）。

---

### 系统架构和数据流向

```
┌──────────────────────────────────────────────────────────────┐
│                   宿主机 (CentOS 7)                          │
│                                                              │
│  ┌───────────────────────┐      ┌────────────────────────┐  │
│  │    Nginx 容器 (mysite)│      │   日志重定向进程        │  │
│  │  ┌──────────────────┐ │      │   (后台 nohup)         │  │
│  │  │ Nginx 访问日志    │ │      │                        │  │
│  │  │ 输出到 stdout     │ │──────│ docker logs -f mysite  │  │
│  │  └──────────────────┘ │      │   >> access.log        │  │
│  └───────────────────────┘      └───────────┬────────────┘  │
│                                               │              │
│                                               ▼              │
│                                  ┌────────────────────────┐  │
│                                  │  宿主机普通文件        │  │
│                                  │  /var/log/mysite/     │  │
│                                  │  access.log           │  │
│                                  └───────────┬────────────┘  │
│                                               │              │
│                                               ▼              │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │           Promtail 容器 (采集器)                         │ │
│  │  - 网络模式: host                                        │ │
│  │  - 挂载: /var/log/mysite (只读)                         │ │
│  │  - 读取 access.log 新行                                  │ │
│  │  - 推送 URL: http://127.0.0.1:3100/loki/api/v1/push    │ │
│  └──────────────────────────────────────────────────────────┘ │
│                               │                              │
│                               ▼                              │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │           Loki 容器 (存储/查询引擎)                      │ │
│  │  - 端口: 3100                                           │ │
│  │  - 存储: /root/monitoring/loki/data (宿主目录)          │ │
│  └──────────────────────────────────────────────────────────┘ │
│                               │                              │
│                               ▼                              │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │           Grafana 容器 (可视化)                          │ │
│  │  - 端口: 3000                                           │ │
│  │  - 数据源: Loki (http://192.168.0.200:3100)             │ │
│  │  - 查询语句: {job="nginx"}                              │ │
│  └──────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

```
【步骤1】用户访问网站
    ↓
【步骤2】mysite 容器内的 Nginx 处理请求，生成访问日志行
    ↓
【步骤3】日志写入容器的标准输出 (stdout)
    ↓
【步骤4】宿主机后台进程 (docker logs -f mysite) 捕获 stdout，追加到 /var/log/mysite/access.log
    ↓
【步骤5】Promtail (容器) 监听 /var/log/mysite/access.log 的变化，读取新行
    ↓
【步骤6】Promtail 将日志行通过 HTTP 推送到 Loki (127.0.0.1:3100)
    ↓
【步骤7】Loki 接收、索引并存储日志到宿主目录 (/root/monitoring/loki/data)
    ↓
【步骤8】运维人员在 Grafana 中发起查询请求 (http://192.168.0.200:3000)
    ↓
【步骤9】Grafana 通过 Loki 数据源 API 查询 (http://192.168.0.200:3100)
    ↓
【步骤10】Loki 检索存储的日志，返回给 Grafana 展示
```

### 深度分析：我们为什么会遇到这一系列问题？

我们遇到的所有问题都可以归为 4 大类根本原因。

1.  版本兼容性与配置语法问题（Loki 配置阶段）

    现象：shared_store 报错、allow_structured_metadata 报错。

    根本原因：Loki 从 v2.x 升级到 v3.x 后，配置结构发生了破坏性变更（Breaking Changes）。官方文档更新滞后，网上大多数教程基于旧版本。

    本质教训：部署开源软件时，必须对照你拉取的镜像版本查看官方配置文档，不能盲目复制粘贴旧教程。

2.  Linux 容器权限与挂载机制（启动失败阶段）

    现象：mkdir /loki/chunks: permission denied、mkdir wal: permission denied。

    根本原因：Loki 容器内的进程默认以 UID 10001（非 root） 运行。当你把宿主目录（如 /root/monitoring/loki/data）挂载进容器时，宿主目录的属主是 root（UID 0），容器内的 UID 10001 没有写权限。

    本质教训：容器并非虚拟机，容器内外的用户 UID 是映射关系。解决方式有二：要么 chmod 777 给所有人写权限（开发环境），要么在宿主机创建与容器 UID 相同的用户（生产环境推荐）。

3.  容器网络隔离与通信（Promtail 连接 Loki 阶段）

    现象：dial tcp 192.168.0.200:3100: connect: connection refused。

    根本原因：Promtail 容器默认使用桥接网络（bridge），它看到的 192.168.0.200 是宿主机的 IP。但在 Docker 默认桥接模式下，容器无法直接通过宿主机的 IP 访问宿主机的端口（除非开启特定路由或使用 host 网络）。

    本质教训：容器访问宿主机的服务，最稳妥的方式是 --network host 然后用 127.0.0.1。如果必须用桥接，应该用 172.17.0.1（默认网桥网关），但 host 模式最简单粗暴有效。

4.  数据格式解析与时区差异（导致“无数据”和“查询卡顿”的元凶）—— 这是最核心的坑

    现象：Promtail 明明 tail 了文件（Debug 显示 tailing new file），但就是没有 sending batch，Grafana 要么无数据，要么无限加载卡死。

    根本原因链路：

        容器默认时区是 UTC，宿主机是 CST（UTC+8）。

        容器日志写入 JSON 文件时，time 字段是 UTC 时间（如 2026-07-29T08:00:00Z）。

        Promtail 解析 JSON 时，严格按照 timestamp 阶段指定的 RFC3339Nano 格式去解析这个时间。

        因为时区不一致，或者纳秒格式稍有偏差，Loki 无法将该时间戳转换为纳秒级 Unix 时间戳，于是这条日志被标记为无效并被静默丢弃（或者导致 Loki 索引异常，查询时扫描大量无效块，造成无限加载）。

    本质教训：在容器和日志领域，时间同步是生命线。所有涉及时间戳解析的组件（Promtail, Loki, Elasticsearch），必须保证容器时区与日志产生时区一致。否则日志可以“看得到文件”，但“进不了索引”。

5.  速率限制与自循环（Grafana 卡在加载的元凶）

    现象：ingestion rate limit exceeded，Grafana 一直转圈。

    根本原因：由于第 4 点的问题，Promtail 无法推送有效日志，它自身会产生大量 error sending batch 错误日志（输出到 stdout）。Promtail 采集自己的错误日志 → 推送失败 → 产生更多错误日志 → 形成无限循环，瞬间打满 Loki 4MB/s 的默认速率限制，导致 Loki 过载，查询请求被挂起。

    本质教训：采集器必须避免采集自身的日志（需要使用 drop 规则，但你的版本配置语法严格，导致没配成功）。这也是为什么最终用 docker logs 重定向绕开了 JSON 解析这一步，从根本上拆除了这个“循环炸弹”。

---

## 针对“5 大根本原因”的通用解决预案

| 根本原因类别                                  | 生产环境标准解决方案（不再用 `chmod 777` 或 `nohup` 这种临时手段）                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| :-------------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **1. 版本兼容性问题（配置字段变更）**         | **锁定版本**：在 `docker run` 或 `docker-compose` 中明确指定镜像标签，如 `grafana/loki:3.2.0`，不要用 `latest`。<br>**配置生成**：从官网下载**对应版本**的默认配置模板，只修改必要的参数（如存储路径、端口），不保留任何不确定的字段。                                                                                                                                                                                                                                                                                                                           |
| **2. 容器权限与挂载（Permission Denied）**    | **UID 对齐法**（见上文）：<br>1. 用 `docker inspect` 或查看官方文档，确认容器进程的 UID。<br>2. 宿主机创建同名 UID 用户。<br>3. `chown -R UID:UID /host/path`。<br>4. 权限设为 `750` 或 `755`。<br>（如果你用的是 K8s，通过 `securityContext.fsGroup` 自动完成）                                                                                                                                                                                                                                                                                                 |
| **3. 容器网络隔离（Connection Refused）**     | **策略一（推荐）**：如果采集器和存储都在同一台宿主机，**统一使用 `--network host`**，所有容器共享宿主机网络栈，直接用 `127.0.0.1` 互访。<br>**策略二（集群环境）**：使用 Docker Compose 或 K8s 的**内部 DNS 服务名**（如 `http://loki:3100`），避免写死 IP。<br>**绝对避免**：在生产环境写死 `192.168.x.x` 这种宿主机 IP。                                                                                                                                                                                                                                       |
| **4. 时间戳解析与时区差异（日志“幽灵消失”）** | **第一层（根治）**：在构建 Docker 镜像时，强制设置时区环境变量 `ENV TZ=Asia/Shanghai`，并安装 `tzdata`。<br>**第二层（启动兜底）**：运行容器时挂载宿主时区 `-v /etc/localtime:/etc/localtime:ro`。<br>**第三层（Promtail 解析兜底）**：在 `pipeline_stages` 的 `timestamp` 阶段，配置 `fallback_formats` 列表，如果 `RFC3339Nano` 解析失败，尝试其他常见格式。<br>**第四层（终极躺平）**：如果对日志的**产生时间**要求不高（比如只查最近几分钟的调试日志），**完全删除 `timestamp` 阶段**，让 Loki 使用“日志到达 Loki 的时间”作为时间戳（系统会加 `_ts` 字段）。 |
| **5. 自循环与速率限制（无限加载打爆 Loki）**  | **避免自循环**：在 Promtail 配置中，**必须**通过 `drop` 规则丢弃 `container_name="promtail"` 的日志（注意你之前语法错了，正确的是 `selector: '{container_name="promtail"}'` 放在单独的 `drop` 阶段）。<br>**提高硬限制**：在 Loki 的 `limits_config` 中，将 `ingestion_rate_mb` 从默认的 4 提高到 20 或 50，并设置合理的 `ingestion_burst_size_mb`。<br>**日志分级**：将 Promtail 的 `log_level` 设为 `error` 而不是 `info`，减少自身的日志输出量。                                                                                                              |

---
