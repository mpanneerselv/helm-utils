#!/bin/bash
set -euo pipefail

# Build custom chart with kustomizations
# Usage: ./build-chart.sh <base_chart_dir> <kustomize_dir> <output_dir>

BASE_CHART_DIR=$1
KUSTOMIZE_DIR=$2
OUTPUT_DIR=$3

echo "🏗️  Building custom chart..."
echo "Base chart: $BASE_CHART_DIR"
echo "Kustomize dir: $KUSTOMIZE_DIR"
echo "Output dir: $OUTPUT_DIR"

# Clean and create output directory
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Copy base chart to output directory
cp -r "$BASE_CHART_DIR"/* "$OUTPUT_DIR/"

# Update Chart.yaml metadata
CHART_YAML="$OUTPUT_DIR/Chart.yaml"
if [ -f "$CHART_YAML" ]; then
    # Update chart name and description
    yq eval '.name = "mimir-custom"' -i "$CHART_YAML"
    yq eval '.description = "Custom Grafana Mimir chart with kustomizations"' -i "$CHART_YAML"
    
    # Add custom annotations
    yq eval '.annotations."custom.chart/base-chart" = "mimir-distributed"' -i "$CHART_YAML"
    yq eval '.annotations."custom.chart/base-version" = "'$(yq eval '.version' "$BASE_CHART_DIR/Chart.yaml")'"' -i "$CHART_YAML"
    yq eval '.annotations."custom.chart/build-date" = "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"' -i "$CHART_YAML"
fi

# Apply values overrides if they exist
if [ -f "$KUSTOMIZE_DIR/values-override.yaml" ]; then
    echo "📝 Applying values overrides..."
    
    # Merge values files
    VALUES_FILE="$OUTPUT_DIR/values.yaml"
    TEMP_VALUES=$(mktemp)
    
    # Use yq to merge values
    yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \
        "$VALUES_FILE" "$KUSTOMIZE_DIR/values-override.yaml" > "$TEMP_VALUES"
    
    mv "$TEMP_VALUES" "$VALUES_FILE"
    echo "✅ Values overrides applied"
fi

# Process template files with kustomize if kustomization.yaml exists
if [ -f "$KUSTOMIZE_DIR/kustomization.yaml" ]; then
    echo "🔧 Applying kustomize transformations..."
    
    # Create temporary directory for kustomize processing
    TEMP_DIR=$(mktemp -d)
    TEMPLATES_DIR="$OUTPUT_DIR/templates"
    
    # Generate base manifests from helm chart
    helm template mimir-base "$OUTPUT_DIR" --output-dir "$TEMP_DIR/base" > /dev/null
    
    # Create kustomization structure
    mkdir -p "$TEMP_DIR/kustomize"
    cp -r "$KUSTOMIZE_DIR"/* "$TEMP_DIR/kustomize/"
    
    # Update kustomization.yaml to point to generated manifests
    cd "$TEMP_DIR/kustomize"
    
    # Replace resources path in kustomization.yaml
    if grep -q "resources:" kustomization.yaml; then
        # Add base manifests to resources
        find "../base" -name "*.yaml" -type f | sed 's|^|../|' | \
            yq eval '.resources += [inputs]' -i kustomization.yaml
    fi
    
    # Apply kustomize transformations
    kustomize build . > "$TEMP_DIR/customized-manifests.yaml"
    
    # Split the customized manifests back into separate files
    cd "$TEMP_DIR"
    mkdir -p split-manifests
    
    # Use yq to split YAML documents
    yq eval-all --split-exp '.kind + "-" + .metadata.name' customized-manifests.yaml
    
    # Move split files to templates directory, ensuring they have .yaml extension
    rm -rf "$TEMPLATES_DIR"
    mkdir -p "$TEMPLATES_DIR"
    
    for file in *.yml; do
        if [ -f "$file" ]; then
            # Convert to lowercase and ensure .yaml extension
            new_name=$(echo "$file" | tr '[:upper:]' '[:lower:]' | sed 's/\.yml$/.yaml/')
            mv "$file" "$TEMPLATES_DIR/$new_name"
        fi
    done
    
    # Clean up
    cd - > /dev/null
    rm -rf "$TEMP_DIR"
    
    echo "✅ Kustomize transformations applied"
fi

# Add additional resources if they exist
if [ -d "$KUSTOMIZE_DIR/resources" ]; then
    echo "📁 Adding additional resources..."
    cp -r "$KUSTOMIZE_DIR/resources"/* "$OUTPUT_DIR/templates/" 2>/dev/null || true
    echo "✅ Additional resources added"
fi

# Validate that templates directory exists and has content
if [ ! -d "$OUTPUT_DIR/templates" ] || [ -z "$(ls -A "$OUTPUT_DIR/templates")" ]; then
    echo "⚠️  No templates found, copying original templates..."
    cp -r "$BASE_CHART_DIR/templates" "$OUTPUT_DIR/"
fi

# Update dependencies if needed
if [ -f "$OUTPUT_DIR/Chart.lock" ]; then
    rm "$OUTPUT_DIR/Chart.lock"
fi

if [ -f "$OUTPUT_DIR/Chart.yaml" ] && yq eval '.dependencies' "$OUTPUT_DIR/Chart.yaml" | grep -q "name:"; then
    echo "📦 Updating chart dependencies..."
    cd "$OUTPUT_DIR"
    helm dependency update
    cd - > /dev/null
fi

echo "✅ Custom chart build completed: $OUTPUT_DIR"