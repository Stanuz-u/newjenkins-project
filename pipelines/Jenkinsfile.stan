
pipeline {
    agent any

    tools {
        nodejs 'nodeproject'
    }

    parameters {
        string(
            name: 'STAGING_IP',
            defaultValue: '16.170.205.99',
            description: 'Staging EC2 instance IPv4 address'
        )

        string(
            name: 'PRODUCTION_IP',
            defaultValue: '16.171.161.103',
            description: 'Production EC2 instance IPv4 address'
        )

        booleanParam(
            name: 'DEPLOY_PRODUCTION',
            defaultValue: false,
            description: 'Deploy to production after staging succeeds'
        )
    }

    environment {
        DOCKER_REGISTRY = 'stanuz'
        DOCKER_REPO = 'classroom-app'

        // Temporary approach: configure trusted host keys for production use.
        SSH_OPTS = '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes'
    }

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 20, unit: 'MINUTES')
    }

    stages {

        stage('Test') {
            steps {
                sh 'mkdir -p reports && npm run test:ci'
            }
        }

        stage('Build & Tag') {
            steps {
                script {
                    def commitId = sh(
                        script: 'git rev-parse --short=12 HEAD',
                        returnStdout: true
                    ).trim()

                    env.IMAGE_TAG =
                        "${env.BUILD_NUMBER}-${commitId}"

                    env.FULL_IMAGE_NAME =
                        "${env.DOCKER_REGISTRY}/${env.DOCKER_REPO}:${env.IMAGE_TAG}"
                }

                sh 'docker build -t "$FULL_IMAGE_NAME" .'
            }
        }

        stage('Push to Docker Hub') {
            steps {
                echo 'Uploading image to Docker Hub...'

                withCredentials([
                    usernamePassword(
                        credentialsId: 'docker-login',
                        usernameVariable: 'DOCKER_USER',
                        passwordVariable: 'DOCKER_PASS'
                    )
                ]) {
                    sh '''
                        set -eu
                        echo "$DOCKER_PASS" |
                            docker login -u "$DOCKER_USER" --password-stdin

                        docker push "$FULL_IMAGE_NAME"

                        docker logout
                    '''
                }
            }
        }

        stage('Deploy to Staging') {
            steps {
                script {
                    if (!params.STAGING_IP?.trim()) {
                        error 'Staging IP cannot be empty.'
                    }
                }

                echo "Deploying ${env.FULL_IMAGE_NAME} to staging..."

                sshagent(credentials: ['ec2']) {
                    sh """
                        set -eu

                        scp ${env.SSH_OPTS} \
                            scripts/deploy.sh \
                            ubuntu@${params.STAGING_IP}:/home/ubuntu/deploy.sh

                        ssh ${env.SSH_OPTS} \
                            ubuntu@${params.STAGING_IP} \
                            "chmod +x /home/ubuntu/deploy.sh && bash /home/ubuntu/deploy.sh '${env.FULL_IMAGE_NAME}'"
                    """
                }
            }
        }

        stage('Approve Production') {
            when {
                expression { params.DEPLOY_PRODUCTION }
            }

            steps {
                timeout(time: 15, unit: 'MINUTES') {
                    input(
                        message: "Staging succeeded. Promote ${env.FULL_IMAGE_NAME} to production?",
                        ok: 'Release to Production'
                    )
                }
            }
        }

        stage('Deploy to Production') {
            when {
                expression { params.DEPLOY_PRODUCTION }
            }

            steps {
                script {
                    if (!params.PRODUCTION_IP?.trim()) {
                        error 'Production IP cannot be empty.'
                    }

                    if (params.PRODUCTION_IP == params.STAGING_IP) {
                        error 'Production and staging must use different IP addresses.'
                    }
                }

                echo "Deploying ${env.FULL_IMAGE_NAME} to production..."

                sshagent(credentials: ['ec2']) {
                    sh """
                        set -eu

                        scp ${env.SSH_OPTS} \
                            scripts/deploy.sh \
                            ubuntu@${params.PRODUCTION_IP}:/home/ubuntu/deploy.sh

                        ssh ${env.SSH_OPTS} \
                            ubuntu@${params.PRODUCTION_IP} \
                            "chmod +x /home/ubuntu/deploy.sh && bash /home/ubuntu/deploy.sh '${env.FULL_IMAGE_NAME}'"
                    """
                }
            }
        }
    }

    post {
        success {
            echo 'Pipeline completed successfully!'
        }

        failure {
            echo 'Pipeline failed. Check the Console Output.'
        }

        always {
            echo 'Pipeline execution finished.'
        }
    }
}
