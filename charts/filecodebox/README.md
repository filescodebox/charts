# filecodebox

filescodebox（文件快递柜 — 匿名口令分享文本/文件）的 Helm Chart。

架构（0.3+）：**前后端分离两容器** —— `frontend`（[ghcr.io/filescodebox/frontend](https://github.com/filescodebox/frontend)，nginx 静态资源 + API 反代）与 `server`（[ghcr.io/filescodebox/server](https://github.com/filescodebox/server)，API/数据，携带 PVC）。Ingress/NodePort 指向 frontend Service，API 请求由其反代后端；两镜像同一版本列车（`frontend.image.tag` 缺省同 AppVersion，由 server 仓 release 工作流同步发布）。server 镜像为纯后端（0.9.0 起不含前端静态资源）；docker compose 模板同为前后端分离编排；fnOS 应用为独立打包，不受影响。

内置数据面服务（0.4+）：`redis.enabled` 默认开启（单副本 + AOF + PVC，自动注入 `FCB_REDIS_HOST`，开箱即用）；`mysql.enabled` / `postgresql.enabled` / `s3.enabled` 默认关闭，开启即部署单副本 StatefulSet 并自动注入 `FCB_DATABASE_*` / `FCB_STORAGE_S3_*`（密码自动生成存 Secret，可用 `*.auth.*Password` 显式指定；内置 S3 桶自动创建并放行 `FCB_SSRF_ALLOW_PRIVATE`，需 server 镜像 ≥ 0.9.3）。生产/多副本建议关闭内置实例、`config.database` + `config.storage` 指向外部服务。

> 内置对象存储为 **SeaweedFS**（Apache-2.0，S3 兼容，单进程 master+volume+filer+s3）。MinIO 自 2025-06 起停止发布社区容器镜像（Docker Hub / quay 均已拒绝匿名拉取），chart 无法再引用，故选型 SeaweedFS；对后端而言仅是标准 S3 端点，接入自建 MinIO / 云厂商 S3 亦只需 `config.storage` 或相应 env。

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
- 数据库切外部 MySQL/Postgres（`config.database.driver` + `secret.database` 注入密码；或直接开 `mysql.enabled` / `postgresql.enabled` 用内置单副本实例），存储切 S3/WebDAV（`config.storage`）后，才考虑 `replicaCount > 1`；多实例建议外部 Redis 并设 `config.rate_limit.use_redis: true` 让限流计数跨实例共享
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
| `service.type` / `port` / `nodePort` | 后端 Service（仅 frontend 反代与 metrics 抓取直连，不对外） | `ClusterIP` / `12345` / `""` |
| `frontend.service.type` / `port` / `nodePort` | 前端 Service（对外入口，Ingress/NodePort 均指向它） | `ClusterIP` / `80` / `""` |
| `ingress.enabled` / `className` / `annotations` / `hosts` / `tls` | Ingress（networking.k8s.io/v1，backend=frontend Service） | `false` |
| `metrics.serviceMonitor.enabled` | Prometheus Operator ServiceMonitor | `false` |
| `metrics.serviceMonitor.interval` / `scrapeTimeout` / `path` / `namespace` / `labels` | ServiceMonitor 细项 | `30s` / `""` / `/metrics` / `""` / `{}` |

### 前端（frontend）

| 参数 | 说明 | 默认值 |
|---|---|---|
| `frontend.replicaCount` | 前端副本数（无状态，可独立扩缩） | `1` |
| `frontend.image.repository` / `tag` / `pullPolicy` | 前端镜像；tag 缺省同 AppVersion（与 server 同版本列车） | `ghcr.io/filescodebox/frontend` / `""` / `IfNotPresent` |
| `frontend.containerPort` | nginx 监听端口（镜像非 root 固定 8080） | `8080` |
| `frontend.clientMaxBodySize` | nginx `client_max_body_size`（反代链路体积上限，须 ≥ `upload.upload_size`；镜像默认 20m，chart 放宽避免多文件 zip 下载/大请求体被 nginx 先拒） | `1024m` |
| `frontend.securityContext` | 前端容器安全上下文（镜像 uid/gid 101） | 非 root、drop ALL |
| `frontend.probes.liveness` / `readiness` | 前端探针（GET `/`） | 见 values.yaml |
| `frontend.resources` | 前端资源限额 | 64Mi~128Mi |
| `frontend.extraEnv` | 追加 env（如覆盖 `CLIENT_MAX_BODY_SIZE`） | `[]` |

> 反代上游自动指向本 release 的 server Service（`BACKEND_HOST`/`BACKEND_PORT` 自动注入），无需配置。

### 数据面（redis / mysql / postgresql）

| 参数 | 说明 | 默认值 |
|---|---|---|
| `redis.enabled` | 内置 Redis（匿名取件码等强依赖）；config 显式配置 `redis` 段时自动让位 | `true` |
| `redis.image.*` / `auth.password` / `persistence.*` / `resources` | 镜像 `redis:7-alpine`；密码留空=无密码(仅集群内)；AOF 持久化 1Gi | 见 values.yaml |
| `mysql.enabled` / `postgresql.enabled` | 内置 MySQL 8.4 / PostgreSQL 17 单副本 StatefulSet（默认关）；开启即自动注入 `FCB_DATABASE_*` | `false` |
| `mysql.auth.*` / `postgresql.auth.*` | `username`(默认 filecodebox)、`database`(默认 filecodebox)、密码留空=随机生成并跨升级复用 | 见 values.yaml |
| `mysql.persistence.size` / `postgresql.persistence.size` | 数据卷 | `10Gi` |
| `s3.enabled` | 内置 SeaweedFS（S3 兼容对象存储，单进程；自动建桶、注入 `FCB_STORAGE_*` 与 `FCB_SSRF_ALLOW_PRIVATE`；需 server ≥ 0.9.3） | `false` |
| `s3.image.*` / `initImage.*` / `auth.*` / `bucket` / `region` / `persistence.size` | SeaweedFS 镜像、建桶用 aws-cli init 容器、凭据（secretKey 留空随机生成）、桶名与 region | 见 values.yaml |
| `s3.corsOrigins` | 建桶后自动写入的桶 CORS（幂等；直传/直下等浏览器直连桶场景必需，`[]` 关闭） | `["*"]` |

**不使用 / 关闭内置 S3**：默认就是关闭（存储走本地 `local`）。启用过想关：`--set s3.enabled=false` 升级即可移除 StatefulSet，桶数据仍在 PVC 中（VCT 创建的 PVC 不会被 helm 删除）；想**部署但不接线**（例如复用内置桶给其他程序），给 `config.storage` 显式配置任意完整存储段即自动让位。预签名直传/直下需桶端点对浏览器可达——内置实例端点在集群内，这类场景请外接 S3 并以 `config.storage` 指向对外端点（凭据/桶可复用内置实例）。

> 内置实例接线优先级高于 `config`（env 覆盖）；三个组件继承顶层 `nodeSelector`/`tolerations`/`affinity`，离线集群需把对应镜像导入到被调度节点。

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
