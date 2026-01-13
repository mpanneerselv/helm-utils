#!/bin/bash
set -euo pipefail

# Publish chart to Artifactory
# Usage: ./publish.sh <chart_package_path>

CHART_PACKAGE=$1

echo "🚀 Publishing chart to Artifactory..."

# Check required environment variables
if [ -z "${ARTIFACTORY_URL:-}" ]; then
    echo "❌ ARTIFACTORY_URL environment variable is required"
    exit 1
fi

if [ -z "${ARTIFACTORY_REPO:-}" ]; then
    echo "❌ ARTIFACTORY_REPO environment variable is required"
    exit 1
fi

if [ -z "${ARTIFACTORY_USER:-}" ]; then
    echo "❌ ARTIFACTORY_USER environment variable is required"
    exit 1
fi

if [ -z "${ARTIFACTORY_TOKEN:-}" ]; then
    echo "❌ ARTIFACTORY_TOKEN environment variable is required"
    exit 1
fi

# Validate chart package exists
if [ ! -f "$CHART_PACKAGE" ]; then
    echo "❌ Chart package not found: $CHART_PACKAGE"
    exit 1
fi

# Extract chart name and version from package filename
PACKAGE_NAME=$(basename "$CHART_PACKAGE")
CHART_NAME=$(echo "$PACKAGE_NAME" | sed 's/-[0-9].*//')
CHART_VERSION=$(echo "$PACKAGE_NAME" | sed 's/.*-\([0-9].*\)\.tgz/\1/')

echo "Chart: $CHART_NAME"
echo "Version: $CHART_VERSION"
echo "Package: $PACKAGE_NAME"

# Construct Artifactory URL
UPLOAD_URL="${ARTIFACTORY_URL}/artifactory/${ARTIFACTORY_REPO}/${CHART_NAME}/${PACKAGE_NAME}"

echo "Upload URL: $UPLOAD_URL"

# Upload chart to Artifactory
echo "Uploading chart package..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "${ARTIFACTORY_USER}:${ARTIFACTORY_TOKEN}" \
    -T "$CHART_PACKAGE" \
    "$UPLOAD_URL")

if [ "$HTTP_STATUS" -eq 201 ] || [ "$HTTP_STATUS" -eq 200 ]; then
    echo "✅ Chart uploaded successfully"
else
    echo "❌ Upload failed with HTTP status: $HTTP_STATUS"
    exit 1
fi

# Update repository index
echo "Updating repository index..."
INDEX_URL="${ARTIFACTORY_URL}/artifactory/api/helm/${ARTIFACTORY_REPO}/reindex"

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "${ARTIFACTORY_USER}:${ARTIFACTORY_TOKEN}" \
    -X POST \
    "$INDEX_URL")

if [ "$HTTP_STATUS" -eq 200 ]; then
    echo "✅ Repository index updated successfully"
else
    echo "⚠️  Repository index update failed with HTTP status: $HTTP_STATUS"
    echo "   The chart was uploaded but may not be immediately available"
fi

# Verify upload by checking if chart is available
echo "Verifying chart availability..."
CHART_INFO_URL="${ARTIFACTORY_URL}/artifactory/api/storage/${ARTIFACTORY_REPO}/${CHART_NAME}/${PACKAGE_NAME}"

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "${ARTIFACTORY_USER}:${ARTIFACTORY_TOKEN}" \
    "$CHART_INFO_URL")

if [ "$HTTP_STATUS" -eq 200 ]; then
    echo "✅ Chart verification successful"
else
    echo "⚠️  Chart verification failed - chart may not be immediately available"
fi

# Generate installation instructions
echo ""
echo "📋 Installation instructions:"
echo "helm repo add custom-charts ${ARTIFACTORY_URL}/artifactory/${ARTIFACTORY_REPO}"
echo "helm repo update"
echo "helm install my-mimir custom-charts/${CHART_NAME} --version ${CHART_VERSION}"

echo ""
echo "🎉 Chart published successfully!"