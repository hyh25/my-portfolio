---
title: '网站自动部署脚本'
date: 2026-07-28T16:50:10+08:00
draft: false
tags: ['powershell', 'github']
categories: ['网站部署']
---

脚本主要由AI生成，这里记录执行遇到的问题

```
# 个人网站一键自动更新脚本
# 自动构建Hugo网站并上传到GitHub Pages

# ==========可配置参数==========
$REPO_URL = "git@github.com:hyh25/my-portfolio.git" # GitHub仓库地址
$BRANCH = "gh-pages" # GitHub Pages分支名称
$COMMIT_MESSAGE = "🚀 自动更新网站 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" # 提交信息
$HUGO_ARGS = "--minify" # Hugo构建参数

Write-Host "🚀 正在构建 Hugo 静态文件..." -ForegroundColor Cyan

# 1.执行Hugo构建（--minfy压缩代码）
hugo $HUGO_ARGS

# 2.检查上一步是否成功（$LASTEXITCODE是上一条命令的返回值，0代表成功）
if($LASTEXITCODE -ne 0){
    Write-Host "❌ Hugo 构建失败，请检查配置！" -ForegroundColor Red
    exit 1 # 退出脚本，不再往下执行
}

Write-Host "✅ Hugo 构建成功！正在部署到gh-pages..." -ForegroundColor Green

# 3.进入public目录
cd public

# 4.初始化Git仓库（如果尚未初始化）
if(-not (Test-Path ".git")) {
    Write-Host "📦 首次运行，初始化 Git 仓库..." -ForegroundColor Yellow
    git init
    git remote add origin $REPO_URL
    git branch -M main
} else {
    # 检查远程仓库是否已设置
    $remote = git remote get-url origin 2>$null
    if(-not $remote) {
        Write-Host "📦 远程仓库未设置，正在添加远程仓库..." -ForegroundColor Yellow
        git remote add origin $REPO_URL
    }
}
# 5.添加所有文件到Git暂存区
git add .

# 6.检查是否有更改需要提交
$status = git status --porcelain
if(-not $status) {
    Write-Host "ℹ️ 没有更改需要提交，网站已是最新状态。" -ForegroundColor Yellow
    cd .. # 返回上级目录
    exit 0 # 退出脚本，不再往下执行
}

# 7.提交更改
git commit -m $COMMIT_MESSAGE
if($LASTEXITCODE -ne 0) {
    Write-Host "❌ Git 提交失败，请检查配置！" -ForegroundColor Red
    exit 1 # 退出脚本，不再往下执行
}

# 9.推送到远程仓库的gh-pages分支（强制覆盖）
git push -f origin main:$BRANCH

if($LASTEXITCODE -ne 0) {
    Write-Host "❌ Git 推送失败，请检查配置！" -ForegroundColor Red
    exit 1 # 退出脚本，不再往下执行
}

# 10.返回上级目录
cd ..

Write-Host "✅ 网站更新完成！请访问 https://hyh25.github.io/my-portfolio/ 查看最新内容。" -ForegroundColor Green
```

在执行脚本时，可能遇到脚本报 `MissingEndCurlyBrace` → 编码问题，需保存为 `UTF-8 with BOM`
