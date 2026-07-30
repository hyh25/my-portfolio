# ========== 可配置参数 ==========
$REPO_URL = "git@github.com:hyh25/my-portfolio.git"
$BRANCH = "gh-pages"
$MAIN_BRANCH = "main"
$PUBLIC_URL = "https://hyh25.github.io/my-portfolio/"
$INTERNAL_URL = "http://192.168.0.200:8080/"
$COMMIT_MESSAGE = "🚀 自动更新网站 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  公网 + 内网 双轨部署脚本（含源码提交）" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# ========== 阶段0：提交源码到 main 分支 ==========
Write-Host "`n📦 [0/3] 提交源码变更到 main 分支..." -ForegroundColor Cyan

# 检查是否有源码变更（排除 public/ 目录）
$status = git status --porcelain -- ':!public'
if (-not $status) {
    Write-Host "ℹ️ 源码无变更，跳过 main 分支提交" -ForegroundColor Yellow
} else {
    git add .
    git commit -m $COMMIT_MESSAGE
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ 源码提交失败！" -ForegroundColor Red
        exit 1
    }
    git push origin $MAIN_BRANCH
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ 源码已推送到 main 分支" -ForegroundColor Green
    } else {
        Write-Host "❌ 源码推送失败！" -ForegroundColor Red
        exit 1
    }
}
Write-Host ""

# ========== 阶段1：构建并部署公网 ==========
Write-Host "🌐 [1/3] 构建公网版本 (GitHub Pages)..." -ForegroundColor Cyan

hugo --minify --baseURL $PUBLIC_URL
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ 公网构建失败！" -ForegroundColor Red
    exit 1
}
Write-Host "✅ 公网构建完成" -ForegroundColor Green

# 推送到 gh-pages
cd public
if (-not (Test-Path ".git")) {
    git init
    git remote add origin $REPO_URL
    git branch -M main
}

git add .
$status = git status --porcelain
if (-not $status) {
    Write-Host "ℹ️ 公网无内容变更，跳过推送" -ForegroundColor Yellow
} else {
    git commit -m $COMMIT_MESSAGE
    git push -f origin main:$BRANCH
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ 公网推送成功: $PUBLIC_URL" -ForegroundColor Green
    } else {
        Write-Host "❌ 公网推送失败！" -ForegroundColor Red
        cd ..
        exit 1
    }
}
cd ..
Write-Host ""

# ========== 阶段2：构建并部署内网 ==========
Write-Host "🏠 [2/3] 构建内网版本 (虚拟机容器)..." -ForegroundColor Cyan

hugo --minify --baseURL $INTERNAL_URL
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ 内网构建失败！" -ForegroundColor Red
    exit 1
}
Write-Host "✅ 内网构建完成" -ForegroundColor Green

# 传输到虚拟机
Write-Host "📦 正在传输文件到虚拟机..." -ForegroundColor Cyan
scp -r public/* root@192.168.0.200:/root/docker-site/public/
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ SCP 传输失败！" -ForegroundColor Red
    exit 1
}

# 更新容器内文件并重载 Nginx
ssh root@192.168.0.200 "docker cp /root/docker-site/public/. mysite:/usr/share/nginx/html/ && docker exec mysite nginx -s reload"
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ 内网部署成功: $INTERNAL_URL" -ForegroundColor Green
} else {
    Write-Host "❌ 容器更新失败！" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "🎉 全部完成！" -ForegroundColor Green
Write-Host "   源码 (main): 已推送" -ForegroundColor Yellow
Write-Host "   公网: $PUBLIC_URL" -ForegroundColor Yellow
Write-Host "   内网: $INTERNAL_URL" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Green