#!/bin/bash
set -euo pipefail

# Semantic versioning script
# Usage: ./semver.sh <bump_type> <current_version> [build_number]
# bump_type: major, minor, patch
# current_version: x.y.z format
# build_number: optional build number to append

BUMP_TYPE=${1:-patch}
CURRENT_VERSION=${2:-0.1.0}
BUILD_NUMBER=${3:-}

# Parse current version
if [[ ! $CURRENT_VERSION =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "Error: Invalid version format. Expected x.y.z" >&2
    exit 1
fi

MAJOR=${BASH_REMATCH[1]}
MINOR=${BASH_REMATCH[2]}
PATCH=${BASH_REMATCH[3]}

# Increment version based on bump type
case $BUMP_TYPE in
    major)
        MAJOR=$((MAJOR + 1))
        MINOR=0
        PATCH=0
        ;;
    minor)
        MINOR=$((MINOR + 1))
        PATCH=0
        ;;
    patch)
        PATCH=$((PATCH + 1))
        ;;
    *)
        echo "Error: Invalid bump type. Use major, minor, or patch" >&2
        exit 1
        ;;
esac

NEW_VERSION="$MAJOR.$MINOR.$PATCH"

# Append build number if provided
if [ -n "$BUILD_NUMBER" ]; then
    NEW_VERSION="$NEW_VERSION-build.$BUILD_NUMBER"
fi

echo "$NEW_VERSION"