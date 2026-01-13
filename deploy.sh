#!/bin/bash

set -euo pipefail

# Mimir Kustomize Deployment Script
# This script orchestrates Helm chart fetching and Kustomize customizations

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-deployment-config.yaml}"
OVERLAY="${OVERLAY:-development}"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Grafana Mimir in distributed mode using Helm charts and Kustomize customizations.

OPTIONS:
    -c, --config FILE       Configuration file (default: deployment-config.yaml)
    -o, --overlay NAME      Overlay environment (default: development)
    -d, --dry-run          Perform a dry run without applying changes
    -v, --verbose          Enable verbose output
    -h, --help             Show this help message

EXAMPLES:
    $0                                          # Deploy development overlay
    $0 -o production                           # Deploy production overlay
    $0 -o staging --dry-run                    # Dry run for staging
    CONFIG_FILE=custom.yaml $0 -o production  # Use custom config file

DIRECTORY STRUCTURE:
    base/                   # Helm-generated base manifests
    overlays/              # Environment-specific overlays
      ├── development/
      ├── staging/
      └── production/
    output/                # Final generated manifests
    charts/                # Cached Helm charts
    values/                # Helm values files

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -o|--overlay)
                OVERLAY="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            -v|--verbose)
                VERBOSE="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Check required tools
check_dependencies() {
    log_info "Checking dependencies..."
    
    local missing_tools=()
    
    if ! command -v helm &> /dev/null; then
        missing_tools+=("helm")
    fi
    
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    if ! command -v kustomize &> /dev/null; then
        missing_tools+=("kustomize")
    fi
    
    if ! command -v yq &> /dev/null; then
        missing_tools+=("yq")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install the missing tools and try again."
        log_info "Installation commands:"
        log_info "  brew install helm kubectl kustomize yq"
        exit 1
    fi
    
    log_success "All dependencies are available"
}

# Load configuration from YAML file
load_config() {
    log_info "Loading configuration from $CONFIG_FILE"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
    
    # Extract Helm configuration
    HELM_REPO=$(yq eval '.spec.helm.chart.repository' "$CONFIG_FILE")
    HELM_CHART=$(yq eval '.spec.helm.chart.name' "$CONFIG_FILE")
    HELM_VERSION=$(yq eval '.spec.helm.chart.version' "$CONFIG_FILE")
    
    # Extract validation configuration
    K8S_VERSION=$(yq eval '.spec.validation.kubernetes_version' "$CONFIG_FILE")
    
    if [ "$VERBOSE" = "true" ]; then
        log_info "Configuration loaded:"
        log_info "  Helm Repository: $HELM_REPO"
        log_info "  Chart Name: $HELM_CHART"
        log_info "  Chart Version: $HELM_VERSION"
        log_info "  Kubernetes Version: $K8S_VERSION"
        log_info "  Target Overlay: $OVERLAY"
    fi
}

# Create directory structure
create_directories() {
    log_info "Creating directory structure..."
    
    mkdir -p base
    mkdir -p overlays/{development,staging,production}
    mkdir -p output/{development,staging,production}
    mkdir -p charts
    mkdir -p values
    
    log_success "Directory structure created"
}

# Add Helm repository and fetch chart
fetch_helm_chart() {
    log_info "Fetching Helm chart: $HELM_CHART:$HELM_VERSION"
    
    # Add Helm repository
    local repo_name="grafana"
    helm repo add "$repo_name" "$HELM_REPO" --force-update
    helm repo update
    
    # Pull chart to local directory
    helm pull "$repo_name/$HELM_CHART" \
        --version "$HELM_VERSION" \
        --untar \
        --untardir charts/
    
    log_success "Helm chart fetched successfully"
}

# Generate base manifests from Helm chart
generate_base_manifests() {
    log_info "Generating base manifests from Helm chart..."
    
    # Clean previous base manifests
    rm -rf base/*
    
    # Collect values files
    local values_args=()
    if [ -f "values/base.yaml" ]; then
        values_args+=("-f" "values/base.yaml")
    fi
    if [ -f "values/distributed-mode.yaml" ]; then
        values_args+=("-f" "values/distributed-mode.yaml")
    fi
    
    # Generate manifests
    helm template mimir "charts/$HELM_CHART" \
        --namespace mimir-system \
        --create-namespace \
        "${values_args[@]}" \
        --output-dir base/
    
    # Move manifests to base directory root and create kustomization.yaml
    if [ -d "base/$HELM_CHART" ]; then
        mv base/$HELM_CHART/templates/* base/ 2>/dev/null || true
        rmdir base/$HELM_CHART/templates 2>/dev/null || true
        rmdir base/$HELM_CHART 2>/dev/null || true
    fi
    
    # Create base kustomization.yaml
    create_base_kustomization
    
    log_success "Base manifests generated"
}

# Create base kustomization.yaml
create_base_kustomization() {
    log_info "Creating base kustomization.yaml..."
    
    cat > base/kustomization.yaml << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

metadata:
  name: mimir-base
  annotations:
    mimir-deployment/source: "helm"
    mimir-deployment/chart-version: "$HELM_VERSION"
    mimir-deployment/generated-at: "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

resources:
EOF
    
    # Add all YAML files in base directory to resources
    find base -name "*.yaml" -not -name "kustomization.yaml" -exec basename {} \; | sort >> base/kustomization.yaml
    
    # Add common labels
    cat >> base/kustomization.yaml << EOF

commonLabels:
  mimir-deployment/managed-by: "kustomize"
  mimir-deployment/component: "mimir"

commonAnnotations:
  mimir-deployment/source: "helm"
  mimir-deployment/chart-version: "$HELM_VERSION"
EOF
}

# Validate overlay exists
validate_overlay() {
    log_info "Validating overlay: $OVERLAY"
    
    if [ ! -d "overlays/$OVERLAY" ]; then
        log_error "Overlay directory not found: overlays/$OVERLAY"
        log_info "Available overlays:"
        ls -1 overlays/ 2>/dev/null || log_info "  No overlays found"
        exit 1
    fi
    
    if [ ! -f "overlays/$OVERLAY/kustomization.yaml" ]; then
        log_warn "No kustomization.yaml found in overlays/$OVERLAY"
        log_info "Creating basic kustomization.yaml for $OVERLAY overlay"
        create_overlay_kustomization
    fi
    
    log_success "Overlay validated: $OVERLAY"
}

# Create overlay kustomization.yaml if it doesn't exist
create_overlay_kustomization() {
    cat > "overlays/$OVERLAY/kustomization.yaml" << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

metadata:
  name: mimir-$OVERLAY
  annotations:
    mimir-deployment/overlay: "$OVERLAY"
    mimir-deployment/generated-at: "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

resources:
  - ../../base

namePrefix: $OVERLAY-

commonLabels:
  mimir-deployment/environment: "$OVERLAY"

# Add patches, resources, and other customizations here
# patchesStrategicMerge:
#   - patches/resources.yaml
# 
# patchesJson6902:
#   - target:
#       group: apps
#       version: v1
#       kind: Deployment
#       name: mimir-ingester
#     path: patches/ingester-affinity.yaml
#
# resources:
#   - resources/additional-config.yaml
#
# images:
#   - name: grafana/mimir
#     newTag: "2.12.0"
EOF
}

# Apply Kustomize transformations
apply_kustomize_transformations() {
    log_info "Applying Kustomize transformations for overlay: $OVERLAY"
    
    # Clean previous output
    rm -rf "output/$OVERLAY"/*
    mkdir -p "output/$OVERLAY"
    
    # Build with Kustomize
    if [ "$DRY_RUN" = "true" ]; then
        log_info "Dry run mode - generating manifests without writing to files"
        kustomize build "overlays/$OVERLAY" | head -50
        log_info "... (output truncated in dry-run mode)"
    else
        kustomize build "overlays/$OVERLAY" > "output/$OVERLAY/manifests.yaml"
        
        # Split into individual files for better organization
        split_manifests "output/$OVERLAY/manifests.yaml" "output/$OVERLAY"
    fi
    
    log_success "Kustomize transformations applied"
}

# Split combined manifest into individual files
split_manifests() {
    local input_file="$1"
    local output_dir="$2"
    
    log_info "Splitting manifests into individual files..."
    
    # Use yq to split the manifests
    local counter=0
    while IFS= read -r doc; do
        if [ -n "$doc" ] && [ "$doc" != "---" ]; then
            local kind=$(echo "$doc" | yq eval '.kind' -)
            local name=$(echo "$doc" | yq eval '.metadata.name' -)
            
            if [ "$kind" != "null" ] && [ "$name" != "null" ]; then
                local filename="${kind,,}-${name}.yaml"
                echo "$doc" > "$output_dir/$filename"
                ((counter++))
            fi
        fi
    done < <(yq eval-all '. as $item ireduce ({}; . * $item)' "$input_file" -s '---')
    
    log_info "Split into $counter individual manifest files"
}

# Validate generated manifests
validate_manifests() {
    log_info "Validating generated manifests..."
    
    local manifest_dir="output/$OVERLAY"
    local validation_errors=0
    
    # Check if manifests directory exists and has files
    if [ ! -d "$manifest_dir" ] || [ -z "$(ls -A "$manifest_dir" 2>/dev/null)" ]; then
        log_error "No manifests found in $manifest_dir"
        return 1
    fi
    
    # Validate each manifest file
    for manifest in "$manifest_dir"/*.yaml; do
        if [ -f "$manifest" ]; then
            if ! kubectl --dry-run=client apply -f "$manifest" &>/dev/null; then
                log_warn "Validation failed for: $(basename "$manifest")"
                ((validation_errors++))
            elif [ "$VERBOSE" = "true" ]; then
                log_info "✓ Valid: $(basename "$manifest")"
            fi
        fi
    done
    
    if [ $validation_errors -eq 0 ]; then
        log_success "All manifests validated successfully"
    else
        log_warn "$validation_errors manifest(s) failed validation"
    fi
    
    # Count manifests and components
    local manifest_count=$(find "$manifest_dir" -name "*.yaml" -type f | wc -l)
    local deployment_count=$(grep -l "kind: Deployment" "$manifest_dir"/*.yaml 2>/dev/null | wc -l)
    
    log_info "Generated $manifest_count manifest files with $deployment_count deployments"
}

# Validate distributed mode components
validate_distributed_mode() {
    log_info "Validating distributed mode components..."
    
    local manifest_dir="output/$OVERLAY"
    local required_components=("ingester" "distributor" "querier" "query-frontend" "compactor" "store-gateway")
    local missing_components=()
    
    for component in "${required_components[@]}"; do
        if ! find "$manifest_dir" -name "*.yaml" -exec grep -l "mimir-$component" {} \; | head -1 | grep -q .; then
            missing_components+=("$component")
        fi
    done
    
    if [ ${#missing_components[@]} -eq 0 ]; then
        log_success "All required distributed mode components found"
    else
        log_warn "Missing distributed mode components: ${missing_components[*]}"
    fi
}

# Main deployment function
main() {
    log_info "Starting Mimir Kustomize Deployment"
    log_info "Overlay: $OVERLAY | Dry Run: $DRY_RUN | Config: $CONFIG_FILE"
    
    # Execute deployment pipeline
    check_dependencies
    load_config
    create_directories
    fetch_helm_chart
    generate_base_manifests
    validate_overlay
    apply_kustomize_transformations
    
    if [ "$DRY_RUN" != "true" ]; then
        validate_manifests
        validate_distributed_mode
        
        log_success "Deployment completed successfully!"
        log_info "Generated manifests are available in: output/$OVERLAY/"
        log_info ""
        log_info "To apply to Kubernetes cluster:"
        log_info "  kubectl apply -f output/$OVERLAY/"
        log_info ""
        log_info "To view generated manifests:"
        log_info "  ls -la output/$OVERLAY/"
    else
        log_success "Dry run completed successfully!"
    fi
}

# Parse arguments and run main function
parse_args "$@"
main