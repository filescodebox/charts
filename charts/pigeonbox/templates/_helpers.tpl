{{/*
展开 chart 名(支持 nameOverride)
*/}}
{{- define "pigeonbox.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
完整资源名(支持 fullnameOverride；release 名已含 chart 名时不重复拼接)
*/}}
{{- define "pigeonbox.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
chart 名-版本(标签用)
*/}}
{{- define "pigeonbox.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
通用标签
*/}}
{{- define "pigeonbox.labels" -}}
helm.sh/chart: {{ include "pigeonbox.chart" . }}
{{ include "pigeonbox.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
选择器标签
*/}}
{{- define "pigeonbox.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pigeonbox.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
ServiceAccount 名
*/}}
{{- define "pigeonbox.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "pigeonbox.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
镜像地址: repository + tag(缺省 AppVersion)。
ghcr 镜像 tag 无 v 前缀(metadata-action semver 产出 0.6.4 形态)，而 AppVersion
惯例带 v(v0.6.4)——此处统一剥 v，两种写法都安全；显式 image.tag 同样容忍带 v。
*/}}
{{- define "pigeonbox.image" -}}
{{- $tag := (.Values.image.tag | default .Chart.AppVersion | toString) | trimPrefix "v" -}}
{{- printf "%s:%s" .Values.image.repository $tag -}}
{{- end }}

{{/*
前端组件完整资源名(前后端分离部署；后端资源名保持 fullname 不变以兼容升级)
*/}}
{{- define "pigeonbox.frontend.fullname" -}}
{{- printf "%s-frontend" (include "pigeonbox.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
前端选择器标签(name 带 -frontend 后缀，与后端 Service/ServiceMonitor 选择器天然隔离)
*/}}
{{- define "pigeonbox.frontend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pigeonbox.name" . }}-frontend
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
前端通用标签
*/}}
{{- define "pigeonbox.frontend.labels" -}}
helm.sh/chart: {{ include "pigeonbox.chart" . }}
{{ include "pigeonbox.frontend.selectorLabels" . }}
app.kubernetes.io/component: frontend
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
前端镜像地址: 与 server 镜像同一版本列车(缺省 AppVersion,剥 v 前缀)
*/}}
{{- define "pigeonbox.frontend.image" -}}
{{- $tag := (.Values.frontend.image.tag | default .Chart.AppVersion | toString) | trimPrefix "v" -}}
{{- printf "%s:%s" .Values.frontend.image.repository $tag -}}
{{- end }}

{{/*
Secret 名: 优先 existingSecret
*/}}
{{- define "pigeonbox.secretName" -}}
{{- default (include "pigeonbox.fullname" .) .Values.secret.existingSecret }}
{{- end }}

{{/*
稳定的 JWT 密钥: 用户显式值 > 集群中既有 Secret 的值 > 随机生成。
注意 lookup 仅在真实集群中生效(helm upgrade 稳定)；Argo CD 等纯渲染工具请显式设置 secret.jwtSecret。
*/}}
{{- define "pigeonbox.jwtSecret" -}}
{{- if .Values.secret.jwtSecret }}
{{- .Values.secret.jwtSecret }}
{{- else }}
{{- $existing := lookup "v1" "Secret" .Release.Namespace (include "pigeonbox.secretName" .) }}
{{- if and $existing $existing.data }}
{{- index $existing.data "PB_JWT_SECRET" | b64dec }}
{{- else }}
{{- randAlphaNum 48 }}
{{- end }}
{{- end }}
{{- end }}

{{/*
稳定的管理员密码: 用户显式值 > 集群中既有 Secret 的值 > 随机生成。
2026-10-05 安全审计：默认值由 admin123 改为随机生成(lookup 复用,升级稳定)；
Argo CD 等纯渲染工具请显式设置 secret.adminPassword。
*/}}
{{- define "pigeonbox.adminPassword" -}}
{{- if .Values.secret.adminPassword }}
{{- .Values.secret.adminPassword }}
{{- else }}
{{- $existing := lookup "v1" "Secret" .Release.Namespace (include "pigeonbox.secretName" .) }}
{{- if and $existing $existing.data }}
{{- index $existing.data "PB_ADMIN_PASSWORD" | b64dec }}
{{- else }}
{{- randAlphaNum 24 }}
{{- end }}
{{- end }}
{{- end }}

{{/*
server 平面 component(多副本拆分): standalone → server(与历史一致); 拆分 public → server-public; admin → server-admin
入参 dict: root(chart 上下文) / plane(standalone|public|admin)
*/}}
{{- define "pigeonbox.server.component" -}}
{{- if eq .plane "admin" }}server-admin{{- else if eq .plane "public" }}server-public{{- else }}server{{- end }}
{{- end }}

{{/*
server 平面完整资源名: standalone/public 沿用 fullname(资源名不变,兼容升级);
admin 用短名 <release>-admin(release 命名空间内无歧义,不再叠 chart 名)
*/}}
{{- define "pigeonbox.server.fullname" -}}
{{- if eq .plane "admin" -}}
{{- printf "%s-admin" .root.Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "pigeonbox.fullname" .root -}}
{{- end -}}
{{- end }}

{{/*
server 平面选择器标签(component 隔离 public/admin 两个 Deployment 的 Service 选择)
*/}}
{{- define "pigeonbox.server.selectorLabels" -}}
{{ include "pigeonbox.selectorLabels" .root }}
app.kubernetes.io/component: {{ include "pigeonbox.server.component" . }}
{{- end }}

{{/*
server 平面通用标签
*/}}
{{- define "pigeonbox.server.labels" -}}
helm.sh/chart: {{ include "pigeonbox.chart" .root }}
{{ include "pigeonbox.server.selectorLabels" . }}
{{- if .root.Chart.AppVersion }}
app.kubernetes.io/version: {{ .root.Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
{{- end }}

{{/*
数据面组件完整资源名(redis/mysql/postgresql;独立 name 后缀,与后端 Service/ServiceMonitor 选择器隔离)
*/}}
{{- define "pigeonbox.redis.fullname" -}}
{{- printf "%s-redis" (include "pigeonbox.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "pigeonbox.mysql.fullname" -}}
{{- printf "%s-mysql" (include "pigeonbox.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "pigeonbox.postgresql.fullname" -}}
{{- printf "%s-postgresql" (include "pigeonbox.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "pigeonbox.s3.fullname" -}}
{{- printf "%s-s3" (include "pigeonbox.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "pigeonbox.p2p.fullname" -}}
{{- printf "%s-p2p" (include "pigeonbox.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
数据面组件选择器标签(name 带 -<组件> 后缀)
*/}}
{{- define "pigeonbox.data.selectorLabels" -}}
{{- $component := .component -}}
app.kubernetes.io/name: {{ include "pigeonbox.name" $ }}-{{ $component }}
app.kubernetes.io/instance: {{ $.Release.Name }}
{{- end }}

{{/*
数据面组件通用标签
*/}}
{{- define "pigeonbox.data.labels" -}}
{{- $component := .component -}}
helm.sh/chart: {{ include "pigeonbox.chart" $ }}
{{ include "pigeonbox.data.selectorLabels" (dict "component" $component "Release" $.Release "Values" $.Values "Chart" $.Chart "Template" $.Template) }}
app.kubernetes.io/component: {{ $component }}
{{- if $.Chart.AppVersion }}
app.kubernetes.io/version: {{ $.Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ $.Release.Service }}
{{- end }}

{{/*
稳定随机密码: 用户显式值 > 集群中既有 Secret 的值 > 随机生成(24 位)。
lookup 仅在真实集群中生效(helm upgrade 稳定);纯渲染工具请显式设置密码。
入参 dict: secretName / key / explicit(用户显式值,可空)
*/}}
{{- define "pigeonbox.stablePassword" -}}
{{- if .explicit }}
{{- .explicit }}
{{- else }}
{{- $existing := lookup "v1" "Secret" .Release.Namespace .secretName }}
{{- if and $existing $existing.data (hasKey $existing.data .key) }}
{{- index $existing.data .key | b64dec }}
{{- else }}
{{- randAlphaNum 24 }}
{{- end }}
{{- end }}
{{- end }}
