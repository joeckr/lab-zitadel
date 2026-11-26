{{/*
Expand the name of the chart.
*/}}
{{- define "lab-zitadel.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "lab-zitadel.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "lab-zitadel.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "lab-zitadel.labels" -}}
helm.sh/chart: {{ include "lab-zitadel.chart" . }}
app.kubernetes.io/part-of: {{ include "lab-zitadel.name" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Core server selector labels
*/}}
{{- define "lab-zitadel.selectorLabels" -}}
app.kubernetes.io/name: {{ include "lab-zitadel.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: server
{{- end }}

{{/*
Login V2 selector labels
*/}}
{{- define "lab-zitadel.loginSelectorLabels" -}}
app.kubernetes.io/name: {{ include "lab-zitadel.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: login
{{- end }}

{{/*
Secret name for ZITADEL credentials
*/}}
{{- define "lab-zitadel.secretName" -}}
{{- if .Values.zitadel.existingSecret }}
{{- .Values.zitadel.existingSecret }}
{{- else }}
{{- printf "%s-secret" (include "lab-zitadel.fullname" .) }}
{{- end }}
{{- end }}

{{/*
TLS Secret name for Login V2 SystemAPIUser RSA keypair
*/}}
{{- define "lab-zitadel.loginKeySecretName" -}}
{{- if .Values.login.existingKeySecret }}
{{- .Values.login.existingKeySecret }}
{{- else }}
{{- printf "%s-login-service-key" (include "lab-zitadel.fullname" .) }}
{{- end }}
{{- end }}

{{/*
PostgreSQL connection helpers
*/}}
{{- define "lab-zitadel.postgresHost" -}}
{{- if .Values.postgres.enabled }}
{{- .Values.postgres.app.name }}
{{- else }}
{{- .Values.externalPostgres.host }}
{{- end }}
{{- end }}

{{- define "lab-zitadel.postgresPort" -}}
{{- if .Values.postgres.enabled }}
{{- .Values.postgres.app.port }}
{{- else }}
{{- .Values.externalPostgres.port }}
{{- end }}
{{- end }}

{{- define "lab-zitadel.postgresDb" -}}
{{- if .Values.postgres.enabled }}
{{- .Values.postgres.app.db }}
{{- else }}
{{- .Values.externalPostgres.db }}
{{- end }}
{{- end }}

{{- define "lab-zitadel.postgresUser" -}}
{{- if .Values.postgres.enabled }}
{{- .Values.postgres.app.user }}
{{- else }}
{{- .Values.externalPostgres.user }}
{{- end }}
{{- end }}

{{- define "lab-zitadel.postgresPassword" -}}
{{- if .Values.postgres.enabled }}
{{- .Values.postgres.app.password }}
{{- else }}
{{- .Values.externalPostgres.password }}
{{- end }}
{{- end }}

{{- define "lab-zitadel.postgresAdminUser" -}}
{{- if .Values.postgres.enabled }}
{{- .Values.postgres.app.user }}
{{- else }}
{{- default .Values.externalPostgres.user .Values.externalPostgres.adminUser }}
{{- end }}
{{- end }}

{{- define "lab-zitadel.postgresAdminPassword" -}}
{{- if .Values.postgres.enabled }}
{{- .Values.postgres.app.password }}
{{- else }}
{{- default .Values.externalPostgres.password .Values.externalPostgres.adminPassword }}
{{- end }}
{{- end }}

{{- define "lab-zitadel.postgresSslMode" -}}
{{- if .Values.postgres.enabled }}
{{- "disable" }}
{{- else }}
{{- .Values.externalPostgres.sslMode }}
{{- end }}
{{- end }}
