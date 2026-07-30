---
title: '使用Prometheus+Grafana搭建监控系统'
date: 2026-07-29T12:37:00+08:00
tags: ['Prometheus', 'Grafana', 'Docker', 'Linux']
categories: ['Linux运维']
---

## 整体目标

在虚拟机上搭建一套完整的监控系统，用于采集：

- 系统资源指标(cpu、内存、磁盘、网络)
- nginx服务指标(连接数、请求数、状态)
  并通过Grafana提供可视化面板

## 系统架构和数据流向

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         虚拟机 192.168.0.200                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────────┐│
│  │   Node Exporter │    │  Nginx Exporter  │    │    Nginx (容器/宿主机)  ││
│  │   (系统指标)    │    │  (服务指标)      │    │    (暴露 stub_status)   ││
│  │   :9100         │    │  :9113           │    │    :8081/nginx_status   ││
│  └────────┬────────┘    └────────┬─────────┘    └────────────┬────────────┘│
│           │                      │                           │             │
│           │    ┌─────────────────┴─────────────────┐        │             │
│           │    │                                   │        │             │
│           │    ▼                                   │        │             │
│           │  ┌─────────────────────────────────┐   │        │             │
│           └──│      Prometheus (采集中心)      │◄──┘        │             │
│              │      :9090                      │            │             │
│              │   ┌─────────────────────────┐   │            │             │
│              │   │ 1. 定期拉取 /metrics    │   │            │             │
│              │   │ 2. 存储到 TSDB (时序库) │   │            │             │
│              │   │ 3. 提供 PromQL 查询     │   │            │             │
│              │   └─────────────────────────┘   │            │             │
│              └────────────────┬────────────────┘            │             │
│                               │                             │             │
│                               ▼                             │             │
│              ┌─────────────────────────────────────────┐    │             │
│              │           Grafana (可视化)              │    │             │
│              │           :3000                        │    │             │
│              │  ┌───────────────────────────────────┐ │    │             │
│              │  │ 通过 PromQL 查询 Prometheus       │ │    │             │
│              │  │ 展示为图表 / 面板                  │ │    │             │
│              │  └───────────────────────────────────┘ │    │             │
│              └─────────────────────────────────────────┘    │             │
│                               │                             │             │
│                               ▼                             │             │
│                        浏览器访问 :3000                     │             │
└─────────────────────────────────────────────────────────────────────────────┘

数据流向：
1. Nginx 通过 stub_status 暴露状态数据（:8081/nginx_status）
2. Nginx Exporter 从 stub_status 读取数据，转换为 Prometheus 格式（/metrics）
3. Prometheus 定期拉取 Nginx Exporter 和 Node Exporter 的 /metrics
4. Prometheus 存储数据到本地时序数据库
5. Grafana 通过 PromQL 查询 Prometheus 获取数据
6. Grafana 渲染图表，用户通过浏览器查看
```

```
容器内 Nginx (8081/nginx_status)
        │
        ▼
Nginx Exporter (容器) → 读取 /nginx_status → 转换成 /metrics
        │
        ▼
Prometheus (容器) → 定期拉取 Nginx Exporter 和 Node Exporter 的 /metrics
        │
        ▼
Grafana (容器) → 通过 PromQL 查询 Prometheus → 渲染图表
```

容器依赖关系

```
┌───────────────────┐
│   mysite          │  ← 基础依赖：提供 nginx 服务 + stub_status
│   (Nginx + 网站)  │
└────────┬──────────┘
         │ 提供 :8081/nginx_status
         ▼
┌───────────────────┐
│ nginx_exporter    │  ← 依赖 mysite 的 stub_status 端点
│ (Nginx 指标采集)  │
└────────┬──────────┘
         │ 暴露自身 /metrics
         ▼
┌───────────────────┐
│   prometheus      │  ← 依赖 nginx_exporter 和 node_exporter 的 /metrics
│   (监控数据采集)  │
└────────┬──────────┘
         │ 提供 PromQL 查询
         ▼
┌───────────────────┐
│    grafana        │  ← 依赖 prometheus 数据源
│   (可视化面板)    │
└───────────────────┘

node_exporter 独立，无依赖。
```

### 一、部署prometheus

1. 配置文件：`/root/monitoring/prometheus/prometheus.yml`

   ```
   global:
     scrape_interval: 15s
     evaluation_interval: 15s

   scrape_configs:
     - job_name: 'prometheus'
       static_configs:
         - targets: ['localhost:9090']

     - job_name: 'node_exporter'
       static_configs:
         - targets: ['192.168.0.200:9100']

     - job_name: 'nginx_exporter'
       static_configs:
         - targets: ['192.168.0.200:9113']`
   ```

2. 启动容器
   ```
   mkdir -p /root/monitoring/prometheus
   vi /root/monitoring/prometheus/prometheus.yml
   docker run -d --name prometheus -p 9090:9090 -v /root/monitoring/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml --restart=always prom/prometheus
   ```

### 二、部署 Node Exporter（系统指标）

    ```
    docker run -d --name node_exporter -p 9100:9100 --restart=always prom/node-exporter
    ```

### 三、部署Nginx并开启stub_status(nginx自带的轻量仪表盘)

1. 关闭宿主机的Nginx，之后都放在容器内运行
   - `systemctl stop nginx`
   - `systemctl diable nginx`
2. 构建镜像并运行容器

   ```
   cd /root/docker-site
   docker build -t my-portfolio-unprivileged .
   docker run -d \
     -p 8080:8080 \
     -p 8081:8081 \
     --name mysite \
     --security-opt seccomp=unconfined \
     my-portfolio-unprivileged
   ```

3. 主要是容器内的配置
   1. 进入容器，查看当前配置
      - `docker exec -it mysite /bin/sh`
      - `cat /etc/nginx/conf.d/default.conf`<br>
        默认只有8080端口的网站服务没有stub_status
   2. 将包含 stub_status 的配置复制到容器内,因为容器内文件系统只读（或权限受限），我们用 docker cp 覆盖配置文件。在宿主机上创建配置文件 `/root/docker-site/nginx-custom.conf`

      ```
      server {
          listen 8080;
          server_name localhost;
          root /usr/share/nginx/html;
          index index.html;

          location / {
              try_files $uri $uri/ =404;
          }
      }

      server {
          listen 8081;
          server_name localhost;

          location /nginx_status {
              stub_status;
              allow 127.0.0.1;
              allow 192.168.0.0/24;
              deny all;
          }
      }
      ```

   3. 复制到容器内
      `docker cp /root/docker-site/nginx-custom.conf mysite:/etc/nginx/conf.d/default.conf`

   4. 重新加载容器内Nginx配置
      `docker exec mysite nginx -s reload`

   5. 验证容器内stub_status是否生效
      `curl http://192.168.0.200:8081/nginx_status`

   6. Dockerfile固化配置
      为了防止每次手动 docker cp，我们已经在 Dockerfile 中固化了这个配置,(修改了Dockerfile记得重新构建镜像)
      ```
      FROM nginxinc/nginx-unprivileged:alpine
      COPY public /usr/share/nginx/html
      COPY nginx-custom.conf /etc/nginx/conf.d/default.conf
      EXPOSE 8080 8081
      ```

### 四、部署Nginx Exporter(服务指标)

```
docker run -d --name nginx_exporter -p 9113:9113 --restart=always nginx/nginx-prometheus-exporter -nginx.scrape-uri=http://172.17.0.1:8081/nginx_status`
```

Nginx Exporter 启动命令中使用了 172.17.0.1：这个 IP 在 Docker 桥接网络中可能因环境不同而变化。建议补充说明：如果使用 --network host 模式，可以改为 127.0.0.1。

### 五、Grafana(可视化)

```
docker run -d --name grafana -p 3000:3000 --restart=always grafana/grafana
```

1. 访问：http://192.168.0.200:3000

   默认账号 admin / admin

   添加数据源：Prometheus → http://192.168.0.200:9090

   导入面板：Node Exporter → 1860，Nginx Exporter → 12708

2. 在此过程中遇到了一些问题(nginx exporter没有数据)，最终发现是时间同步问题，以下是解决方案
   ```
   yum install -y chrony
   systemctl start chronyd
   systemctl enable chronyd
   chronyc -a makestep
   date
   docker restart prometheus
   ```

### 当前的容器列表

`docker ps`
|容器名称|端口映射|作用|
|---|---|---|
|mysite|8080:8080, 8081:8081|Hugo 网站 + Nginx stub_status|
|prometheus|9090:9090|监控数据采集与存储|
|node_exporter|9100:9100|系统指标采集|
|nginx_exporter|9113:9113|Nginx 指标采集|
|grafana|3000:3000|可视化面板|
