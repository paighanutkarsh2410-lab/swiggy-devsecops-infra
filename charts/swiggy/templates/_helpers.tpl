{{/* Labels shared by every object. */}}
{{- define "swiggy.labels" -}}
app.kubernetes.io/part-of: swiggy-devsecops
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{/* Full image reference for one of the app's images. */}}
{{- define "swiggy.image" -}}
{{- $tag := required "image.tag must be set to an app commit SHA" .root.Values.image.tag -}}
{{- if not (kindIs "string" $tag) -}}
{{- fail "image.tag must be quoted in the values file, or YAML may read an all-digit SHA as a number" -}}
{{- end -}}
{{- if not (regexMatch "^[0-9a-f]{40}$" $tag) -}}
{{- fail (printf "image.tag must be a full 40-character commit SHA, got %q" $tag) -}}
{{- end -}}
{{ .root.Values.image.registry }}/{{ .name }}:{{ $tag }}
{{- end }}

{{/* Pod security settings that satisfy the restricted Pod Security Standard. */}}
{{- define "swiggy.containerSecurity" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: ["ALL"]
{{- end }}
