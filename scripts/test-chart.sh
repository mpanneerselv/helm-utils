#!/bin/bash
set -euo pipefail

# Chart testing script
# Usage: ./test-chart.sh <chart_dir>

CHART_DIR=$1

echo "🧪 Running chart tests..."

# Test with different value combinations
test_scenarios=(
    "default:Default values"
    "minimal:Minimal configuration"
    "production:Production configuration"
)

for scenario in "${test_scenarios[@]}"; do
    IFS=':' read -r name description <<< "$scenario"
    
    echo "Testing scenario: $description"
    
    values_file="$CHART_DIR/ci/${name}-values.yaml"
    if [ -f "$values_file" ]; then
        echo "  Using values file: $values_file"
        helm template "test-$name" "$CHART_DIR" -f "$values_file" --dry-run > /dev/null
        echo "  ✅ $description test passed"
    else
        echo "  ⏭️  Skipping $description (no values file found)"
    fi
done

# Test template rendering with various configurations
echo "Testing template rendering..."

# Test with different replica counts
echo "  Testing with different replica counts..."
for replicas in 1 3 5; do
    helm template test "$CHART_DIR" \
        --set mimir.ingester.replicas=$replicas \
        --set mimir.distributor.replicas=$replicas \
        --dry-run > /dev/null
done

# Test with different storage configurations
echo "  Testing with different storage configurations..."
storage_types=("filesystem" "s3" "gcs")
for storage in "${storage_types[@]}"; do
    case $storage in
        "filesystem")
            helm template test "$CHART_DIR" \
                --set mimir.structuredConfig.common.storage.backend=filesystem \
                --dry-run > /dev/null
            ;;
        "s3")
            helm template test "$CHART_DIR" \
                --set mimir.structuredConfig.common.storage.backend=s3 \
                --set mimir.structuredConfig.common.storage.s3.endpoint=s3.amazonaws.com \
                --set mimir.structuredConfig.common.storage.s3.bucket_name=mimir-blocks \
                --dry-run > /dev/null
            ;;
        "gcs")
            helm template test "$CHART_DIR" \
                --set mimir.structuredConfig.common.storage.backend=gcs \
                --set mimir.structuredConfig.common.storage.gcs.bucket_name=mimir-blocks \
                --dry-run > /dev/null
            ;;
    esac
done

# Test resource validation
echo "Testing resource validation..."
TEMP_OUTPUT=$(mktemp)
helm template test "$CHART_DIR" > "$TEMP_OUTPUT"

# Check that all required Mimir components are present
required_components=("ingester" "distributor" "querier" "query-frontend" "compactor" "store-gateway")
for component in "${required_components[@]}"; do
    if ! grep -q "mimir-$component" "$TEMP_OUTPUT"; then
        echo "❌ Missing required component: $component"
        exit 1
    fi
done

# Validate service configurations
echo "Validating service configurations..."
services=$(yq eval 'select(.kind == "Service") | .metadata.name' "$TEMP_OUTPUT")
if [ -z "$services" ]; then
    echo "❌ No services found in rendered templates"
    exit 1
fi

# Validate deployment configurations
echo "Validating deployment configurations..."
deployments=$(yq eval 'select(.kind == "Deployment" or .kind == "StatefulSet") | .metadata.name' "$TEMP_OUTPUT")
if [ -z "$deployments" ]; then
    echo "❌ No deployments found in rendered templates"
    exit 1
fi

# Test with custom annotations and labels
echo "Testing custom annotations and labels..."
helm template test "$CHART_DIR" \
    --set global.podAnnotations.test=value \
    --set global.podLabels.environment=test \
    --dry-run > /dev/null

# Test ingress configuration if enabled
echo "Testing ingress configuration..."
helm template test "$CHART_DIR" \
    --set nginx.ingress.enabled=true \
    --set nginx.ingress.hosts[0].host=mimir.example.com \
    --dry-run > /dev/null

# Cleanup
rm "$TEMP_OUTPUT"

echo "✅ All chart tests passed"