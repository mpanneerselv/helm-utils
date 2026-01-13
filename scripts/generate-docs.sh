#!/bin/bash
set -euo pipefail

# Generate chart documentation
# Usage: ./generate-docs.sh <chart_dir>

CHART_DIR=$1
DOCS_DIR="docs"

echo "📚 Generating chart documentation..."

mkdir -p "$DOCS_DIR"

# Generate README.md
cat > "$DOCS_DIR/README.md" << 'EOF'
# Mimir Custom Chart

This is a customized version of the official Grafana Mimir Helm chart with additional features and optimizations.

## Overview

The Mimir Custom chart extends the official Mimir distributed chart with:
- Enhanced resource configurations
- Custom monitoring and alerting
- Security hardening
- Performance optimizations
- Additional operational tools

## Installation

### Prerequisites

- Kubernetes 1.20+
- Helm 3.8+
- Persistent Volume provisioner support in the underlying infrastructure

### Add Helm Repository

```bash
helm repo add custom-charts <ARTIFACTORY_URL>/artifactory/<REPO_NAME>
helm repo update
```

### Install Chart

```bash
helm install mimir-custom custom-charts/mimir-custom
```

### Upgrade Chart

```bash
helm upgrade mimir-custom custom-charts/mimir-custom
```

### Uninstall Chart

```bash
helm uninstall mimir-custom
```

## Configuration

The following table lists the configurable parameters and their default values.

EOF

# Extract values and generate documentation
if command -v helm-docs &> /dev/null; then
    echo "Using helm-docs to generate values documentation..."
    helm-docs --chart-search-root="$CHART_DIR" --output-file="$DOCS_DIR/VALUES.md"
else
    echo "Generating basic values documentation..."
    
    cat >> "$DOCS_DIR/README.md" << 'EOF'
### Key Configuration Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `mimir.ingester.replicas` | Number of ingester replicas | `3` |
| `mimir.distributor.replicas` | Number of distributor replicas | `2` |
| `mimir.querier.replicas` | Number of querier replicas | `2` |
| `mimir.structuredConfig.common.storage.backend` | Storage backend | `s3` |
| `nginx.ingress.enabled` | Enable ingress | `true` |
| `serviceMonitor.enabled` | Enable Prometheus monitoring | `true` |
| `networkPolicy.enabled` | Enable network policies | `true` |

For a complete list of configuration options, see the [values.yaml](../values.yaml) file.

EOF
fi

# Generate architecture documentation
cat >> "$DOCS_DIR/README.md" << 'EOF'

## Architecture

The Mimir Custom chart deploys the following components:

### Core Components

- **Ingester**: Stores incoming time series data
- **Distributor**: Receives and distributes incoming samples
- **Querier**: Handles read queries
- **Query Frontend**: Provides query optimization and caching
- **Compactor**: Compacts and deduplicates blocks
- **Store Gateway**: Provides access to historical data

### Additional Components

- **Nginx Gateway**: Provides unified API endpoint
- **Monitoring**: ServiceMonitor and PrometheusRule resources
- **Network Policies**: Security policies for network traffic
- **Custom ConfigMaps**: Additional configuration and overrides

## Monitoring

The chart includes comprehensive monitoring setup:

- ServiceMonitor for Prometheus scraping
- Custom alerting rules
- Grafana dashboard configurations
- Performance metrics collection

## Security

Security features included:

- Network policies for traffic isolation
- Pod security contexts
- Resource limits and requests
- Non-root container execution
- Security scanning integration

## Troubleshooting

### Common Issues

1. **Ingester pods not starting**
   - Check persistent volume availability
   - Verify resource limits
   - Check node affinity rules

2. **High memory usage**
   - Adjust ingester memory limits
   - Review retention policies
   - Check compaction settings

3. **Query performance issues**
   - Scale querier replicas
   - Optimize query patterns
   - Review store gateway configuration

### Useful Commands

```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/name=mimir

# View logs
kubectl logs -l app.kubernetes.io/component=ingester

# Check metrics
kubectl port-forward svc/mimir-nginx 8080:80
curl http://localhost:8080/metrics

# Validate configuration
helm template mimir-custom . --dry-run
```

## Development

### Building Custom Chart

```bash
# Setup development environment
make setup

# Download dependencies
make deps

# Build custom chart
make build

# Validate chart
make validate

# Run tests
make test
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## License

This chart is licensed under the Apache 2.0 License.

EOF

# Generate values documentation
echo "Generating values documentation..."
cat > "$DOCS_DIR/VALUES.md" << 'EOF'
# Configuration Values

This document describes all configuration values available in the Mimir Custom chart.

## Global Configuration

### Global Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `global.podAnnotations` | object | `{}` | Annotations to add to all pods |
| `global.podLabels` | object | `{}` | Labels to add to all pods |

## Mimir Configuration

### Core Components

#### Ingester

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `mimir.ingester.replicas` | int | `3` | Number of ingester replicas |
| `mimir.ingester.resources.requests.cpu` | string | `"1000m"` | CPU request |
| `mimir.ingester.resources.requests.memory` | string | `"4Gi"` | Memory request |
| `mimir.ingester.resources.limits.cpu` | string | `"2000m"` | CPU limit |
| `mimir.ingester.resources.limits.memory` | string | `"8Gi"` | Memory limit |
| `mimir.ingester.persistentVolume.size` | string | `"100Gi"` | Persistent volume size |

#### Distributor

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `mimir.distributor.replicas` | int | `2` | Number of distributor replicas |
| `mimir.distributor.resources.requests.cpu` | string | `"500m"` | CPU request |
| `mimir.distributor.resources.requests.memory` | string | `"1Gi"` | Memory request |

#### Querier

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `mimir.querier.replicas` | int | `2` | Number of querier replicas |
| `mimir.querier.resources.requests.cpu` | string | `"500m"` | CPU request |
| `mimir.querier.resources.requests.memory` | string | `"1Gi"` | Memory request |

### Storage Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `mimir.structuredConfig.common.storage.backend` | string | `"s3"` | Storage backend type |
| `mimir.structuredConfig.common.storage.s3.bucket_name` | string | `"mimir-blocks-custom"` | S3 bucket name |
| `mimir.structuredConfig.common.storage.s3.endpoint` | string | `"s3.amazonaws.com"` | S3 endpoint |

## Monitoring Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `serviceMonitor.enabled` | bool | `true` | Enable ServiceMonitor |
| `serviceMonitor.interval` | string | `"30s"` | Scrape interval |
| `serviceMonitor.scrapeTimeout` | string | `"10s"` | Scrape timeout |

## Security Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `securityContext.runAsNonRoot` | bool | `true` | Run as non-root user |
| `securityContext.runAsUser` | int | `10001` | User ID |
| `securityContext.runAsGroup` | int | `10001` | Group ID |
| `networkPolicy.enabled` | bool | `true` | Enable network policies |

## Ingress Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `nginx.ingress.enabled` | bool | `true` | Enable ingress |
| `nginx.ingress.ingressClassName` | string | `"nginx"` | Ingress class name |
| `nginx.ingress.hosts[0].host` | string | `"mimir.example.com"` | Hostname |

EOF

# Generate changelog
echo "Generating changelog..."
cat > "$DOCS_DIR/CHANGELOG.md" << 'EOF'
# Changelog

All notable changes to the Mimir Custom chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial custom chart implementation
- Enhanced resource configurations
- Custom monitoring and alerting
- Security hardening features
- Performance optimizations
- Network policies
- Custom ConfigMaps and overrides

### Changed
- Updated base chart to mimir-distributed 5.4.0
- Enhanced ingester resource allocation
- Improved distributor auto-scaling

### Security
- Added pod security contexts
- Implemented network policies
- Enhanced container security scanning

## [0.1.0] - 2025-01-13

### Added
- Initial release of Mimir Custom chart
- Based on official mimir-distributed chart version 5.4.0
- Custom kustomizations and enhancements
- Comprehensive documentation
- Automated build and release pipeline

EOF

echo "✅ Documentation generated in $DOCS_DIR/"
echo ""
echo "Generated files:"
echo "- $DOCS_DIR/README.md"
echo "- $DOCS_DIR/VALUES.md"
echo "- $DOCS_DIR/CHANGELOG.md"