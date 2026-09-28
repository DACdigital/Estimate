{{/*
Standard helm helpers.
Extend cautiously — helm-framework provides its own name/fullname helpers under
"helm-framework.*". Names here are used by chart-owned templates (Postgres,
app Secret) that do not go through the library include.
*/}}

{{- define "estimate-chart.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "estimate-chart.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "estimate-chart.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "estimate-chart.labels" -}}
helm.sh/chart: {{ include "estimate-chart.chart" . }}
app.kubernetes.io/name: {{ include "estimate-chart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Composed DATABASE_URL. Priority:
  1. externalDatabase.url (when postgres.enabled=false)
  2. postgres://<user>:<password>@<fullname>-postgres:<port>/<database>
Used by templates/secret-app.yaml. Fails fast (missing password) if bundled
Postgres is enabled with no password and no existingSecretName.
*/}}
{{- define "estimate-chart.databaseUrl" -}}
{{- if .Values.postgres.enabled -}}
{{- $auth := .Values.postgres.auth -}}
{{- $pw := $auth.password -}}
{{- if and (not $pw) (not $auth.existingSecretName) -}}
{{- fail "postgres.auth.password (or postgres.auth.existingSecretName) must be set when postgres.enabled=true" -}}
{{- end -}}
{{- printf "postgres://%s:%s@%s-postgres:%d/%s"
    $auth.username
    $pw
    (include "estimate-chart.fullname" .)
    (int .Values.postgres.service.port)
    $auth.database -}}
{{- else -}}
{{- if not .Values.externalDatabase.url -}}
{{- fail "externalDatabase.url must be set when postgres.enabled=false" -}}
{{- end -}}
{{- .Values.externalDatabase.url -}}
{{- end -}}
{{- end -}}
