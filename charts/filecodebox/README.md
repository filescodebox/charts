# filecodebox

FileCodeBox（文件快递柜 — 匿名口令分享文本/文件）的 Helm Chart，部署 [filescodebox/server](https://github.com/filescodebox/server) 单容器（镜像内置前端静态资源）。

```bash
helm repo add filescodebox https://filescodebox.github.io/charts
helm repo update
helm install filecodebox filescodebox/filecodebox --namespace filecodebox --create-namespace
```

## 生产建议

- `--set secret.adminPassword='<强密码>'` 覆盖默认管理密码 `admin123`
- `--set secret.production=true` 开启 secret 强校验
- 数据库切外部 MySQL/Postgres（`config.database.driver` + `secret.database` 注入密码），存储切 S3/WebDAV（`config.storage`）后，才考虑 `replicaCount > 1`
- Ingress 挂 TLS，并设置 `config.server.base_url` 为对外地址（分享链接生成用）
- `config.security.cors.allow_origins` 显式列出可信域名

## 参数

### 全局

| 参数 | 说明 | 默认值 |
|---|---|---|
| `replicaCount` | 副本数（SQLite 部署保持 1） | `1` |
| `containerPort` | 容器内应用监听端口 | `12345` |
| `image.repository` | 镜像 | `ghcr.io/filescodebox/server` |
| `image.tag` | 镜像 tag | `.Chart.AppVersion`（如 `v0.1.1`） |
| `image.pullPolicy` | 拉取策略 | `IfNotPresent` |
| `imagePullSecrets` | 私仓凭证 | `[]` |
| `nameOverride` / `fullnameOverride` | 资源名覆盖 | `""` |
| `serviceAccount.create` / `annotations` / `name` | ServiceAccount | `true` / `{}` / `""` |
| `podAnnotations` / `podLabels` | Pod 注解/标签 | `{}` |
| `podSecurityContext` | Pod 安全上下文 | `fsGroup: 1000` |
| `securityContext` | 容器安全上下文（镜像以 uid/gid 1000 运行） | 非 root、drop ALL |
| `strategy` | 部署策略，留空自动判断（新建 RWO 卷 → Recreate） | `{}` |
| `nodeSelector` / `tolerations` / `affinity` | 调度 | `{}` / `[]` / `{}` |
| `extraEnv` / `extraVolumes` / `extraVolumeMounts` | 追加 env / 卷 / 挂载 | `[]` |

### 网络

| 参数 | 说明 | 默认值 |
|---|---|---|
| `service.type` / `port` / `nodePort` | Service | `ClusterIP` / `12345` / `""` |
| `ingress.enabled` / `className` / `annotations` / `hosts` / `tls` | Ingress（networking.k8s.io/v1） | `false` |
| `metrics.serviceMonitor.enabled` | Prometheus Operator ServiceMonitor | `false` |
| `metrics.serviceMonitor.interval` / `path` / `namespace` / `labels` | ServiceMonitor 细项 | `30s` / `/metrics` / `""` / `{}` |

### 存储

| 参数 | 说明 | 默认值 |
|---|---|---|
| `persistence.enabled` | 持久化 SQLite + 本地上传文件（容器 `/app/data`） | `true` |
| `persistence.existingClaim` | 使用已有 PVC | `""` |
| `persistence.storageClass` / `accessModes` / `size` | PVC 规格 | `""` / `[ReadWriteOnce]` / `5Gi` |

### 配置注入

| 参数 | 说明 | 默认值 |
|---|---|---|
| `config` | server 配置（渲染为 ConfigMap，subPath 覆盖 `/app/config/config.yaml`）。**注意是整体替换镜像内置配置文件**，请对照 [config.example.yaml](https://github.com/filescodebox/server/blob/main/configs/config.example.yaml) 提供完整结构；留空则使用镜像内置配置 | `{}` |
| `secret.create` / `existingSecret` | 是否创建 Secret / 引用已有 Secret | `true` / `""` |
| `secret.jwtSecret` | JWT 密钥；留空随机生成并跨升级复用（lookup，Argo CD 下需显式指定） | `""` |
| `secret.adminPassword` | 管理密码（`FCB_ADMIN_PASSWORD`） | `admin123` ⚠️ |
| `secret.production` | `FCB_PRODUCTION=1` 强制校验 secret | `false` |
| `secret.serverMode` | `FCB_SERVER_MODE` | `release` |
| `secret.database` / `secret.redis` | 追加 `FCB_DATABASE_*` / `FCB_REDIS_*` 键值对 | `{}` |
| `secret.extra` | 其他任意 `FCB_*` 键值对 | `{}` |
| `probes.liveness` / `probes.readiness` | 探针（默认 `/live`、`/ready`） | 见 values.yaml |

> 环境变量优先级高于配置文件，敏感项一律走 `secret.*`；`config.*` 只放非敏感配置。

## 示例：外部 MySQL + S3 + Ingress

```yaml
config:
  server:
    base_url: https://fcb.example.com
  database:
    driver: mysql
    host: mysql.data.svc.cluster.local
    port: 3306
    db_name: filecodebox
  storage:
    type: s3
    s3:
      endpoint: https://s3.example.com
      region: us-east-1
      bucket: filecodebox
  security:
    cors:
      allow_origins:
        - https://fcb.example.com
secret:
  adminPassword: change-me-please
  production: true
  database:
    user: filecodebox
    password: db-pass
  extra:
    FCB_STORAGE_S3_ACCESS_KEY: ak
    FCB_STORAGE_S3_SECRET_KEY: sk
ingress:
  enabled: true
  className: nginx
  hosts:
    - host: fcb.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: fcb-tls
      hosts:
        - fcb.example.com
```

## 限制说明

- 使用 Argo CD / Flux 等纯渲染（`helm template`）工具时，`lookup` 不可用，`secret.jwtSecret` 会随每次渲染重新随机 —— 请显式指定该值或改用 external-secrets。
- `metrics.serviceMonitor` 需要 prometheus-operator CRD 已安装。
