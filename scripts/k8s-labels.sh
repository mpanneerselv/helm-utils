#!/bin/bash
# k8s-label-tiered-auditor.sh

NAMESPACE=${1:-"default"}
KIND_FILTER=${2:-""} # Optional: e.g., "pods", "deployments", "configmaps"

if [ -z "$KIND_FILTER" ]; then
    echo "--- Analyzing ALL Resources in Namespace: $NAMESPACE ---"
    # Use api-resources to get everything (ConfigMaps, Mimir/Tempo CRDs, etc.)
    RESOURCE_LIST=$(kubectl api-resources --verbs=list --namespaced -o name | paste -sd "," -)
else
    echo "--- Analyzing KIND: $KIND_FILTER in Namespace: $NAMESPACE ---"
    RESOURCE_LIST="$KIND_FILTER"
fi

# 1. Gather targeted resources into JSON
ALL_RESOURCES=$(kubectl get $RESOURCE_LIST -n "$NAMESPACE" --ignore-not-found -o json)

# Check if any resources were found
ITEM_COUNT=$(echo "$ALL_RESOURCES" | jq '.items | length')
if [ "$ITEM_COUNT" -eq 0 ]; then
    echo "No resources found for the specified criteria."
    exit 0
fi

# 2. GLOBAL COMMON (Across all objects in the selection)
GLOBAL_COMMON=$(echo "$ALL_RESOURCES" | jq -c '
  .items | map(.metadata.labels // {} | keys_unsorted) | 
  if length > 0 then 
    reduce .[] as $item (.[0]; . - (. - $item)) 
  else [] end')

echo -e "\n[ 1. GLOBAL COMMON LABELS ]"
if [ "$GLOBAL_COMMON" == "[]" ]; then echo "  (None)"; else
  echo "$ALL_RESOURCES" | jq -r --argjson gc "$GLOBAL_COMMON" '
    .items[0].metadata.labels | with_entries(select(.key == ($gc[]))) | to_entries[] | "  - \(.key): \(.value)"' | sort -u
fi

# 3. KIND COMMON (Labels common to a Kind, but NOT Global Common)
# This is particularly useful when auditing Mimir's different microservices.
echo -e "\n[ 2. KIND COMMON LABELS ] (Excluding Global)"
echo "$ALL_RESOURCES" | jq -r --argjson gc "$GLOBAL_COMMON" '
  .items | group_by(.kind) | .[] | 
  {
    kind: .[0].kind,
    common_keys: (map(.metadata.labels // {} | keys_unsorted) | reduce .[] as $item (.[0]; . - (. - $item)) | . - $gc),
    first_labels: .[0].metadata.labels
  } | 
  if (.common_keys | length > 0) then
    "\n  \(.kind):", 
    (.common_keys[] as $k | "    - \($k): \(.first_labels[$k])")
  else empty end'

# 4. RESOURCE SPECIFIC (Unique labels NOT in Global or Kind-Common)
echo -e "\n[ 3. RESOURCE SPECIFIC LABELS ]"
echo "$ALL_RESOURCES" | jq -r --argjson gc "$GLOBAL_COMMON" '
  .items | group_by(.kind) | .[] | 
  (map(.metadata.labels // {} | keys_unsorted) | reduce .[] as $item (.[0]; . - (. - $item))) as $kc |
  .[] | 
  {
    name: "\(.kind)/\(.metadata.name)",
    specific: (.metadata.labels // {} | keys_unsorted | . - $kc)
  } | 
  if (.specific | length > 0) then
    "\n  \(.name):",
    (.specific[] as $k | "    - \($k)")
  else empty end'