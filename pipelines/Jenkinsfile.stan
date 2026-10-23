pipeline {
    agent any

    tools {
        nodejs 'nodeproject'
    }

    parameters {
        string(name: 'STAGING_IP', defaultValue: '16.170.205.99', description: 'Staging EC2 instance IPv4 address')
        string(name: 'PRODUCTION_IP', defaultValue: '16.171.161.103', description: 'Production EC2 instance IPv4 address')
        booleanParam(name: 'DEPLOY_PRODUCTION', defaultValue: false, description: 'Check this box to promote the build to the production server after staging succeeds')
    }

    environment {
        // Replace with your actual Docker Hub username/org
        DOCKER_REGISTRY  = 'stanuz' 
        DOCKER_REPO      = 'classroom-app'
        
        SSH_OPTS         = '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes'
    }

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 20, unit: 'MINUTES')
    }

    stages {
        stage('Test') {
            steps {
                sh 'mkdir -p reports'
                sh 'npm ci'
                sh 'npm run test:ci -- --forceExit' 
            }
        }

        stage('Build & Tag') {
            steps {
                script {
                    def commitId = sh(script: 'git rev-parse --short=12 HEAD', returnStdout: true).trim()
                    // Constructs a globally distinct Docker Hub registry path
                    env.IMAGE_TAG = "${env.BUILD_NUMBER}-${commitId}"
                    env.FULL_IMAGE_NAME = "${env.DOCKER_REGISTRY}/${env.DOCKER_REPO}:${env.IMAGE_TAG}"
                }
                sh 'docker build -t "$FULL_IMAGE_NAME" .'
            }
        }

        stage('Push to Docker Hub') {
            steps {
                echo "📦 Uploading image to Docker Hub..."
                // 'docker-hub-credentials-id' must match your stored Jenkins Username/Password credential ID
                withCredentials([usernamePassword(credentialsId: 'docker-login', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                    sh """
                        echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
                        docker push "$FULL_IMAGE_NAME"
                    """
                }
            }
        }

        stage('Deploy to Staging') {
            steps {
                script {
                    if (!params.STAGING_IP) { error 'Staging IP parameter cannot be empty.' }
                }
                echo "🚀 Deploying $FULL_IMAGE_NAME to Staging EC2 (${params.STAGING_IP})..."
                sshagent(credentials: ['ec2']) {
                    sh """
                        scp ${env.SSH_OPTS} scripts/deploy.sh ubuntu@${params.STAGING_IP}:/home/ubuntu/deploy.sh
                        ssh ${env.SSH_OPTS} ubuntu@${params.STAGING_IP} \
                            "chmod +x /home/ubuntu/deploy.sh && bash /home/ubuntu/deploy.sh '${env.FULL_IMAGE_NAME}'"
                    """
                }
            }
        }

        stage('Approve Production') {
            when { expression { params.DEPLOY_PRODUCTION } }
            steps {
                echo "⏸️ Staging deployment successful. Pausing for production release approval..."
                timeout(time: 15, unit: 'MINUTES') {
                    // Pauses execution until a team member manually confirms the promotion
                    input message: "Promote image tag [ ${env.IMAGE_TAG} ] to live Production?", ok: "Release to Production"
                }
            }
        }

        stage('Deploy to Production') {
            when { expression { params.DEPLOY_PRODUCTION } }
            steps {
                script {
                    if (!params.PRODUCTION_IP || params.PRODUCTION_IP == params.STAGING_IP) { 
                        error 'A valid, distinct Production IP address must be supplied.' 
                    }
                }
                echo "🔥 Deploying verified image $FULL_IMAGE_NAME to Production EC2 (${params.PRODUCTION_IP})..."
                sshagent(credentials: ['ec2']) {
                    sh """
                        scp ${env.SSH_OPTS} scripts/deploy.sh ubuntu@${params.PRODUCTION_IP}:/home/ubuntu/deploy.sh
                        ssh ${env.SSH_OPTS} ubuntu@${params.PRODUCTION_IP} \
                            "chmod +x /home/ubuntu/deploy.sh && bash /home/ubuntu/deploy.sh '${env.FULL_IMAGE_NAME}'"
                    """
                }
            }
        }
    }

    post {
        success {
            echo '✅ Pipeline completed successfully across targeted environments!'
        }
        failure {
            echo '❌ Pipeline failed. Check console log streams for error context.'
        }
    }
}
