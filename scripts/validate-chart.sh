#!/bin/bash
set -euo pipefail

# Comprehensive chart validation script
# Usage: ./validate-chart.sh <chart_dir>

CHART_DIR=$1

echo "🔍 Running comprehensive chart validation..."

# Basic helm lint
echo "Running helm lint..."
helm lint "$CHART_DIR"

# Template validation with different values
echo "Validating templates with default values..."
helm template test "$CHART_DIR" --dry-run > /dev/null

# Test with different value combinations
if [ -f "$CHART_DIR/ci/test-values.yaml" ]; then
    echo "Validating with test values..."
    helm template test "$CHART_DIR" -f "$CHART_DIR/ci/test-values.yaml" --dry-run > /dev/null
fi

# Check for required files
echo "Checking required files..."
required_files=("Chart.yaml" "values.yaml" "templates")
for file in "${required_files[@]}"; do
    if [ ! -e "$CHART_DIR/$file" ]; then
        echo "❌ Missing required file/directory: $file"
        exit 1
    fi
done

# Validate Chart.yaml structure
echo "Validating Chart.yaml structure..."
CHART_YAML="$CHART_DIR/Chart.yaml"

# Check required fields
required_fields=("name" "version" "description")
for field in "${required_fields[@]}"; do
    if ! yq eval ".$field" "$CHART_YAML" | grep -q "."; then
        echo "❌ Missing required field in Chart.yaml: $field"
        exit 1
    fi
done

# Validate version format
VERSION=$(yq eval '.version' "$CHART_YAML")
if [[ ! $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+(-.*)?$ ]]; then
    echo "❌ Invalid version format in Chart.yaml: $VERSION"
    exit 1
fi

# Check for template syntax issues
echo "Checking template syntax..."
TEMP_OUTPUT=$(mktemp)
if ! helm template test "$CHART_DIR" > "$TEMP_OUTPUT" 2>&1; then
    echo "❌ Template rendering failed:"
    cat "$TEMP_OUTPUT"
    rm "$TEMP_OUTPUT"
    exit 1
fi
rm "$TEMP_OUTPUT"

# Validate generated YAML
echo "Validating generated YAML syntax..."
helm template test "$CHART_DIR" | yq eval '.' > /dev/null

# Check for common issues
echo "Checking for common issues..."

# Check for hardcoded namespaces (should use .Release.Namespace)
if grep -r "namespace:" "$CHART_DIR/templates" | grep -v "\.Release\.Namespace" | grep -v "{{" | grep -q "."; then
    echo "⚠️  Found hardcoded namespaces in templates (consider using .Release.Namespace)"
fi

# Check for missing resource limits/requests in Deployments
RENDERED_TEMPLATES=$(mktemp)
helm template test "$CHART_DIR" > "$RENDERED_TEMPLATES"

if yq eval 'select(.kind == "Deployment") | .spec.template.spec.containers[] | select(.resources == null)' "$RENDERED_TEMPLATES" | grep -q "."; then
    echo "⚠️  Found containers without resource limits/requests"
fi

rm "$RENDERED_TEMPLATES"

# Validate values.yaml
echo "Validating values.yaml..."
if ! yq eval '.' "$CHART_DIR/values.yaml" > /dev/null; then
    echo "❌ Invalid YAML syntax in values.yaml"
    exit 1
fi

# Check for Mimir-specific requirements
echo "Validating Mimir-specific requirements..."
VALUES_CONTENT=$(yq eval '.' "$CHART_DIR/values.yaml")

# Check for distributed mode configuration
if echo "$VALUES_CONTENT" | yq eval '.mimir.structuredConfig.common.storage' | grep -q "null"; then
    echo "⚠️  Storage configuration not found in values.yaml"
fi

# Security checks
echo "Running security checks..."

# Check for privileged containers
RENDERED_TEMPLATES=$(mktemp)
helm template test "$CHART_DIR" > "$RENDERED_TEMPLATES"

if yq eval 'select(.kind == "Deployment" or .kind == "StatefulSet") | .spec.template.spec.containers[] | select(.securityContext.privileged == true)' "$RENDERED_TEMPLATES" | grep -q "."; then
    echo "⚠️  Found privileged containers"
fi

# Check for containers running as root
if yq eval 'select(.kind == "Deployment" or .kind == "StatefulSet") | .spec.template.spec.containers[] | select(.securityContext.runAsUser == 0)' "$RENDERED_TEMPLATES" | grep -q "."; then
    echo "⚠️  Found containers running as root"
fi

rm "$RENDERED_TEMPLATES"

echo "✅ Chart validation completed successfully"