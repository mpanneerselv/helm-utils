# Mimir Custom Helm Chart

A customized version of the official Grafana Mimir Helm chart with enhanced features, security hardening, and operational improvements.

## 🚀 Features

- **Enhanced Resource Management**: Optimized resource allocations and auto-scaling
- **Security Hardening**: Pod security contexts, network policies, and security scanning
- **Advanced Monitoring**: Custom ServiceMonitor, PrometheusRules, and alerting
- **Performance Tuning**: Optimized configurations for production workloads
- **Operational Tools**: Comprehensive validation, testing, and deployment automation
- **GitOps Ready**: Clean separation between base charts and customizations

## 📋 Prerequisites

- Kubernetes 1.20+
- Helm 3.8+
- Kustomize 5.0+
- yq 4.30+

## 🛠️ Quick Start

### 1. Setup Development Environment

```bash
# Clone the repository
git clone <repository-url>
cd mimir-custom-chart

# Setup development environment
make setup

# Download base chart dependencies
make deps
```

### 2. Build Custom Chart

```bash
# Build the custom chart
make build

# Validate the chart
make validate

# Run tests
make test
```

### 3. Package and Deploy

```bash
# Package the chart
make package

# Install locally for testing
make install-local

# Clean up local installation
make uninstall-local
```

## 🔧 Customization

### Values Override

Customize the chart by modifying `kustomize/values-override.yaml`:

```yaml
mimir:
  ingester:
    replicas: 3
    resources:
      requests:
        cpu: 1000m
        memory: 4Gi
  
  structuredConfig:
    common:
      storage:
        backend: s3
        s3:
          bucket_name: your-mimir-bucket
```

### Kustomize Patches

Add custom patches in the `kustomize/patches/` directory:

- `ingester-resources.yaml` - Resource and affinity configurations
- `distributor-hpa.yaml` - Horizontal Pod Autoscaler settings
- `compactor-config.yaml` - Compactor optimizations

### Additional Resources

Add new Kubernetes resources in `kustomize/resources/`:

- `monitoring-servicemonitor.yaml` - Prometheus monitoring
- `custom-configmap.yaml` - Additional configurations
- `network-policy.yaml` - Network security policies

## 📊 Makefile Targets

### Development Targets

| Target | Description |
|--------|-------------|
| `make setup` | Setup development environment |
| `make deps` | Download base chart dependencies |
| `make build` | Build custom chart |
| `make validate` | Validate chart configuration |
| `make test` | Run chart tests |
| `make dev-build` | Quick development build |

### Validation Targets

| Target | Description |
|--------|-------------|
| `make validate-base` | Validate base chart |
| `make security-scan` | Run security scans |
| `make dry-run` | Dry run chart installation |
| `make diff` | Show differences from base chart |

### Release Targets

| Target | Description |
|--------|-------------|
| `make version` | Update chart version |
| `make package` | Package the chart |
| `make publish` | Publish to Artifactory |
| `make tag` | Tag git commit |
| `make release` | Full release pipeline |

### CI/CD Targets

| Target | Description |
|--------|-------------|
| `make jenkins-setup` | Jenkins environment setup |
| `make jenkins-build` | Jenkins build pipeline |
| `make jenkins-release` | Jenkins release pipeline |
| `make ci-build` | CI build without publish |

### Utility Targets

| Target | Description |
|--------|-------------|
| `make clean` | Clean build artifacts |
| `make docs` | Generate documentation |
| `make watch` | Watch for changes and rebuild |
| `make shell` | Open build environment shell |

## 🔄 Version Management

The chart uses semantic versioning with automatic version bumping:

```bash
# Patch version (0.1.0 -> 0.1.1)
make package VERSION_BUMP=patch

# Minor version (0.1.0 -> 0.2.0)
make package VERSION_BUMP=minor

# Major version (0.1.0 -> 1.0.0)
make package VERSION_BUMP=major

# With build number
make package BUILD_NUMBER=123
```

## 🏗️ CI/CD Pipeline

### Jenkins Pipeline

The included Jenkinsfile provides:

- Automated building and testing
- Security scanning
- Version management
- Artifactory publishing
- Git tagging
- Slack notifications

### Environment Variables

Configure these environment variables for CI/CD:

```bash
# Artifactory Configuration
ARTIFACTORY_URL=https://your-artifactory.com
ARTIFACTORY_REPO=helm-local
ARTIFACTORY_USER=your-username
ARTIFACTORY_TOKEN=your-token

# Version Management
VERSION_BUMP=patch  # patch, minor, major
BUILD_NUMBER=123    # Optional build number
GIT_TAG=true        # Enable git tagging
```

## 🔒 Security

### Security Features

- **Pod Security Contexts**: Non-root execution, security profiles
- **Network Policies**: Traffic isolation and ingress/egress rules
- **Resource Limits**: CPU and memory constraints
- **Security Scanning**: Automated vulnerability detection
- **Image Security**: Specific image tags, no latest tags

### Security Scanning

```bash
# Run comprehensive security scan
make security-scan

# Check for specific security issues
helm template test build/output/mimir-custom | \
  yq eval 'select(.kind == "Deployment") | .spec.template.spec.securityContext'
```

## 📈 Monitoring

### Prometheus Integration

The chart includes:

- **ServiceMonitor**: Automatic metrics scraping
- **PrometheusRule**: Custom alerting rules
- **Grafana Dashboards**: Performance monitoring

### Custom Alerts

Key alerts included:

- Component availability (ingester, distributor, querier)
- High ingestion rates
- Resource utilization
- Performance degradation

## 🐛 Troubleshooting

### Common Issues

1. **Build Failures**
   ```bash
   # Check dependencies
   make deps
   
   # Validate base chart
   make validate-base
   
   # Check kustomize syntax
   kustomize build kustomize/
   ```

2. **Test Failures**
   ```bash
   # Run specific test scenario
   helm template test build/output/mimir-custom -f ci/minimal-values.yaml
   
   # Check resource requirements
   make security-scan
   ```

3. **Deployment Issues**
   ```bash
   # Dry run installation
   make dry-run
   
   # Check differences
   make diff
   
   # Validate against cluster
   helm template test build/output/mimir-custom --validate
   ```

### Debug Commands

```bash
# Show current configuration
make show-version

# Generate documentation
make docs

# Watch for changes
make watch

# Compare with base chart
make diff
```

## 📚 Documentation

- [Configuration Values](docs/VALUES.md)
- [Architecture Overview](docs/README.md)
- [Changelog](docs/CHANGELOG.md)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Add tests for new functionality
5. Run the full test suite (`make test`)
6. Commit your changes (`git commit -m 'Add amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

### Development Workflow

```bash
# Setup development environment
make setup

# Make changes to kustomize configurations
# ...

# Test changes
make dev-build

# Run full validation
make validate test security-scan

# Generate documentation
make docs

# Submit PR
```

## 📄 License

This project is licensed under the Apache 2.0 License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Grafana Mimir](https://grafana.com/oss/mimir/) - The amazing time series database
- [Grafana Helm Charts](https://github.com/grafana/helm-charts) - Official Helm charts
- [Kustomize](https://kustomize.io/) - Kubernetes native configuration management

## 📞 Support

- 📧 Email: support@example.com
- 💬 Slack: #mimir-support
- 🐛 Issues: [GitHub Issues](https://github.com/your-org/mimir-custom-chart/issues)
- 📖 Documentation: [Wiki](https://github.com/your-org/mimir-custom-chart/wiki)