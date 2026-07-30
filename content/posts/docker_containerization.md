---
title: 'Docker容器化'
date: 2026-07-28T17:00:10+08:00
draft: false
tags: ['docker']
categories: ['linux运维']
---

好的，下面用**列表形式**重新输出完整的 Docker 部署阶段总结。

---

## 🐳 Docker 部署阶段完整总结（列表版）

**时间跨度**：约 2-3 天（2026 年 7 月 28 日前后）

**最终成果**：网站成功运行在 Docker 容器中，访问地址 `http://192.168.0.200:8080`

### 一、环境准备（安装 Docker）

**准确操作流程**（从阿里云源安装）：

1. 检查系统源是否已配置阿里云
   - 执行 `yum repolist` 确认阿里云源可用
   - 因为之前已经配过阿里云源，无需额外添加

2. 安装 Docker（直接从阿里云源拉取）
   - 执行 `yum install -y docker-ce docker-ce-cli containerd.io`
   - 没有执行 `yum-config-manager --add-repo`，因为阿里云源已有 Docker 包

3. 启动 Docker 服务
   - 执行 `systemctl start docker`
   - 执行 `systemctl enable docker`（设置开机自启）

4. 验证安装
   - 执行 `docker --version`，确认能看到版本号

5. 给普通用户添加 Docker 权限（可选）
   - 执行 `usermod -aG docker $USER` 这里注意登录的用户是否是普通用户如果不是，记得登出root用户或者使用`usermod -aG docker learner` `
   - 重新登录 SSH 或执行 `newgrp docker` 使权限生效

### 二、镜像加速器配置

**解决的问题**：构建时卡在 `load metadata for docker.io/...`，拉取镜像极慢或超时。

**操作步骤**：

1. 创建/修改 Docker 配置文件
   - 执行 `vi /etc/docker/daemon.json`
   - 写入镜像加速器地址

2. 配置文件内容
   - `{"registry-mirrors": ["https://docker.1ms.run", "https://docker.m.daocloud.io"]}`
   - 注意：移除了失效的 `docker.xuanyuan.me` 源

3. 重启 Docker 使配置生效
   - 执行 `systemctl daemon-reload`
   - 执行 `systemctl restart docker`

4. 验证加速器是否加载成功
   - 执行 `docker info | grep -A 5 "Registry Mirrors"`
   - 应能看到配置的加速器地址

**踩坑记录**：

- `docker.xuanyuan.me` 源失效 → 移除，换成 `1ms.run` 和 `daocloud.io`
- `daemon.json` 格式错误（多余逗号）→ 确保 JSON 格式正确

**应急方案**：如果加速器配置后仍然拉取缓慢，可以先执行 `docker pull nginxinc/nginx-unprivileged:alpine` 手动拉取到本地缓存，构建时直接使用缓存，跳过网络拉取。

```
以上的操作步骤还是比较麻烦的，之后我选择了毫秒镜像，在官方网站有一键配置的手册，比较简单
```

### 三、构建 Docker 镜像

**工作目录**：`/root/docker-site/`（虚拟机内）

**操作步骤**：

1. 创建工作目录
   - 执行 `mkdir -p /root/docker-site`
   - 执行 `cd /root/docker-site`

2. 从 Windows 传输静态文件到虚拟机
   - 在 Windows PowerShell 中执行：
     - `scp -r D:\program_manager_tools\new_project\item_set\my-portfolio\public root@192.168.0.200:/root/docker-site/`
   - 输入 root 密码，等待传输完成,注意是root用户登录，只有它才有写入/root目录的权限

3. 编写 Dockerfile
   - 执行 `vi Dockerfile`
   - 定义镜像构建规则

4. 构建镜像
   - 执行 `docker build -t my-portfolio-unprivileged .`
   - 等待构建完成

5. 查看镜像列表确认构建成功
   - 执行 `docker images`，应能看到 `my-portfolio-unprivileged`

**Dockerfile 版本演进过程**：

**v1（第一版）**：

- 使用 `FROM nginx:alpine` 作为基础镜像
- 执行 `COPY public /usr/share/nginx/html`
- 执行 `EXPOSE 80`
- 问题：容器启动后立即退出，`pwrite() "/run/nginx.pid"` 权限报错

**v2（第二版）**：

- 尝试在 Dockerfile 中添加 `RUN sed -i 's|pid /run/nginx.pid;|pid /tmp/nginx.pid;|' /etc/nginx/nginx.conf`
- 问题：`sed` 命令可能未正确执行，同样报 `pwrite` 错误

**v3（第三版）**：

- 换用 `nginxinc/nginx-unprivileged:alpine` 基础镜像
- 将 `EXPOSE 80` 改为 `EXPOSE 8080`，因为nginx-unprivileged 镜像为了安全，刻意不使用 root 用户，因此内部默认监听的是 8080 端口，而不是 80
- 问题：仍然报 `pwrite` 错误，但错误出现在 `/tmp/nginx.pid` 而非 `/run/nginx.pid`

**v4（最终版）**：

- 继续使用 `nginxinc/nginx-unprivileged:alpine`
- 保持 `EXPOSE 8080`
- 配合运行时参数 `--security-opt seccomp=unconfined` 成功运行

**最终 Dockerfile 内容**：

```
FROM nginxinc/nginx-unprivileged:alpine
COPY public /usr/share/nginx/html
EXPOSE 8080
```

### 四、运行容器（权限问题排查与解决）

**核心问题**：容器启动后立即退出，`docker logs` 显示：
`[crit] 1#1: pwrite() "/run/nginx.pid" failed (1: Operation not permitted)`

**尝试过的方案**：

1. 修改 PID 路径到 `/tmp`
   - 在 Dockerfile 中通过 `sed` 替换 `nginx.conf` 中的 PID 路径
   - 结果：失败，报错仍然存在

2. 使用 `--privileged` 运行
   - 执行 `docker run -d -p 8080:8080 --name mysite --privileged my-portfolio-unprivileged`
   - 结果：成功运行，但权限过大，生产环境不推荐

3. 使用 `seccomp=unconfined` 运行
   - 执行 `docker run -d -p 8080:8080 --name mysite --security-opt seccomp=unconfined my-portfolio-unprivileged`
   - 结果：成功运行，比 `--privileged` 安全

4. 自定义 seccomp 配置文件
   - 创建 `/tmp/custom-seccomp.json`，只放行 `pwrite` 系统调用
   - 执行 `docker run -d -p 8080:8080 --name mysite --security-opt seccomp=/tmp/custom-seccomp.json my-portfolio-unprivileged`
   - 结果：失败，报 `cannot start a stopped process: unknown`，配置文件缺少基本系统调用

5. 改用 `nginx-unprivileged` 镜像
   - 在 Dockerfile 中使用 `FROM nginxinc/nginx-unprivileged:alpine`
   - 结合 `seccomp=unconfined` 运行
   - 结果：成功运行

**最终运行命令**：
`docker run -d -p 8080:8080 --name mysite --security-opt seccomp=unconfined my-portfolio-unprivileged`

### 五、样式问题修复

**问题现象**：容器中访问网站样式丢失（CSS 无法加载），页面只有文字没有样式。

**根本原因**：`hugo.yaml` 中 `baseURL` 设置为 `'/'`，导致生成的资源路径为 `/assets/...`，容器内无法正确匹配。

**解决方案（最终采用）**：

1. 修改 `hugo.yaml`
   - 将 `baseURL` 改为 `'http://192.168.0.200:8080/'`
   - 保存文件

2. 重新生成静态文件
   - 在 Windows 项目根目录执行 `hugo --minify`
   - 生成新的 `public` 目录

3. 传输新文件到虚拟机
   - 执行 `scp -r public root@192.168.0.200:/root/docker-site/`

4. 重新构建镜像
   - 执行 `docker build -t my-portfolio-unprivileged .`

5. 重新运行容器
   - 执行 `docker rm mysite`
   - 执行 `docker run -d -p 8080:8080 --name mysite --security-opt seccomp=unconfined my-portfolio-unprivileged`

**备选方案（未采用）**：在 Nginx 配置中添加路径重写（`location /my-portfolio/` 映射到根目录），以保留 `baseURL: '/'` 的配置，但需要额外配置 `default.conf`。

### 六、常用 Docker 管理命令

1. 查看正在运行的容器：`docker ps`

2. 查看所有容器（包括已停止的）：`docker ps -a`

3. 查看容器日志：`docker logs mysite`

4. 停止容器：`docker stop mysite`

5. 删除容器：`docker rm mysite`

6. 删除镜像：`docker rmi my-portfolio-unprivileged`

7. 进入容器内部调试：`docker exec -it mysite /bin/sh`

8. 查看镜像列表：`docker images`

9. 清理构建缓存：`docker builder prune -f`

### 七、问题与解决方案汇总

**问题 1：镜像拉取卡住**

- 现象：构建时长时间停在 `load metadata`
- 根因：镜像加速器失效或网络慢
- 解决方案：配置 `daemon.json`，更换稳定加速器

**问题 2：容器启动失败**

- 现象：`pwrite() "/run/nginx.pid" failed (1: Operation not permitted)`
- 根因：seccomp 阻止 `pwrite` 系统调用
- 解决方案：使用 `seccomp=unconfined` 运行

**问题 3：改用非 root 镜像后仍然失败**

- 现象：即使 PID 路径改为 `/tmp/nginx.pid`，同样报 `pwrite` 错误
- 根因：seccomp 阻止 `pwrite` 系统调用本身
- 解决方案：同上，使用 `seccomp=unconfined`

**问题 4：自定义 seccomp 配置失败**

- 现象：`cannot start a stopped process: unknown`
- 根因：配置文件只放了 `pwrite`，缺少容器启动所需的基本系统调用
- 解决方案：暂用 `unconfined`，后续用 `strace` 生成完整列表

**问题 5：网站样式丢失**

- 现象：页面无 CSS 样式
- 根因：`baseURL` 路径不匹配容器环境
- 解决方案：改为完整 URL（`http://192.168.0.200:8080/`）

**问题 6：Dockerfile 语法错误**

- 现象：`unknown instruction: OM`
- 根因：第一行写错，`OM` 应为 `FROM`
- 解决方案：修正为 `FROM nginx:alpine`

**问题 7：构建中断后卡住**

- 现象：取消构建后重新执行仍然缓慢
- 根因：残留的构建缓存
- 解决方案：执行 `docker builder prune -f` 清理
