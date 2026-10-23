pipeline {
    agent any
    tools {
    nodejs 'nodeproject'
}
    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 45, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '15', artifactNumToKeepStr: '3'))
    }
    parameters {
        string(name: 'STAGING_HOST', defaultValue: '16.170.205.99', description: 'Staging EC2 DNS name or IPv4 address')
        string(name: 'PRODUCTION_HOST', defaultValue: '16.171.161.103', description: 'Production EC2 DNS name or IPv4 address')
        booleanParam(name: 'DEPLOY_PRODUCTION', defaultValue: false, description: 'Request approval after staging succeeds')
    }
    stages {
        stage('Validate') {
            steps {
                sh 'mkdir -p reports && rm -f reports/tests.xml'
                script {
                    if (!(params.STAGING_HOST ==~ /[a-zA-Z0-9][a-zA-Z0-9.-]*/)) { error('Set a valid STAGING_HOST') }
                    if (params.DEPLOY_PRODUCTION && (!(params.PRODUCTION_HOST ==~ /[a-zA-Z0-9][a-zA-Z0-9.-]*/) || params.PRODUCTION_HOST == params.STAGING_HOST)) {
                        error('Production must be a valid, separate EC2 host')
                    }
                    env.IMAGE = "classroom-app:${env.BUILD_NUMBER}-${sh(script: 'git rev-parse --short=12 HEAD', returnStdout: true).trim()}"
                }
            }
        }
        stage('Test') { steps { sh 'mkdir -p reports && npm run test:ci' } }
        stage('Build once') { steps { sh 'docker build -t "$IMAGE" .' } }
        stage('Smoke test') { steps { sh 'bash scripts/smoke-test.sh "$IMAGE"' } }
        stage('Package') {
            steps {
                sh 'mkdir -p dist && docker save "$IMAGE" -o dist/image.tar && printf "%s\\n" "$IMAGE" > dist/image.txt'
                archiveArtifacts artifacts: 'dist/image.*', fingerprint: true
            }
        }
        stage('Deploy staging') {
            steps {
                withCredentials([file(credentialsId: 'ec2-known-hosts', variable: 'KNOWN_HOSTS')]) {
                    sshagent(credentials: ['ec2-deploy-key']) { sh 'bash scripts/deploy.sh "$STAGING_HOST" "$IMAGE"' }
                }
            }
        }
        stage('Approve production') {
            when { expression { params.DEPLOY_PRODUCTION } }
            steps {
                timeout(time: 10, unit: 'MINUTES') {
                    input message: 'Staging passed. Promote the same image to production?', submitter: 'instructor'
                }
            }
        }
        stage('Deploy production') {
            when { expression { params.DEPLOY_PRODUCTION } }
            steps {
                withCredentials([file(credentialsId: 'ec2-known-hosts', variable: 'KNOWN_HOSTS')]) {
                    sshagent(credentials: ['ec2-deploy-key']) { sh 'bash scripts/deploy.sh "$PRODUCTION_HOST" "$IMAGE"' }
                }
            }
        }
    }
    post { always { junit testResults: 'reports/tests.xml', allowEmptyResults: true } }
}
