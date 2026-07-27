---
title: '从零搭建第一个 Nginx 网站'
date: 2026-07-26
draft: false
tags: ['Nginx', 'Linux', '运维']
categories: ['运维实战']
---

## 为什么写这篇博客

这是我学习运维的第一个里程碑。从零开始，在虚拟机中安装 CentOS 7，配置网络，部署 Nginx，最终用手机访问到了自己的网站。整个过程遇到了不少问题，这是我为什么要写这篇博客的原因，记录和回顾。

## 环境准备

- **宿主机**: windows 11
- **虚拟机软件**: VMware Workstation
- **操作系统**: Centos7 Minimal
- **目标**: 在虚拟机中部署Nginx,主机和手机均可以访问

## 第一步: 安装Centos7 Minimal

由于Centos7官方已经停止维护了，该镜像是从华为的镜像库下载的

## 第二步: 配置网络环境

1. 修改虚拟机的网络接口配置
   - `ip addr` 查看ip
   - 修改`/etc/sysconfig/network-scripts/ifcfg-ens33`，首先要备份(要root权限)
   - 将`ONBOOT=no`改为`ONBOOT=yes`
   - 重启网络服务`systemctl restart network`
   - 看到inet后面的IP就配置成功了

## 第三步配置Nginx

1. 因为Centos7官方已经停止维护了，所以我们需要先配置软件源配置文件

- `mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.bak` 备份
- `curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo` 从阿里云下载到本地
- `yum clean all` 清除yum缓存
- `yum makecache` 重建缓存
- `yum install -y epel-release` 安装第三方软件库
- `yum install -y nginx` 安装nginx
- `systemctl start nginx` 启动服务
- `systemctl enable nginx` 设置开机自启
- `systemctl status nginx`
- `firewall-cmd --list-all` 查看防火墙配置
- `firewall-cmd --permanent --add-service=http` 永久放行http服务
- `firewall-cmd --reload` 重新加载配置

这里已经配置完成了，下面更改nginx默认index.html，或者新建html文件，这里我进行新建，这里出现了一个新问题，如果直接打有点花时间，所以我选择配置xshell，在xshell里操作会更方便，也比较符合真实的工作环境

## 配置xshell

- `firewall-cmd --list-all` 检查是否放行了ssh服务
- 打开xshell进行配置，对于无密码或者root账户远程登录需要配置
- `vi /etc/ssh/sshd_congfig` 进行配置
- `PermitEmptyPasswords` 如果是无密码用户，设置为yes
- `PermitRootLogin` 如果希望允许root用户远程登录，将他设置为yes(不推荐)

后续直接在xshell中进行操作

- `vi /usr/share/nginx/html/time.html` 直接让AI生成一个简单的网页复制代码进行测试就行了
