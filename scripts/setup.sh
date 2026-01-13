#!/bin/bash
set -euo pipefail

# Setup script for Mimir custom chart development environment

echo "🔧 Setting up Mimir custom chart development environment..."

# Check required tools
check_tool() {
    if ! command -v "$1" &> /dev/null; then
        echo "❌ $1 is not installed. Please install it first."
        exit 1
    else
        echo "✅ $1 is available"
    fi
}

echo "Checking required tools..."
check_tool helm
check_tool kustomize
check_tool yq
check_tool git

# Verify tool versions
echo ""
echo "Tool versions:"
echo "Helm: $(helm version --short)"
echo "Kustomize: $(kustomize version --short)"
echo "yq: $(yq --version)"
echo "Git: $(git --version)"

# Create directory structure
echo ""
echo "Creating directory structure..."
mkdir -p charts
mkdir -p kustomize/{base,overlays,patches,resources}
mkdir -p build/{output,packages}
mkdir -p scripts
mkdir -p docs
mkdir -p tests

# Create .gitignore if it doesn't exist
if [ ! -f .gitignore ]; then
    cat > .gitignore << 'EOF'
# Build artifacts
build/
charts/mimir-distributed/

# Helm
*.tgz

# IDE
.vscode/
.idea/

# OS
.DS_Store
Thumbs.db

# Temporary files
*.tmp
*.temp
EOF
    echo "✅ Created .gitignore"
fi

# Initialize git if not already initialized
if [ ! -d .git ]; then
    git init
    echo "✅ Initialized git repository"
fi

echo ""
echo "🎉 Setup completed successfully!"
echo ""
echo "Next steps:"
echo "1. Run 'make deps' to download base chart"
echo "2. Customize kustomize configurations"
echo "3. Run 'make build' to build custom chart"