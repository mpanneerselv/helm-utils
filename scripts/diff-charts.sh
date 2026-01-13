#!/bin/bash
set -euo pipefail

# Show differences between base and custom chart
# Usage: ./diff-charts.sh <base_chart_dir> <custom_chart_dir>

BASE_CHART_DIR=$1
CUSTOM_CHART_DIR=$2

echo "📊 Showing differences between base and custom chart..."

# Create temporary directories for rendered templates
BASE_TEMP=$(mktemp -d)
CUSTOM_TEMP=$(mktemp -d)

# Render both charts
echo "Rendering base chart..."
helm template base-chart "$BASE_CHART_DIR" --output-dir "$BASE_TEMP" > /dev/null

echo "Rendering custom chart..."
helm template custom-chart "$CUSTOM_CHART_DIR" --output-dir "$CUSTOM_TEMP" > /dev/null

# Compare Chart.yaml files
echo ""
echo "=== Chart.yaml Differences ==="
if diff -u "$BASE_CHART_DIR/Chart.yaml" "$CUSTOM_CHART_DIR/Chart.yaml" || true; then
    echo "No differences in Chart.yaml"
fi

# Compare values.yaml files
echo ""
echo "=== Values.yaml Differences ==="
if diff -u "$BASE_CHART_DIR/values.yaml" "$CUSTOM_CHART_DIR/values.yaml" || true; then
    echo "No differences in values.yaml"
fi

# Compare rendered templates
echo ""
echo "=== Template Differences ==="

# Find all template files in both directories
BASE_TEMPLATES=$(find "$BASE_TEMP" -name "*.yaml" -type f | sort)
CUSTOM_TEMPLATES=$(find "$CUSTOM_TEMP" -name "*.yaml" -type f | sort)

# Compare common files
for base_file in $BASE_TEMPLATES; do
    rel_path=$(echo "$base_file" | sed "s|$BASE_TEMP/||")
    custom_file="$CUSTOM_TEMP/$rel_path"
    
    if [ -f "$custom_file" ]; then
        echo "--- Comparing $rel_path ---"
        if ! diff -u "$base_file" "$custom_file"; then
            echo ""
        fi
    else
        echo "--- File removed: $rel_path ---"
    fi
done

# Find new files in custom chart
for custom_file in $CUSTOM_TEMPLATES; do
    rel_path=$(echo "$custom_file" | sed "s|$CUSTOM_TEMP/||")
    base_file="$BASE_TEMP/$rel_path"
    
    if [ ! -f "$base_file" ]; then
        echo "--- New file: $rel_path ---"
        echo "Content:"
        cat "$custom_file"
        echo ""
    fi
done

# Resource count comparison
echo ""
echo "=== Resource Count Comparison ==="
echo "Base chart resources:"
find "$BASE_TEMP" -name "*.yaml" -exec yq eval '.kind' {} \; 2>/dev/null | sort | uniq -c | sort -nr

echo ""
echo "Custom chart resources:"
find "$CUSTOM_TEMP" -name "*.yaml" -exec yq eval '.kind' {} \; 2>/dev/null | sort | uniq -c | sort -nr

# Cleanup
rm -rf "$BASE_TEMP" "$CUSTOM_TEMP"

echo ""
echo "✅ Diff comparison completed"