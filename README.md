# filescodebox Helm Charts

[![CI](https://github.com/filescodebox/charts/actions/workflows/lint-test.yml/badge.svg)](https://github.com/filescodebox/charts/actions/workflows/lint-test.yml)
[![Chart](https://img.shields.io/github/v/tag/filescodebox/charts?label=chart)](https://github.com/filescodebox/charts/tags)
[![License](https://img.shields.io/github/license/filescodebox/charts)](LICENSE)

[FilesCodeBox](https://github.com/filescodebox/filescodebox)（文件快递柜 — 匿名口令分享文本/文件）生态的 Kubernetes Helm Chart 仓库。
独立发版：chart 版本与业务仓库版本解耦，chart 里的 `appVersion` 对应 `server` 镜像 tag。

> 🗂️ [FilesCodeBox 生态](https://github.com/orgs/filescodebox)成员仓 · 总览与部署见 [装配仓 filescodebox](https://github.com/filescodebox/filescodebox) · [架构图集](https://github.com/filescodebox/filescodebox/blob/main/docs/architecture.md)

## Chart 一览

| Chart | 说明 | Chart 版本 | App 版本 |
|---|---|---|---|
| `filecodebox` | 前后端分离双 Deployment：[frontend](https://github.com/filescodebox/frontend)（nginx 静态+反代）→ [server](https://github.com/filescodebox/server)（API）；Ingress 指向 frontend Service | 1.3.23 | v0.14.0 |

支持可选组件：Redis（默认开）/ MySQL / PostgreSQL / S3 对象存储（SeaweedFS）/ PVC / Ingress / ServiceMonitor(Prometheus) / p2p 联邦注册中心（1.3.4 起，`p2p.enabled`，1.3.7 起含直传中继开关）；1.3.22 起多副本双拓扑（`replicaCount>1` 自动渲染 public×N + admin×1，`FCB_DEPLOY_MODE`）。

## 安装

方式一：Helm 仓库（GitHub Pages，由 chart-releaser 自动发布）

```bash
helm repo add filescodebox https://filescodebox.github.io/charts
helm repo update
helm install filecodebox filescodebox/filecodebox \
  --namespace filecodebox --create-namespace
```

方式二：OCI 制品（ghcr.io，与 Pages 同步发布）

```bash
helm install filecodebox oci://ghcr.io/filescodebox/charts/filecodebox
```

> 该 OCI 包已设为 public，可匿名安装。注意：org 包由 CI（GITHUB_TOKEN）推送时默认 private，且 GitHub 无修改可见性的 API——若将来删除重建，需在 org Settings → Packages 手动改回 public。

方式三：直接使用 Release 制品

从 [Releases](https://github.com/filescodebox/charts/releases) 下载 `filecodebox-<version>.tgz`：

```bash
helm install filecodebox ./filecodebox-1.3.23.tgz
```

生产环境最少建议覆盖：

```bash
helm install filecodebox filescodebox/filecodebox \
  --set secret.adminPassword='<强密码>' \
  --set secret.production=true \
  --set ingress.enabled=true \
  --set ingress.hosts[0].host=<你的域名>
```

完整参数与生产建议见 [charts/filecodebox/README.md](charts/filecodebox/README.md)。

## 发布新版本（维护者）

1. 修改 `charts/filecodebox/Chart.yaml` 的 `version`（chart 语义化版本）和/或 `appVersion`（对应 server 镜像 tag）
2. push 到 `main`
3. [chart-releaser](https://github.com/helm/chart-releaser-action) 自动执行：打包 `.tgz` → 发 GitHub Release → 更新 `gh-pages/index.yaml`（Helm 仓库索引）

chart `version` 未变化的 push 不会重复发布。

## CI

- `lint-test.yml`：PR / push 时用 [chart-testing](https://github.com/helm/chart-testing) 做 `ct lint`，并在 kind 集群上 `ct install` 安装冒烟（CI 会轮询等待 `appVersion` 对应镜像发布后 `kind load` 预载）。
  **前置条件**：`ghcr.io/filescodebox/server` 与 `ghcr.io/filescodebox/frontend` 镜像包需为 public（或给 CI 配置 imagePullSecrets），否则安装步骤会因拉取镜像失败。
- `release.yml`：push 到 `main` 自动发布。

仓库首次发布后需确认 GitHub Pages 已启用：Settings → Pages → Source = `gh-pages` branch / `/(root)`。

## License

[Apache-2.0](LICENSE)
