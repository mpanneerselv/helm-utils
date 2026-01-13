pipeline {
    agent any
    
    environment {
        CHART_NAME = 'mimir-custom'
        ARTIFACTORY_URL = credentials('artifactory-url')
        ARTIFACTORY_REPO = credentials('artifactory-repo')
        ARTIFACTORY_USER = credentials('artifactory-user')
        ARTIFACTORY_TOKEN = credentials('artifactory-token')
        
        // Version management
        VERSION_BUMP = params.VERSION_BUMP ?: 'patch'
        BUILD_NUMBER = env.BUILD_NUMBER
        GIT_TAG = params.GIT_TAG ?: 'true'
        
        // Tools
        HELM_VERSION = '3.13.3'
        KUSTOMIZE_VERSION = '5.2.1'
        YQ_VERSION = '4.35.2'
    }
    
    parameters {
        choice(
            name: 'VERSION_BUMP',
            choices: ['patch', 'minor', 'major'],
            description: 'Version bump type'
        )
        booleanParam(
            name: 'GIT_TAG',
            defaultValue: true,
            description: 'Tag git commit with chart version'
        )
        booleanParam(
            name: 'SKIP_TESTS',
            defaultValue: false,
            description: 'Skip chart tests'
        )
        booleanParam(
            name: 'SKIP_SECURITY_SCAN',
            defaultValue: false,
            description: 'Skip security scans'
        )
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_COMMIT_SHORT = sh(
                        script: 'git rev-parse --short HEAD',
                        returnStdout: true
                    ).trim()
                }
            }
        }
        
        stage('Setup Environment') {
            steps {
                script {
                    // Install required tools
                    sh '''
                        # Install Helm
                        if ! command -v helm &> /dev/null; then
                            curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
                            chmod 700 get_helm.sh
                            ./get_helm.sh --version v${HELM_VERSION}
                        fi
                        
                        # Install Kustomize
                        if ! command -v kustomize &> /dev/null; then
                            curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
                            sudo mv kustomize /usr/local/bin/
                        fi
                        
                        # Install yq
                        if ! command -v yq &> /dev/null; then
                            sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64
                            sudo chmod +x /usr/local/bin/yq
                        fi
                        
                        # Verify installations
                        helm version --short
                        kustomize version --short
                        yq --version
                    '''
                }
            }
        }
        
        stage('Setup') {
            steps {
                sh 'make jenkins-setup'
            }
        }
        
        stage('Download Dependencies') {
            steps {
                sh 'make deps'
            }
        }
        
        stage('Validate Base Chart') {
            steps {
                sh 'make validate-base'
            }
        }
        
        stage('Build Custom Chart') {
            steps {
                sh 'make build'
            }
        }
        
        stage('Validate Custom Chart') {
            steps {
                sh 'make validate'
            }
        }
        
        stage('Run Tests') {
            when {
                not { params.SKIP_TESTS }
            }
            steps {
                sh 'make test'
            }
            post {
                always {
                    // Archive test results if available
                    archiveArtifacts artifacts: 'build/test-results/**', allowEmptyArchive: true
                }
            }
        }
        
        stage('Security Scan') {
            when {
                not { params.SKIP_SECURITY_SCAN }
            }
            steps {
                sh 'make security-scan'
            }
            post {
                always {
                    // Archive security scan results if available
                    archiveArtifacts artifacts: 'build/security-results/**', allowEmptyArchive: true
                }
            }
        }
        
        stage('Generate Documentation') {
            steps {
                sh 'make docs'
                archiveArtifacts artifacts: 'docs/**', allowEmptyArchive: true
            }
        }
        
        stage('Package Chart') {
            steps {
                script {
                    sh 'make package'
                    
                    // Get the new version
                    env.CHART_VERSION = sh(
                        script: 'cat VERSION',
                        returnStdout: true
                    ).trim()
                    
                    echo "Chart version: ${env.CHART_VERSION}"
                }
                
                archiveArtifacts artifacts: 'build/packages/*.tgz'
            }
        }
        
        stage('Publish to Artifactory') {
            when {
                anyOf {
                    branch 'main'
                    branch 'master'
                    branch 'release/*'
                }
            }
            steps {
                sh 'make publish'
            }
        }
        
        stage('Git Tag') {
            when {
                allOf {
                    anyOf {
                        branch 'main'
                        branch 'master'
                        branch 'release/*'
                    }
                    params.GIT_TAG
                }
            }
            steps {
                script {
                    withCredentials([usernamePassword(credentialsId: 'git-credentials', usernameVariable: 'GIT_USER', passwordVariable: 'GIT_TOKEN')]) {
                        sh '''
                            git config user.name "Jenkins"
                            git config user.email "jenkins@example.com"
                            make tag
                            git push origin v${CHART_VERSION}
                        '''
                    }
                }
            }
        }
        
        stage('Deploy to Test Environment') {
            when {
                branch 'main'
            }
            steps {
                script {
                    // Deploy to test environment for validation
                    sh '''
                        # Install chart in test namespace
                        helm upgrade --install mimir-test-${BUILD_NUMBER} \
                            build/packages/${CHART_NAME}-${CHART_VERSION}.tgz \
                            --namespace mimir-test-${BUILD_NUMBER} \
                            --create-namespace \
                            --values ci/minimal-values.yaml \
                            --wait --timeout 300s
                        
                        # Run smoke tests
                        kubectl get pods -n mimir-test-${BUILD_NUMBER}
                        
                        # Cleanup test deployment
                        helm uninstall mimir-test-${BUILD_NUMBER} --namespace mimir-test-${BUILD_NUMBER}
                        kubectl delete namespace mimir-test-${BUILD_NUMBER}
                    '''
                }
            }
        }
    }
    
    post {
        always {
            // Clean up workspace
            sh 'make clean || true'
        }
        
        success {
            script {
                if (env.BRANCH_NAME == 'main' || env.BRANCH_NAME == 'master') {
                    // Send success notification
                    slackSend(
                        channel: '#deployments',
                        color: 'good',
                        message: """
                        ✅ Mimir Custom Chart ${env.CHART_VERSION} released successfully!
                        
                        📦 Chart: ${env.CHART_NAME}-${env.CHART_VERSION}.tgz
                        🔗 Build: ${env.BUILD_URL}
                        📝 Commit: ${env.GIT_COMMIT_SHORT}
                        
                        Installation:
                        ```
                        helm repo add custom-charts ${env.ARTIFACTORY_URL}/artifactory/${env.ARTIFACTORY_REPO}
                        helm install mimir custom-charts/${env.CHART_NAME} --version ${env.CHART_VERSION}
                        ```
                        """.stripIndent()
                    )
                }
            }
        }
        
        failure {
            // Send failure notification
            slackSend(
                channel: '#deployments',
                color: 'danger',
                message: """
                ❌ Mimir Custom Chart build failed!
                
                🔗 Build: ${env.BUILD_URL}
                📝 Commit: ${env.GIT_COMMIT_SHORT}
                🌿 Branch: ${env.BRANCH_NAME}
                """.stripIndent()
            )
        }
        
        unstable {
            // Send unstable notification
            slackSend(
                channel: '#deployments',
                color: 'warning',
                message: """
                ⚠️ Mimir Custom Chart build is unstable!
                
                🔗 Build: ${env.BUILD_URL}
                📝 Commit: ${env.GIT_COMMIT_SHORT}
                🌿 Branch: ${env.BRANCH_NAME}
                """.stripIndent()
            )
        }
    }
}