{{/*
server Deployment 共享模板(多副本拆分,2026-10-06):
同一镜像按 FCB_DEPLOY_MODE 渲染三种平面——
  standalone(默认): 全功能单副本,资源名/标签与历史版本一致(升级零迁移);
  public(可 N 副本): 公开面路由,只读配置+订阅管理端变更广播,不跑迁移/后台任务;
  admin(全局 1 副本): 管理面路由 + 迁移 + 后台任务 + 配置唯一写者(变更 Redis 广播)。
拆分硬约束(见 values.yaml serverAdmin 注释): mysql/postgresql + Redis + 多节点可读的存储。
入参 dict: root(chart 上下文) / plane(standalone|public|admin)
*/}}
{{- define "pigeonbox.server.deployment" -}}
{{- $ctx := .root -}}
{{- $plane := .plane -}}
{{- $split := ne $plane "standalone" -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "pigeonbox.server.fullname" (dict "root" $ctx "plane" $plane) }}
  labels:
    {{- include "pigeonbox.server.labels" (dict "root" $ctx "plane" $plane) | nindent 4 }}
spec:
  replicas: {{ if eq $plane "admin" }}1{{ else }}{{ $ctx.Values.replicaCount }}{{ end }}
  {{- if $ctx.Values.strategy.type }}
  strategy:
    type: {{ $ctx.Values.strategy.type }}
  {{- else if and $ctx.Values.persistence.enabled (not $ctx.Values.persistence.existingClaim) }}
  # ReadWriteOnce 卷不支持跨节点多挂载，滚动更新会卡住，改用 Recreate
  strategy:
    type: Recreate
  {{- end }}
  selector:
    matchLabels:
      {{- include "pigeonbox.server.selectorLabels" (dict "root" $ctx "plane" $plane) | nindent 6 }}
  template:
    metadata:
      annotations:
        {{- if $ctx.Values.config }}
        checksum/config: {{ include (print $ctx.Template.BasePath "/configmap.yaml") $ctx | sha256sum }}
        {{- end }}
        {{- if and $ctx.Values.secret.create (not $ctx.Values.secret.existingSecret) }}
        checksum/secret: {{ include (print $ctx.Template.BasePath "/secret.yaml") $ctx | sha256sum }}
        {{- end }}
        {{- with $ctx.Values.podAnnotations }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      labels:
        {{- include "pigeonbox.server.selectorLabels" (dict "root" $ctx "plane" $plane) | nindent 8 }}
        {{- with $ctx.Values.podLabels }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
    spec:
      {{- /* 数据面接线: 内置 redis/mysql/postgresql/s3(SeaweedFS) → FCB_* env(env 优先级高于 config)。
         让位判断用取值判空而非 hasKey: config.<段>=null(helm --set xxx=null 删除语义)也算未显式配置 */}}
      {{- $wireRedis := and $ctx.Values.redis.enabled (not (get ($ctx.Values.config | default dict) "redis")) }}
      {{- $wireS3 := and $ctx.Values.s3.enabled (not (get ($ctx.Values.config | default dict) "storage")) }}
      {{- /* 联邦仅在 standalone 注入: 多副本模式下节点身份是进程级密钥,语义未定义,
         core 侧也会自动降级——chart 干脆不接线,避免注入即冲突 */}}
      {{- $wireFed := and $ctx.Values.p2p.enabled (not (get ($ctx.Values.config | default dict) "federation")) (eq $plane "standalone") }}
      {{- if or $wireRedis $wireS3 }}
      initContainers:
        {{- if $wireRedis }}
        {{- /* core 仅在启动时探测 redis,连不上即降级——等 redis 就绪再起后端; 用 redis 镜像自带 redis-cli,不引入额外镜像 */}}
        - name: wait-redis
          image: {{ $ctx.Values.redis.image.repository }}:{{ $ctx.Values.redis.image.tag | default "7-alpine" }}
          imagePullPolicy: {{ $ctx.Values.redis.image.pullPolicy }}
          command: ["sh", "-c", "until redis-cli -h {{ include "pigeonbox.redis.fullname" $ctx }} ping 2>/dev/null | grep -q PONG; do echo waiting for redis; sleep 2; done"]
          resources:
            requests:
              cpu: 10m
              memory: 16Mi
        {{- end }}
        {{- if $wireS3 }}
        {{- /* 桶存在 ⇒ S3 网关就绪, head-bucket 探测+建桶一步完成; aws-cli 走 SigV4 而非 minio 专有客户端。
           corsOrigins 非空时顺手写桶 CORS(直传/直下浏览器跨域必需, 幂等可重复执行) */}}
        - name: wait-s3-bucket
          image: {{ $ctx.Values.s3.initImage.repository }}:{{ $ctx.Values.s3.initImage.tag }}
          env:
            - name: AWS_ACCESS_KEY_ID
              value: {{ $ctx.Values.s3.auth.accessKey | quote }}
            - name: AWS_SECRET_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: {{ include "pigeonbox.s3.fullname" $ctx }}
                  key: secret-key
            - name: AWS_DEFAULT_REGION
              value: {{ $ctx.Values.s3.region | default "us-east-1" }}
            - name: S3_ENDPOINT
              value: http://{{ include "pigeonbox.s3.fullname" $ctx }}:8333
            {{- with $ctx.Values.s3.corsOrigins }}
            - name: S3_CORS_CONFIG
              value: {{ (dict "CORSRules" (list (dict "AllowedOrigins" . "AllowedMethods" (list "GET" "PUT" "POST" "HEAD") "AllowedHeaders" (list "*") "MaxAgeSeconds" 3600))) | toJson | quote }}
            {{- end }}
          command: ["sh", "-c", "until aws --endpoint-url \"$S3_ENDPOINT\" s3api head-bucket --bucket {{ $ctx.Values.s3.bucket }} 2>/dev/null; do aws --endpoint-url \"$S3_ENDPOINT\" s3api create-bucket --bucket {{ $ctx.Values.s3.bucket }} || true; echo waiting for s3; sleep 5; done; if [ -n \"$S3_CORS_CONFIG\" ]; then aws --endpoint-url \"$S3_ENDPOINT\" s3api put-bucket-cors --bucket {{ $ctx.Values.s3.bucket }} --cors-configuration \"$S3_CORS_CONFIG\" && echo s3 cors applied; fi"]
          resources:
            requests:
              cpu: 10m
              memory: 16Mi
        {{- end }}
      {{- end }}
      {{- with $ctx.Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      serviceAccountName: {{ include "pigeonbox.serviceAccountName" $ctx }}
      securityContext:
        {{- toYaml $ctx.Values.podSecurityContext | nindent 8 }}
      containers:
        - name: {{ $ctx.Chart.Name }}
          securityContext:
            {{- toYaml $ctx.Values.securityContext | nindent 12 }}
          image: {{ include "pigeonbox.image" $ctx }}
          imagePullPolicy: {{ $ctx.Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: {{ $ctx.Values.containerPort }}
              protocol: TCP
          envFrom:
            - secretRef:
                name: {{ include "pigeonbox.secretName" $ctx }}
          {{- $wireRedis := and $ctx.Values.redis.enabled (not (get ($ctx.Values.config | default dict) "redis")) }}
          {{- $wireS3 := and $ctx.Values.s3.enabled (not (get ($ctx.Values.config | default dict) "storage")) }}
          {{- $wireFed := and $ctx.Values.p2p.enabled (not (get ($ctx.Values.config | default dict) "federation")) (eq $plane "standalone") }}
          {{- /* 联邦 public_url: 显式值 > config.server.base_url;都空则不注入
             (bootstrap 联邦初始化会失败降级,日志可见——public_url 是取件方
             直连本站的地址,无法瞎猜) */}}
          {{- $fedPublicURL := $ctx.Values.p2p.publicURL -}}
          {{- if not $fedPublicURL -}}
          {{- with ($ctx.Values.config | default dict).server -}}{{- $fedPublicURL = .base_url -}}{{- end -}}
          {{- end -}}
          {{- if or $ctx.Values.trustedProxies $ctx.Values.extraEnv $wireRedis $wireS3 $wireFed $ctx.Values.mysql.enabled $ctx.Values.postgresql.enabled $split }}
          env:
            {{- /* 多副本拆分: 显式声明运行平面;限流计数走 Redis 多实例共享 */}}
            {{- if $split }}
            - name: FCB_DEPLOY_MODE
              value: {{ $plane | quote }}
            - name: FCB_RATE_LIMIT_USE_REDIS
              value: "true"
            {{- end }}
            {{- with $ctx.Values.trustedProxies }}
            - name: FCB_TRUSTED_PROXIES
              value: {{ join "," . | quote }}
            {{- end }}
            {{- with $ctx.Values.extraEnv }}
            {{- toYaml . | nindent 12 }}
            {{- end }}
            {{- if $wireRedis }}
            - name: FCB_REDIS_HOST
              value: {{ include "pigeonbox.redis.fullname" $ctx }}
            - name: FCB_REDIS_PORT
              value: "6379"
            {{- if $ctx.Values.redis.auth.password }}
            - name: FCB_REDIS_PASSWORD
              value: {{ $ctx.Values.redis.auth.password | quote }}
            {{- end }}
            {{- end }}
            {{- if $ctx.Values.mysql.enabled }}
            - name: FCB_DATABASE_DRIVER
              value: mysql
            - name: FCB_DATABASE_HOST
              value: {{ include "pigeonbox.mysql.fullname" $ctx }}
            - name: FCB_DATABASE_PORT
              value: "3306"
            - name: FCB_DATABASE_USER
              value: {{ $ctx.Values.mysql.auth.username | quote }}
            - name: FCB_DATABASE_DB_NAME
              value: {{ $ctx.Values.mysql.auth.database | quote }}
            - name: FCB_DATABASE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ include "pigeonbox.mysql.fullname" $ctx }}
                  key: user-password
            {{- end }}
            {{- if $ctx.Values.postgresql.enabled }}
            - name: FCB_DATABASE_DRIVER
              value: postgres
            - name: FCB_DATABASE_HOST
              value: {{ include "pigeonbox.postgresql.fullname" $ctx }}
            - name: FCB_DATABASE_PORT
              value: "5432"
            - name: FCB_DATABASE_USER
              value: {{ $ctx.Values.postgresql.auth.username | quote }}
            - name: FCB_DATABASE_DB_NAME
              value: {{ $ctx.Values.postgresql.auth.database | quote }}
            - name: FCB_DATABASE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ include "pigeonbox.postgresql.fullname" $ctx }}
                  key: user-password
            {{- end }}
            {{- if $wireS3 }}
            {{- /* storage.s3 env 映射需 core v0.7.7+(server 镜像 >= 0.9.3);
               集群内端点是私网地址,须放开 core 的 SSRF 端点防护才可用 */}}
            - name: FCB_SSRF_ALLOW_PRIVATE
              value: "true"
            - name: FCB_STORAGE_TYPE
              value: s3
            - name: FCB_STORAGE_S3_ENDPOINT
              value: http://{{ include "pigeonbox.s3.fullname" $ctx }}:8333
            - name: FCB_STORAGE_S3_REGION
              value: {{ $ctx.Values.s3.region | default "us-east-1" }}
            - name: FCB_STORAGE_S3_BUCKET
              value: {{ $ctx.Values.s3.bucket | quote }}
            - name: FCB_STORAGE_S3_ACCESS_KEY
              value: {{ $ctx.Values.s3.auth.accessKey | quote }}
            - name: FCB_STORAGE_S3_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: {{ include "pigeonbox.s3.fullname" $ctx }}
                  key: secret-key
            - name: FCB_STORAGE_S3_USE_SSL
              value: "false"
            - name: FCB_STORAGE_S3_PATH_STYLE
              value: "true"
            {{- end }}
            {{- if $wireFed }}
            {{- /* P2P 联邦(M2): 节点身份密钥在 data 卷(persistence),重启不变 */}}
            - name: FCB_FEDERATION_ENABLED
              value: "true"
            - name: FCB_FEDERATION_REGISTRY_URL
              value: http://{{ include "pigeonbox.p2p.fullname" $ctx }}:12346
            {{- if $fedPublicURL }}
            - name: FCB_FEDERATION_PUBLIC_URL
              value: {{ $fedPublicURL | quote }}
            {{- end }}
            {{- end }}
          {{- end }}
          livenessProbe:
            httpGet:
              path: {{ $ctx.Values.probes.liveness.path }}
              port: http
            initialDelaySeconds: {{ $ctx.Values.probes.liveness.initialDelaySeconds }}
            periodSeconds: {{ $ctx.Values.probes.liveness.periodSeconds }}
            timeoutSeconds: {{ $ctx.Values.probes.liveness.timeoutSeconds }}
            failureThreshold: {{ $ctx.Values.probes.liveness.failureThreshold }}
          readinessProbe:
            httpGet:
              path: {{ $ctx.Values.probes.readiness.path }}
              port: http
            initialDelaySeconds: {{ $ctx.Values.probes.readiness.initialDelaySeconds }}
            periodSeconds: {{ $ctx.Values.probes.readiness.periodSeconds }}
            timeoutSeconds: {{ $ctx.Values.probes.readiness.timeoutSeconds }}
            failureThreshold: {{ $ctx.Values.probes.readiness.failureThreshold }}
          {{- if $ctx.Values.probes.startup.enabled }}
          startupProbe:
            httpGet:
              path: {{ $ctx.Values.probes.startup.path }}
              port: http
            periodSeconds: {{ $ctx.Values.probes.startup.periodSeconds }}
            failureThreshold: {{ $ctx.Values.probes.startup.failureThreshold }}
          {{- end }}
          resources:
            {{- toYaml $ctx.Values.resources | nindent 12 }}
          volumeMounts:
            - name: data
              mountPath: {{ $ctx.Values.persistence.mountPath }}
            {{- if $ctx.Values.config }}
            - name: config
              mountPath: /app/config/config.yaml
              subPath: config.yaml
              readOnly: true
            {{- end }}
            {{- with $ctx.Values.extraVolumeMounts }}
            {{- toYaml . | nindent 12 }}
            {{- end }}
      volumes:
        - name: data
          {{- /* 两个平面共享同一 data 卷: admin 侧过期清理/janitor 删物理文件、
             federation key 等;多节点调度时该卷须 RWX,或改用 s3 后端 */}}
          {{- if $ctx.Values.persistence.enabled }}
          persistentVolumeClaim:
            claimName: {{ default (include "pigeonbox.fullname" $ctx) $ctx.Values.persistence.existingClaim }}
          {{- else }}
          emptyDir: {}
          {{- end }}
        {{- if $ctx.Values.config }}
        - name: config
          configMap:
            name: {{ include "pigeonbox.fullname" $ctx }}-config
        {{- end }}
        {{- with $ctx.Values.extraVolumes }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      {{- with $ctx.Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $ctx.Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $ctx.Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
{{- end }}
