{{/*
展开 chart 名(支持 nameOverride)
*/}}
{{- define "filecodebox.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
完整资源名(支持 fullnameOverride；release 名已含 chart 名时不重复拼接)
*/}}
{{- define "filecodebox.fullname" -}}
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
{{- define "filecodebox.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
通用标签
*/}}
{{- define "filecodebox.labels" -}}
helm.sh/chart: {{ include "filecodebox.chart" . }}
{{ include "filecodebox.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
选择器标签
*/}}
{{- define "filecodebox.selectorLabels" -}}
app.kubernetes.io/name: {{ include "filecodebox.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
ServiceAccount 名
*/}}
{{- define "filecodebox.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "filecodebox.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
镜像地址: repository + tag(缺省 AppVersion)
*/}}
{{- define "filecodebox.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- printf "%s:%s" .Values.image.repository $tag -}}
{{- end }}

{{/*
Secret 名: 优先 existingSecret
*/}}
{{- define "filecodebox.secretName" -}}
{{- default (include "filecodebox.fullname" .) .Values.secret.existingSecret }}
{{- end }}

{{/*
稳定的 JWT 密钥: 用户显式值 > 集群中既有 Secret 的值 > 随机生成。
注意 lookup 仅在真实集群中生效(helm upgrade 稳定)；Argo CD 等纯渲染工具请显式设置 secret.jwtSecret。
*/}}
{{- define "filecodebox.jwtSecret" -}}
{{- if .Values.secret.jwtSecret }}
{{- .Values.secret.jwtSecret }}
{{- else }}
{{- $existing := lookup "v1" "Secret" .Release.Namespace (include "filecodebox.secretName" .) }}
{{- if and $existing $existing.data }}
{{- index $existing.data "FCB_JWT_SECRET" | b64dec }}
{{- else }}
{{- randAlphaNum 48 }}
{{- end }}
{{- end }}
{{- end }}
