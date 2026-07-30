## 📦 网站更新完整流程（公网 + 内网双轨部署）

作品集网站部署在**两个环境**，每次更新需要同步：

| 部署位置 | 访问地址                                | 部署方式                              |
| :------- | :-------------------------------------- | :------------------------------------ |
| 公网     | `https://hyh25.github.io/my-portfolio/` | Git 推送 `public/` 到 `gh-pages` 分支 |
| 内网     | `http://192.168.0.200:8080`             | SCP 传输 + Docker 容器更新            |

### 🎯 核心设计：一个配置，两个环境

**问题**：公网和内网的 `baseURL` 不同（`https://hyh25.github.io/my-portfolio/` vs `http://192.168.0.200:8080/`），静态资源路径会不一致。

**解决方案**：`hugo.yaml` 中固定为公网地址，部署脚本通过 `hugo --baseURL` 参数动态覆盖，无需手动修改配置文件。

```yaml
# hugo.yaml 固定配置（只需维护这一个）
baseURL: 'https://hyh25.github.io/my-portfolio/'
```

脚本构建时自动区分：

- **公网构建**：`hugo --minify --baseURL https://hyh25.github.io/my-portfolio/`
- **内网构建**：`hugo --minify --baseURL http://192.168.0.200:8080/`

### 🚀 一键自动化脚本（推荐）

在本地项目根目录创建 `update-site.ps1`，一条命令完成所有操作：

```powershell
# ============================================================
# 名称: update-site.ps1
# 功能: 源码提交 + 公网部署 + 内网部署（三阶段全自动）
# ============================================================

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

Write-Host "📦 正在传输文件到虚拟机..." -ForegroundColor Cyan
scp -r public/* root@192.168.0.200:/root/docker-site/public/
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ SCP 传输失败！" -ForegroundColor Red
    exit 1
}

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
```

**使用方式**：每次修改内容后，在项目根目录执行：

```powershell
.\update-site.ps1
```

脚本会自动完成：**源码提交 → 公网构建推送 → 内网构建部署**。

### 📋 手动更新流程（备用）

当脚本不可用或需要精细控制时，按以下步骤操作：

#### 第一阶段：提交源码到 main（如果源码有变更）

```powershell
git add .
git commit -m "更新内容：<简要说明>"
git push origin main
```

#### 第二阶段：部署到公网（GitHub Pages）

```powershell
hugo --minify
cd public
git add .
git commit -m "更新网站内容：<简要说明>"
git push -f origin main:gh-pages
cd ..
```

#### 第三阶段：部署到内网（虚拟机容器）

```powershell
# 重新构建内网版本（注意 baseURL 覆盖）
hugo --minify --baseURL "http://192.168.0.200:8080/"

# 传输静态文件
scp -r public/* root@192.168.0.200:/root/docker-site/public/

# 更新容器并重载 Nginx
ssh root@192.168.0.200 "docker cp /root/docker-site/public/. mysite:/usr/share/nginx/html/ && docker exec mysite nginx -s reload"
```

#### 特殊场景：Nginx 配置变更

如果修改了 `nginx-custom.conf`，需要额外执行：

```bash
docker cp /root/docker-site/nginx-custom.conf mysite:/etc/nginx/conf.d/default.conf
docker exec mysite nginx -t
docker exec mysite nginx -s reload
```

### 📊 更新场景对照表

| 更新内容                    | 需要执行的操作                                                             |
| :-------------------------- | :------------------------------------------------------------------------- |
| 新增/修改博客文章（`.md`）  | 运行 `update-site.ps1` 即可                                                |
| 修改主题配置（`hugo.yaml`） | 运行 `update-site.ps1` 即可                                                |
| 修改 Nginx 配置             | `update-site.ps1` + 额外 `docker cp nginx-custom.conf` + `nginx -s reload` |
| 修改 Dockerfile             | 需要重建镜像：`docker build` + 重建容器（一般不需要）                      |
| 只推送源码不改网站          | 运行 `update-site.ps1`，脚本会提交 main 分支，公网/内网若无变更则跳过      |

### 🔧 虚拟机内关键路径速查

| 文件/目录              | 路径                                  |
| :--------------------- | :------------------------------------ |
| Nginx 配置（宿主机）   | `/root/docker-site/nginx-custom.conf` |
| Nginx 配置（容器内）   | `/etc/nginx/conf.d/default.conf`      |
| 网站静态文件（宿主机） | `/root/docker-site/public/`           |
| 网站静态文件（容器内） | `/usr/share/nginx/html/`              |
| 日志重定向文件         | `/var/log/mysite/access.log`          |
| Dockerfile             | `/root/docker-site/Dockerfile`        |

### ✅ 验证清单

部署完成后，确认以下检查点：

- [ ] 公网：`https://hyh25.github.io/my-portfolio/` 正常访问，样式完整
- [ ] 内网：`http://192.168.0.200:8080` 正常访问，样式完整
- [ ] 公网和内网资源路径均正确（无 404）
- [ ] Grafana 日志查询 `{job="nginx"}` 能看到新访问记录

### 📌 日常维护建议

1. **内容更新**：只需运行 `.\update-site.ps1`，无需任何手动操作。
2. **Nginx 配置变更**：先修改 `nginx-custom.conf`，再运行脚本，最后手动执行 `docker cp` + `nginx -s reload`。
3. **不要频繁重建镜像**：只有修改 `Dockerfile` 或基础镜像时才需要重建。网站内容更新只需替换 `public/`，不涉及镜像。
4. **`.gitignore` 确保 `public/` 不被提交到 main**：public 是构建产物，只存在于 gh-pages 分支。
