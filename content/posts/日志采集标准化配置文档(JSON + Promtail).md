---
title: '日志采集标准化配置文档JSON + Promtail'
date: 2026-07-30T16:40:00+08:00
tags: ['json', 'promtail', '日志采集']
categories: ['日志采集']
---

### 📌 背景与问题

在部署 Loki + Promtail 日志系统初期，我们遇到两类典型问题：

- **时间解析失败导致丢数据**：Nginx 默认日志格式（`[30/Jul/2026:15:31:11 +0800]`）与 Promtail 默认的 `RFC3339Nano` 格式不匹配。
- **时间显示不准确**：放弃解析后，Loki 使用 UTC 接收时间，与日志实际产生时间相差 8 小时。

**根本原因**：采集器（Promtail）试图从**非结构化文本**中“猜测”时间格式，只要格式稍有偏差，解析就会失败。

**解决方案**：在日志源（Nginx）侧输出**结构化 JSON 日志**，包含标准格式的时间戳（ISO8601），让 Promtail 用稳定的 `json` 阶段提取字段，彻底告别正则表达式。

### 🎯 目标

1. Nginx 输出 JSON 格式访问日志，包含标准 `time_local` 字段（ISO8601 带时区）。
2. Promtail 使用 `json` 阶段直接提取字段，不再依赖 `regex`。
3. `timestamp` 阶段使用 `RFC3339` 格式稳定解析时间。
4. Grafana 显示日志实际产生时间（北京时区），与宿主机时间一致。

### 🔄 配置流程

#### 第一步：修改 Nginx 日志格式为 JSON

**文件**：`/root/docker-site/nginx-custom.conf`

```nginx
# 定义 JSON 日志格式（必须放在 server 块外面）
log_format json_escape escape=json
'{'
    '"time_local":"$time_iso8601",'
    '"remote_addr":"$remote_addr",'
    '"remote_user":"$remote_user",'
    '"request":"$request",'
    '"status":"$status",'
    '"body_bytes_sent":"$body_bytes_sent",'
    '"request_time":"$request_time",'
    '"http_referrer":"$http_referer",'
    '"http_user_agent":"$http_user_agent",'
    '"http_x_forwarded_for":"$http_x_forwarded_for"'
'}';

server {
    listen 8080;
    server_name localhost;
    root /usr/share/nginx/html;
    index index.html;

    # 关键：应用 JSON 格式到访问日志
    access_log /dev/stdout json_escape;
    error_log /dev/stderr;

    location / {
        try_files $uri $uri/ =404;
    }
}

server {
    listen 8081;
    server_name localhost;

    # stub_status 保持默认日志格式即可
    access_log /dev/stdout;
    error_log /dev/stderr;

    location /nginx_status {
        stub_status;
        allow 127.0.0.1;
        allow 192.168.0.0/24;
        deny all;
    }
}
```

**应用到容器并重载**：

```bash
docker cp /root/docker-site/nginx-custom.conf mysite:/etc/nginx/conf.d/default.conf
docker exec mysite nginx -t
docker exec mysite nginx -s reload
```

**验证**：

```bash
curl -s http://192.168.0.200:8080 > /dev/null
tail -1 /var/log/mysite/access.log
```

期望输出为 JSON 格式，包含 `"time_local":"2026-07-30T15:45:11+08:00"`。

#### 第二步：修改 Promtail 配置（使用 json 解析）

**文件**：`/root/monitoring/promtail/promtail-config.yaml`

```yaml
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
    pipeline_stages:
      # 解析 JSON 日志
      - json:
          expressions:
            time_local: time_local
            remote_addr: remote_addr
            request: request
            status: status
            http_user_agent: http_user_agent
      # 用标准 RFC3339 格式解析时间戳
      - timestamp:
          source: time_local
          format: RFC3339
      # 把状态码作为标签（方便按状态过滤）
      - labels:
          status: status
      # 输出完整日志内容
      - output:
          source: log
```

**重启 Promtail**：

```bash
docker restart promtail
```

#### 第三步：验证

1. 产生新日志：`curl -s http://192.168.0.200:8080 > /dev/null`
2. 检查 Promtail 日志，确认无报错：`docker logs promtail --tail 10`
3. 在 Grafana Explore 中查询 `{job="nginx"}`
4. 确认时间显示为北京时间（如 `15:45:11+08:00`），而非 UTC

### 🔧 备选方案（无法修改应用代码时）

如果无法修改 Nginx 配置（比如应用是第三方中间件），可以用 Promtail 的 `regex` 阶段从文本中提取时间：

```yaml
- regex:
    expression: '\[(?P<time_local>[^\]]+)\]'
    source: log
- timestamp:
    source: time_local
    format: '02/Jan/2006:15:04:05 -0700'
```

此方案不稳定，**仅在无法修改应用日志格式时作为兜底**。

### 📊 配置前后对比

| 维度         | 配置前（文本格式）                                          | 配置后（JSON 格式）                                               |
| :----------- | :---------------------------------------------------------- | :---------------------------------------------------------------- |
| 日志样例     | `192.168.0.200 - - [30/Jul/2026:15:31:11 +0800] "GET /..."` | `{"time_local":"2026-07-30T15:31:11+08:00","request":"GET /..."}` |
| 时间解析方式 | 需要 `regex` + 复杂格式字符串                               | `json` + `RFC3339`                                                |
| 解析失败风险 | 高（格式稍有偏差就丢数据）                                  | 极低（结构化数据稳定）                                            |
| 新增字段     | 需要修改正则表达式                                          | 在 `expressions` 中直接添加键名                                   |
| 维护成本     | 高                                                          | 低                                                                |

---

### 📎 相关文件路径

| 文件             | 路径                                             |
| :--------------- | :----------------------------------------------- |
| Nginx 自定义配置 | `/root/docker-site/nginx-custom.conf`            |
| Promtail 配置    | `/root/monitoring/promtail/promtail-config.yaml` |
| 日志缓存文件     | `/var/log/mysite/access.log`                     |
| Nginx 配置备份   | `/root/docker-site/nginx-custom.conf.bak`        |

### ✅ 完成标准

- Nginx 日志文件中的每一条记录都是合法 JSON。
- `time_local` 字段使用 ISO8601 格式，包含时区偏移。
- Promtail 能够稳定解析 `time_local` 字段，无报错。
- Grafana 中日志时间与宿主机时间一致。

我已在文档中补充了引号说明，确保不会遗漏这个你亲自追问过的细节。

---

## 📝 关于配置格式的说明（补充）

在 `log_format` 配置中，你看到的这种写法：

```nginx
log_format json_escape escape=json
'{'
    '"time_local":"$time_iso8601",'
    '"remote_addr":"$remote_addr",'
    '"remote_user":"$remote_user"'
'}';
```

**不是引号嵌套，而是 Nginx 的字符串拼接语法：**

| 符号               | 作用                                                           |
| :----------------- | :------------------------------------------------------------- |
| 外层单引号 `'...'` | Nginx 的字符串边界，表示“这是一个普通文本片段”                 |
| 内层双引号 `"..."` | JSON 语法，标记键名和字符串值                                  |
| 多个单引号片段相邻 | Nginx 自动把它们按顺序拼接成一个完整字符串                     |
| `'{'` 中的单引号   | **必须存在**，否则 Nginx 会把裸 `{` 误认为配置块开始符号而报错 |

**拼接过程示意**（忽略单引号，只看内容）：

```text
{ + "time_local":"$time_iso8601", + "remote_addr":"$remote_addr", + ... + }
= {"time_local":"$time_iso8601","remote_addr":"$remote_addr",...}
```

这种写法的唯一目的是**提升可读性**（方便增删字段），你也可以把所有内容写在一行，效果完全相同。
