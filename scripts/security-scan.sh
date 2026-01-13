#!/bin/bash
set -euo pipefail

# Security scanning script for Helm charts
# Usage: ./security-scan.sh <chart_dir>

CHART_DIR=$1

echo "🔒 Running security scans..."

# Render templates for analysis
TEMP_OUTPUT=$(mktemp)
helm template security-test "$CHART_DIR" > "$TEMP_OUTPUT"

# Security check functions
check_privileged_containers() {
    echo "Checking for privileged containers..."
    if yq eval 'select(.kind == "Deployment" or .kind == "StatefulSet") | .spec.template.spec.containers[] | select(.securityContext.privileged == true)' "$TEMP_OUTPUT" | grep -q "."; then
        echo "❌ Found privileged containers"
        return 1
    fi
    echo "✅ No privileged containers found"
}

check_root_users() {
    echo "Checking for containers running as root..."
    if yq eval 'select(.kind == "Deployment" or .kind == "StatefulSet") | .spec.template.spec.containers[] | select(.securityContext.runAsUser == 0)' "$TEMP_OUTPUT" | grep -q "."; then
        echo "⚠️  Found containers running as root"
    else
        echo "✅ No containers running as root"
    fi
}

check_host_network() {
    echo "Checking for host network usage..."
    if yq eval 'select(.kind == "Deployment" or .kind == "StatefulSet") | select(.spec.template.spec.hostNetwork == true)' "$TEMP_OUTPUT" | grep -q "."; then
        echo "❌ Found pods using host network"
        return 1
    fi
    echo "✅ No host network usage found"
}

check_host_pid() {
    echo "Checking for host PID usage..."
    if yq eval 'select(.kind == "Deployment" or .kind == "StatefulSet") | select(.spec.template.spec.hostPID == true)' "$TEMP_OUTPUT" | grep -q "."; then
        echo "❌ Found pods using host PID"
        return 1
    fi
    echo "✅ No host PID usage found"
}

check_capabilities() {
    echo "Checking for container capabilities..."
    
    # Check for dangerous capabilities
    dangerous_caps=("SYS_ADMIN" "NET_ADMIN" "SYS_TIME" "SYS_MODULE")
    
    for cap in "${dangerous_caps[@]}"; do
        if yq eval 'select(.kind == "Deployment" or .kind == "StatefulSet") | .spec.template.spec.containers[] | .securityContext.capabilities.add[]? | select(. == "'$cap'")' "$TEMP_OUTPUT" | grep -q "."; then
            echo "❌ Found dangerous capability: $cap"
            return 1
        fi
    done
    
    # Check that capabilities are dropped (should have "drop: [ALL]")
    containers_without_drop_all=$(yq eval 'select(.kind == "Deployment" or .kind == "StatefulSet") | .spec.template.spec.containers[] | select(.securityContext.capabilities.drop == null or (.securityContext.capabilities.drop | contains(["ALL"]) | not)) | .name' "$TEMP_OUTPUT")
    
    if [ -n "$containers_without_drop_all" ]; then
        echo "❌ Containers without 'drop: [ALL]' capabilities:"
        echo "$containers_without_drop_all"
        return 1
    fi
    
    echo "✅ All containers have proper capability configuration (drop: [ALL])"
}

check_container_security_context() {
    echo "Checking container security contexts..."
    
    # Check for readOnlyRootFilesystem
    containers_without_readonly_fs=$(yq eval 'select(.kind == "Deployment" or .kind == "StatefulSet") | .spec.template.spec.containers[] | select(.securityContext.readOnlyRootFilesystem != true) | .name' "$TEMP_OUTPUT")
    
    if [ -n "$containers_without_readonly_fs" ]; then
        echo "❌ Containers without readOnlyRootFilesystem: true:"
        echo "$containers_without_readonly_fs"
        return 1
    fi
    
    # Check for allowPrivilegeEscalation: false
    containers_with_privilege_escalation=$(yq eval 'select(.kind == "Deployment" or .kind == "StatefulSet") | .spec.template.spec.containers[] | select(.securityContext.allowPrivilegeEscalation != false) | .name' "$TEMP_OUTPUT")
    
    if [ -n "$containers_with_privilege_escalation" ]; then
        echo "❌ Containers without allowPrivilegeEscalation: false:"
        echo "$containers_with_privilege_escalation"
        return 1
    fi
    
    echo "✅ All containers have proper security context (readOnlyRootFilesystem: true, allowPrivilegeEscalation: false)"
}

check_resource_limits() {
    echo "Checking for missing resource limits..."
    containers_without_limits=$(yq eval 'select(.kind == "Deployment" or .kind == "StatefulSet") | .spec.template.spec.containers[] | select(.resources.limits == null) | .name' "$TEMP_OUTPUT")
    
    if [ -n "$containers_without_limits" ]; then
        echo "⚠️  Containers without resource limits:"
        echo "$containers_without_limits"
    else
        echo "✅ All containers have resource limits"
    fi
}

check_secrets_in_env() {
    echo "Checking for secrets in environment variables..."
    if yq eval 'select(.kind == "Deployment" or .kind == "StatefulSet") | .spec.template.spec.containers[] | .env[]? | select(.value | test("password|secret|key|token"; "i"))' "$TEMP_OUTPUT" | grep -q "."; then
        echo "⚠️  Found potential secrets in environment variables"
    else
        echo "✅ No secrets found in environment variables"
    fi
}

check_pod_security_context() {
    echo "Checking pod security contexts..."
    
    # Check for runAsNonRoot
    pods_without_run_as_non_root=$(yq eval 'select(.kind == "Deployment" or .kind == "StatefulSet") | select(.spec.template.spec.securityContext.runAsNonRoot != true) | .metadata.name' "$TEMP_OUTPUT")
    
    if [ -n "$pods_without_run_as_non_root" ]; then
        echo "❌ Pods without runAsNonRoot: true:"
        echo "$pods_without_run_as_non_root"
        return 1
    fi
    
    # Check for runAsUser
    pods_without_run_as_user=$(yq eval 'select(.kind == "Deployment" or .kind == "StatefulSet") | select(.spec.template.spec.securityContext.runAsUser == null) | .metadata.name' "$TEMP_OUTPUT")
    
    if [ -n "$pods_without_run_as_user" ]; then
        echo "❌ Pods without runAsUser defined:"
        echo "$pods_without_run_as_user"
        return 1
    fi
    
    # Check for runAsGroup
    pods_without_run_as_group=$(yq eval 'select(.kind == "Deployment" or .kind == "StatefulSet") | select(.spec.template.spec.securityContext.runAsGroup == null) | .metadata.name' "$TEMP_OUTPUT")
    
    if [ -n "$pods_without_run_as_group" ]; then
        echo "❌ Pods without runAsGroup defined:"
        echo "$pods_without_run_as_group"
        return 1
    fi
    
    # Check for fsGroup
    pods_without_fs_group=$(yq eval 'select(.kind == "Deployment" or .kind == "StatefulSet") | select(.spec.template.spec.securityContext.fsGroup == null) | .metadata.name' "$TEMP_OUTPUT")
    
    if [ -n "$pods_without_fs_group" ]; then
        echo "❌ Pods without fsGroup defined:"
        echo "$pods_without_fs_group"
        return 1
    fi
    
    echo "✅ All pods have complete security context (runAsNonRoot, runAsUser, runAsGroup, fsGroup)"
}

check_image_tags() {
    echo "Checking for image tags..."
    if yq eval 'select(.kind == "Deployment" or .kind == "StatefulSet") | .spec.template.spec.containers[] | .image | select(test(":latest$"))' "$TEMP_OUTPUT" | grep -q "."; then
        echo "⚠️  Found images using 'latest' tag"
    fi
    
    if yq eval 'select(.kind == "Deployment" or .kind == "StatefulSet") | .spec.template.spec.containers[] | .image | select(test(":[^:]*$") | not)' "$TEMP_OUTPUT" | grep -q "."; then
        echo "⚠️  Found images without explicit tags"
    fi
    
    echo "✅ Image tag check completed"
}

check_pod_security_context_legacy() {
    echo "Checking legacy pod security contexts..."
    pods_without_security_context=$(yq eval 'select(.kind == "Deployment" or .kind == "StatefulSet") | select(.spec.template.spec.securityContext == null) | .metadata.name' "$TEMP_OUTPUT")
    
    if [ -n "$pods_without_security_context" ]; then
        echo "⚠️  Pods without any security context:"
        echo "$pods_without_security_context"
    else
        echo "✅ All pods have security context defined"
    fi
}

check_service_accounts() {
    echo "Checking service accounts..."
    default_sa_usage=$(yq eval 'select(.kind == "Deployment" or .kind == "StatefulSet") | select(.spec.template.spec.serviceAccountName == "default" or .spec.template.spec.serviceAccountName == null) | .metadata.name' "$TEMP_OUTPUT")
    
    if [ -n "$default_sa_usage" ]; then
        echo "⚠️  Pods using default service account:"
        echo "$default_sa_usage"
    else
        echo "✅ All pods use custom service accounts"
    fi
}

# Run all security checks
security_issues=0

check_privileged_containers || ((security_issues++))
check_root_users
check_host_network || ((security_issues++))
check_host_pid || ((security_issues++))
check_capabilities || ((security_issues++))
check_container_security_context || ((security_issues++))
check_resource_limits
check_secrets_in_env
check_pod_security_context || ((security_issues++))
check_image_tags
check_pod_security_context_legacy
check_service_accounts

# Additional security recommendations
echo ""
echo "Security recommendations:"
echo "1. Use specific image tags instead of 'latest'"
echo "2. Implement NetworkPolicies for network segmentation (if needed)"
echo "3. Use non-root users in containers"
echo "4. Set resource limits for all containers"
echo "5. Use dedicated service accounts"
echo "6. Enable Pod Security Standards"
echo "7. Regularly scan images for vulnerabilities"
echo "8. Ensure all containers have readOnlyRootFilesystem: true"
echo "9. Drop all capabilities and add only required ones"
echo "10. Set allowPrivilegeEscalation: false for all containers"

# Cleanup
rm "$TEMP_OUTPUT"

if [ $security_issues -gt 0 ]; then
    echo ""
    echo "❌ Security scan completed with $security_issues critical issues"
    exit 1
else
    echo ""
    echo "✅ Security scan completed successfully"
fi