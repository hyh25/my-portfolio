---
title: '使用hugo生成html并部署到github'
date: 2026-07-28
draft: false
tags: ['Nginx', 'Linux', '运维', 'hugo', 'github', 'ssh']
categories: ['运维实战']
---

## 第一步安装Hugo并创建站点

1. 直接上网搜索下载或者命令行下载，这里我选择直接上github下载最新的适用于windows的x64位架构的预编译的二进制文件的压缩包，移动到目标目录解压就行了
2. 配置环境变量，使其在任何路径都可以执行
3. `hugo new site my-portfolio` 创建目录结构
4. `cd my-portfolio` 进入目录
5. `git init` 初始化git进行版本管理
6. `git submodule add https://github.com/adityatelange/hugo-PaperMod.git themes/PaperMod` 将PaperMod主题克隆到themes目录，并将其作为git子模块加入项目，这里解释下git子模块，在初次引用，将代码拉下来并记录版本（实际是40位的提交哈希值），当我们上传到github时，并不会上传themes中的代码，只是将之前记录的版本上传，别人进行clone时，也不会有代码，他们需要手动更新子模块
7. 编辑站点配置文件我们使用yaml格式`yaml`,这里有几个问题
   - `baseURL`的值必需以协议开头，并以斜杠结尾，必须精确匹配，否则资源404
   - `SRI` 子资源完整性检查在CDN的环境可能引发样式失效，所以我设置了`disableFingerprinting: true`
   - `relativeURLs=false` 相对路径需要关闭，避免可能的样式失效问题
8. 在content目录下编辑.md文件
9. `hugo --minify` 生成静态文件，产物在public目录内

## 第二步配置github

采用ssh协议推送

1. 配置ssh
   - `ssh-keygen -t ed25519 -C "邮箱" 生成密钥`
   - 添加公钥到github,将`C:\Users\用户名\.ssh\id_ed25519.pub`中的密钥内容复制到github中的settings--->ssh keys

## 第三步部署到`gh-pages`分支

为什么不是main，main分支一般用来存储源代码

1. `cd public` 进入public文件夹
2. `git init` 初始化git仓库
3. `git remote add origin git@github.com:hyh25/my-portfolio.git` 添加远程服务器的url
4. `git branch -M main` 将默认的master的分支名改为main
5. `git add .` 将当前目录的所有文件加入暂存区
6. `git commit -m "xxxxxxxxxx"` 提交，并附上记录信息
7. `git push -f origin main:gh-pages` 将本机的main分支强制上传到origin的gh-pages
8. 在github中code中的setting中page,选择分支部署并选择gh-pages后保存
9. 可以在actions观察是否部署成功，成功就可以通过域名进行访问就行了

### [hugo官方文档地址]("https://hugo.opendocs.io/")
