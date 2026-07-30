---
title: '使用Alertmanager+告警规则搭建告警系统'
date: 2026-07-29T18:30:00+08:00
tags: ['Prometheus', 'Alertmanager']
categories: ['Linux运维']
---

## 目标

让 Prometheus 根据规则判断异常 → 推送告警给 Alertmanager → Alertmanager 通过邮件通知。
目录结构沿用之前的规范，所有配置放在 /root/monitoring/ 下。

### 操作流程

1. 配置 Alertmanager（邮件通知）

- ```
  mkdir -p /root/monitoring/alertmanager
  vi /root/monitoring/alertmanager/alertmanager.yml
  ```
- 配置文件内容

  ```
  global:
  smtp_smarthost: 'smtp.qq.com:587'
  smtp_from: '你的QQ号@qq.com'
  smtp_auth_username: '你的QQ号@qq.com'
  smtp_auth_password: '你的QQ邮箱授权码'
  smtp_require_tls: true

  route:
    group_by: ['alertname']
    group_wait: 10s
    group_interval: 10s
    repeat_interval: 1h
    receiver: 'email-receiver'

  receivers:
    - name: 'email-receiver'
      email_configs:
        - to: '你的接收邮箱@qq.com'
  ```

2. 编写 Prometheus 告警规则

   `vi /root/monitoring/prometheus/rules.yml`

   规则内容（5条核心规则：宕机、高负载、磁盘、内存、Nginx服务）：

   ```
   groups:
   - name: basic_alerts
     interval: 30s
     rules:
       # ========== 已有规则 ==========
       - alert: InstanceDown
         expr: up == 0
         for: 1m
         labels:
           severity: critical
         annotations:
           summary: "实例 {{ $labels.instance }} 已停止响应"
           description: "{{ $labels.job }} 任务下的实例 {{ $labels.instance }} 已经宕机超过 1 分钟。"

     - alert: HighLoadAverage
       expr: node_load5 > 2
       for: 5m
       labels:
         severity: warning
       annotations:
         summary: "节点 {{ $labels.instance }} CPU 负载过高"
         description: "当前 5 分钟平均负载为 {{ $value }}，已持续超过 5 分钟。"

     # ========== 新增规则1：磁盘空间不足 ==========
     - alert: DiskSpaceLow
       expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 20
       for: 2m
       labels:
         severity: warning
       annotations:
         summary: "节点 {{ $labels.instance }} 磁盘空间不足"
         description: "根分区可用空间仅剩 {{ $value | printf \"%.2f\" }}%，请及时清理。"

     # ========== 新增规则2：内存使用率过高 ==========
     - alert: MemoryHigh
       expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 90
       for: 3m
       labels:
         severity: warning
       annotations:
         summary: "节点 {{ $labels.instance }} 内存使用率过高"
         description: "当前内存使用率为 {{ $value | printf \"%.2f\" }}%，超过 90% 阈值。"

     # ========== 新增规则3：Nginx 服务不可用 ==========
     - alert: NginxServiceDown
       expr: up{job="nginx_exporter"} == 0
       for: 1m
       labels:
         severity: critical
       annotations:
         summary: "Nginx 服务已停止"
         description: "Nginx Exporter 采集失败，请检查 mysite 容器是否运行正常。"

   ```

3. 修改 Prometheus 主配置

   编辑 /root/monitoring/prometheus/prometheus.yml，添加

   ```
   alerting:
     alertmanagers:
       - static_configs:
           - targets:
               - '192.168.0.200:9093'

   rule_files:
     - "rules.yml"
   ```

### 遇到的一些问题

- 问题：Prometheus 容器启动时，告警页面看不到规则。
- 原因：之前只挂载了 prometheus.yml 单个文件，rules.yml 没有被挂载进容器。
- 解决：删除并重建 Prometheus 容器，挂载整个配置目录而不是单文件：
  ```bash
  docker stop prometheus && docker rm prometheus
  docker run -d --name prometheus -p 9090:9090 -v /root/monitoring/prometheus:/etc/prometheus --restart=always prom/prometheus
  ```
- 验证：访问 http://192.168.0.200:9090/alerts 能看到5条规则（绿色 Inactive 状态）。
- 测试：docker stop node_exporter 触发宕机告警，邮箱收到邮件，恢复后收到恢复邮件。
