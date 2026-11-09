{{/* Labels shared by every object. */}}
{{- define "swiggy.labels" -}}
app.kubernetes.io/part-of: swiggy-devsecops
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{/* Full image reference for one of the app's images. */}}
{{- define "swiggy.image" -}}
{{- $tag := required "image.tag must be set to an app commit SHA" .root.Values.image.tag -}}
{{ .root.Values.image.registry }}/{{ .name }}:{{ $tag }}
{{- end }}

{{/* Pod security settings that satisfy the restricted Pod Security Standard. */}}
{{- define "swiggy.containerSecurity" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: ["ALL"]
{{- end }}
