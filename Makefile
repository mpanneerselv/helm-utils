# Mimir Custom Chart Makefile
# Supports both Jenkins pipeline and local development

# Configuration
CHART_NAME := mimir-custom
BASE_CHART_REPO := https://grafana.github.io/helm-charts
BASE_CHART_NAME := mimir-distributed
BASE_CHART_VERSION := 5.4.0

# Versioning
CURRENT_VERSION := $(shell cat VERSION 2>/dev/null || echo "0.1.0")
BUILD_NUMBER ?= 
VERSION_BUMP ?= patch
NEW_VERSION := $(shell ./scripts/semver.sh $(VERSION_BUMP) $(CURRENT_VERSION) $(BUILD_NUMBER))

# Directories
BUILD_DIR := build
CHARTS_DIR := charts
KUSTOMIZE_DIR := kustomize
OUTPUT_DIR := $(BUILD_DIR)/output
PACKAGE_DIR := $(BUILD_DIR)/packages

# Artifactory Configuration
ARTIFACTORY_URL ?= 
ARTIFACTORY_REPO ?= helm-local
ARTIFACTORY_USER ?= 
ARTIFACTORY_TOKEN ?= 

# Git Configuration
GIT_TAG ?= true
GIT_COMMIT_MSG := "Release $(CHART_NAME) version $(NEW_VERSION)"

# Tools
HELM := helm
KUSTOMIZE := kustomize
YQ := yq

.PHONY: help
help: ## Display this help message
	@echo "Mimir Custom Chart Build System"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: clean
clean: ## Clean build artifacts
	@echo "🧹 Cleaning build artifacts..."
	rm -rf $(BUILD_DIR)
	rm -rf $(CHARTS_DIR)/$(BASE_CHART_NAME)
	@echo "✅ Clean completed"

.PHONY: setup
setup: ## Setup development environment
	@echo "🔧 Setting up development environment..."
	@./scripts/setup.sh
	@echo "✅ Setup completed"

.PHONY: deps
deps: ## Download base chart dependencies
	@echo "📦 Downloading base chart dependencies..."
	mkdir -p $(CHARTS_DIR)
	$(HELM) repo add grafana $(BASE_CHART_REPO)
	$(HELM) repo update
	$(HELM) pull grafana/$(BASE_CHART_NAME) --version $(BASE_CHART_VERSION) --untar --untardir $(CHARTS_DIR)
	@echo "✅ Dependencies downloaded"

.PHONY: validate-base
validate-base: deps ## Validate base chart
	@echo "🔍 Validating base chart..."
	$(HELM) lint $(CHARTS_DIR)/$(BASE_CHART_NAME)
	$(HELM) template test $(CHARTS_DIR)/$(BASE_CHART_NAME) --dry-run > /dev/null
	@echo "✅ Base chart validation passed"

.PHONY: build
build: deps ## Build custom chart with kustomizations
	@echo "🏗️  Building custom chart..."
	mkdir -p $(OUTPUT_DIR)
	@./scripts/build-chart.sh $(CHARTS_DIR)/$(BASE_CHART_NAME) $(KUSTOMIZE_DIR) $(OUTPUT_DIR)/$(CHART_NAME)
	@echo "✅ Custom chart built"

.PHONY: validate
validate: build ## Validate custom chart
	@echo "🔍 Validating custom chart..."
	$(HELM) lint $(OUTPUT_DIR)/$(CHART_NAME)
	$(HELM) template test $(OUTPUT_DIR)/$(CHART_NAME) --dry-run > /dev/null
	@./scripts/validate-chart.sh $(OUTPUT_DIR)/$(CHART_NAME)
	@echo "✅ Custom chart validation passed"

.PHONY: test
test: validate ## Run chart tests
	@echo "🧪 Running chart tests..."
	@./scripts/test-chart.sh $(OUTPUT_DIR)/$(CHART_NAME)
	@echo "✅ Chart tests passed"

.PHONY: security-scan
security-scan: build ## Run security scans on chart
	@echo "🔒 Running security scans..."
	@./scripts/security-scan.sh $(OUTPUT_DIR)/$(CHART_NAME)
	@echo "✅ Security scans passed"

.PHONY: version
version: ## Update chart version
	@echo "📝 Updating version from $(CURRENT_VERSION) to $(NEW_VERSION)..."
	echo "$(NEW_VERSION)" > VERSION
	$(YQ) eval '.version = "$(NEW_VERSION)"' -i $(OUTPUT_DIR)/$(CHART_NAME)/Chart.yaml
	@echo "✅ Version updated to $(NEW_VERSION)"

.PHONY: package
package: build version ## Package the custom chart
	@echo "📦 Packaging custom chart..."
	mkdir -p $(PACKAGE_DIR)
	$(HELM) package $(OUTPUT_DIR)/$(CHART_NAME) --destination $(PACKAGE_DIR)
	@echo "✅ Chart packaged: $(PACKAGE_DIR)/$(CHART_NAME)-$(NEW_VERSION).tgz"

.PHONY: publish
publish: package ## Publish chart to Artifactory
	@echo "🚀 Publishing chart to Artifactory..."
	@./scripts/publish.sh $(PACKAGE_DIR)/$(CHART_NAME)-$(NEW_VERSION).tgz
	@echo "✅ Chart published to Artifactory"

.PHONY: tag
tag: ## Tag git commit with chart version
ifeq ($(GIT_TAG),true)
	@echo "🏷️  Tagging git commit..."
	git add VERSION
	git commit -m "$(GIT_COMMIT_MSG)" || true
	git tag -a "v$(NEW_VERSION)" -m "$(GIT_COMMIT_MSG)"
	@echo "✅ Git tagged with v$(NEW_VERSION)"
else
	@echo "⏭️  Git tagging disabled"
endif

.PHONY: release
release: clean validate test security-scan package publish tag ## Full release pipeline
	@echo "🎉 Release $(NEW_VERSION) completed successfully!"

.PHONY: dev-build
dev-build: clean build validate ## Quick development build
	@echo "🔨 Development build completed"

.PHONY: ci-build
ci-build: clean validate test security-scan package ## CI build without publish
	@echo "🤖 CI build completed"

.PHONY: show-version
show-version: ## Show current and next version
	@echo "Current version: $(CURRENT_VERSION)"
	@echo "Next version: $(NEW_VERSION)"

.PHONY: dry-run
dry-run: build ## Dry run chart installation
	@echo "🏃 Running dry-run installation..."
	$(HELM) install --dry-run --debug test-release $(OUTPUT_DIR)/$(CHART_NAME)
	@echo "✅ Dry-run completed"

.PHONY: install-local
install-local: build ## Install chart locally for testing
	@echo "⚡ Installing chart locally..."
	$(HELM) upgrade --install mimir-test $(OUTPUT_DIR)/$(CHART_NAME) \
		--namespace mimir-test --create-namespace \
		--wait --timeout 300s
	@echo "✅ Chart installed locally"

.PHONY: uninstall-local
uninstall-local: ## Uninstall local chart
	@echo "🗑️  Uninstalling local chart..."
	$(HELM) uninstall mimir-test --namespace mimir-test || true
	kubectl delete namespace mimir-test || true
	@echo "✅ Local chart uninstalled"

.PHONY: diff
diff: build ## Show diff between base and custom chart
	@echo "📊 Showing differences..."
	@./scripts/diff-charts.sh $(CHARTS_DIR)/$(BASE_CHART_NAME) $(OUTPUT_DIR)/$(CHART_NAME)

.PHONY: docs
docs: build ## Generate chart documentation
	@echo "📚 Generating documentation..."
	@./scripts/generate-docs.sh $(OUTPUT_DIR)/$(CHART_NAME)
	@echo "✅ Documentation generated"

# Jenkins-specific targets
.PHONY: jenkins-setup
jenkins-setup: setup deps ## Jenkins environment setup

.PHONY: jenkins-build
jenkins-build: ci-build ## Jenkins build pipeline

.PHONY: jenkins-release
jenkins-release: release ## Jenkins release pipeline

# Development helpers
.PHONY: watch
watch: ## Watch for changes and rebuild
	@echo "👀 Watching for changes..."
	@./scripts/watch.sh

.PHONY: shell
shell: ## Open interactive shell in build environment
	@echo "🐚 Opening build shell..."
	@docker run -it --rm -v $(PWD):/workspace -w /workspace alpine/helm:latest sh