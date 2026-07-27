---
title: '搭建nginx的一些补充'
date: 2026-07-27
draft: false
tags: ['Nginx', 'Linux', '运维']
categories: ['运维实战']
---

事实上,如果我们使用NAT模式，要使能在同一局域网的手机能够进行访问，以及避免虚拟机IP的变化仍有一些东西需要调整

## 对于避免虚拟机的IP变化问题的解决方案(NAT和桥接的配置是不一样的)

1. 将网卡配置从dhcp改为static

- `vi /etc/sysconfig/network-scripts/ifcfg-ens33`
- `BOOTPROTO=static`
- `IPADDR=` 在宿主机中比如windows可以通过`ipconfig` 进行查看VMnet8下的IPV4的前三位就是网段，
- `NETMASK` 设置子网掩码一般为255.255.255.0
- `GATEWAY` 如果是NAT模式查看VMWARE的虚拟网络编辑器，桥接在宿主机中查看默认网关就行
- `DNS1` 默认选择路由器的网关IP可以配置多个，比如`DNS2=8.8.8.8`这是谷歌服务器提供DNS解析服务的地址

## 对于如何让同一局域网中的设备进行访问的问题

1. NAT模式下需要配置端口转发

- 在vmware中的虚拟网络编辑器中设置，宿主机的端口可随便设置（不被占用），但是虚拟机的端口应该是提供服务的端口
