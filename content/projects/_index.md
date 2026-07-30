---
title: '项目'
date: 2026-07-30T13:45:00+08:00
draft: false
---

## 运维个人作品集（全栈可观测性平台）

> 从零搭建一套完整的运维平台，涵盖容器化网站、自动备份、监控告警、日志查询。所有服务均运行在 Docker 容器中，全部配置 `--restart=always`，虚拟机重启后自动恢复。

---

### 🎯 项目目标

- 搭建个人作品集网站（内网 + 公网双轨部署）
- 建立自动备份机制，保障数据安全
- 构建完整的可观测性体系：指标监控 + 实时告警 + 日志查询

---

### 🛠️ 技术全景

| 层级   | 技术组件                                    | 用途                               |
| :----- | :------------------------------------------ | :--------------------------------- |
| 网站   | Hugo + Nginx + GitHub Pages                 | 静态站生成 + 容器化运行 + 公网托管 |
| 容器化 | Docker                                      | 所有服务容器化，统一管理           |
| 监控   | Prometheus + Node Exporter + Nginx Exporter | 系统指标 + 服务指标采集            |
| 可视化 | Grafana                                     | 监控面板 + 日志查询                |
| 告警   | Alertmanager + SMTP（QQ邮箱）               | 5条核心告警规则，邮件通知          |
| 日志   | Loki + Promtail                             | 日志采集、存储、查询               |
| 自动化 | Shell + Crontab + PowerShell                | 自动备份 + 一键部署脚本            |

---

### ✅ 当前成果

| 服务               | 访问地址                                | 状态 |
| :----------------- | :-------------------------------------- | :--- |
| 作品集网站（内网） | `http://192.168.0.200:8080`             | ✅   |
| 作品集网站（公网） | `https://hyh25.github.io/my-portfolio/` | ✅   |
| Grafana 面板       | `http://192.168.0.200:3000`             | ✅   |
| Prometheus         | `http://192.168.0.200:9090`             | ✅   |
| Alertmanager       | `http://192.168.0.200:9093`             | ✅   |
| Loki               | `http://192.168.0.200:3100`             | ✅   |

- ✅ **监控指标**：系统资源（CPU/内存/磁盘）+ Nginx 状态，Grafana 实时展示
- ✅ **告警闭环**：宕机、高负载、磁盘不足、内存过高、Nginx 服务不可用 → 邮件通知
- ✅ **日志查询**：Grafana 内实时检索 Nginx 访问日志（`{job="nginx"}`），秒级响应
- ✅ **自动备份**：每日凌晨 2:00 打包网站文件，保留最近 7 天

---

### 📖 详细记录

搭建过程中遇到的所有问题和解决方案，记录在博客中：

- [从零搭建第一个 Nginx 网站]({{< ref "/posts/first-post" >}})
- [使用 Hugo 生成 HTML 并部署到 GitHub]({{< ref "/posts/使用hugo生成html并部署到github" >}})
- [Docker 容器化全记录]({{< ref "/posts/docker_containerization" >}})
- [Prometheus + Grafana 监控系统搭建]({{< ref "/posts/Prometheus+Grafana监控系统搭建" >}})
- [告警系统搭建（Alertmanager + 告警规则）]({{< ref "/posts/告警系统搭建Alertmanager+告警规则" >}})
- [Loki + Promtail 日志系统搭建]({{< ref "/posts/loki+promtail" >}})

---

### 🔗 相关链接

- [GitHub 源码仓库](https://github.com/hyh25/my-portfolio)
- [公网网站](https://hyh25.github.io/my-portfolio/)
