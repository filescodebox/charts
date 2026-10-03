# filecodebox

FileCodeBox（文件快递柜 — 匿名口令分享文本/文件）的 Helm Chart，部署 [filescodebox/server](https://github.com/filescodebox/server) 单容器（镜像内置前端静态资源）。

```bash
helm repo add filescodebox https://filescodebox.github.io/charts
helm repo update
helm install filecodebox filescodebox/filecodebox --namespace filecodebox --create-namespace

# 或 OCI 方式: helm install filecodebox oci://ghcr.io/filescodebox/charts/filecodebox
```

## 生产建议

- `--set secret.adminPassword='<强密码>'` 覆盖默认管理密码 `admin123`
- `--set secret.production=true` 开启 secret 强校验；`FCB_JWT_SECRET` 全环境强制且要求 ≥32 位强随机（chart 自动生成的值已满足，显式传入短值会拒绝启动）
- **反代/Ingress 部署必须设置 `trustedProxies`**（如 `--set trustedProxies[0]=10.0.0.0/8`），否则应用不采信 X-Forwarded-For，限流/失败锁定会按代理地址误伤所有用户
- 通过内网 MinIO/WebDAV 使用对象存储时，设置 `config.security.ssrf.allow_private_networks: true`（或 env `FCB_SSRF_ALLOW_PRIVATE=true`）
- 数据库切外部 MySQL/Postgres（`config.database.driver` + `secret.database` 注入密码），存储切 S3/WebDAV（`config.storage`）后，才考虑 `replicaCount > 1`；多实例建议启用 Redis 并设置 `config.rate_limit.use_redis: true` 让限流计数跨实例共享
- Ingress 挂 TLS，并设置 `config.server.base_url` 为对外地址（分享链接生成用）；S3 直传/直下（`download.s3_direct_download`）需给存储桶配置 CORS
- `config.security.cors.allow_origins` 显式列出可信域名；预签名签名密钥如需独立于 JWT，可用 `secret.extra` 注入 `FCB_PRESIGN_SIGNING_KEY`（缺省复用 jwtSecret）

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
| `metrics.serviceMonitor.interval` / `scrapeTimeout` / `path` / `namespace` / `labels` | ServiceMonitor 细项 | `30s` / `""` / `/metrics` / `""` / `{}` |

### 存储

| 参数 | 说明 | 默认值 |
|---|---|---|
| `persistence.enabled` | 持久化 SQLite + 本地上传文件（容器 `/app/data`） | `true` |
| `persistence.existingClaim` | 使用已有 PVC | `""` |
| `persistence.storageClass` / `accessModes` / `size` | PVC 规格 | `""` / `[ReadWriteOnce]` / `10Gi` |

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
| `trustedProxies` | 可信代理网段 CIDR 列表，以 `FCB_TRUSTED_PROXIES` 注入；反代/Ingress 部署必填 | `[]` |
| `probes.liveness` / `probes.readiness` / `probes.startup` | 探针（默认 `/live`、`/readyz`，startupProbe 慢启动保护默认开启） | 见 values.yaml |

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
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
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
