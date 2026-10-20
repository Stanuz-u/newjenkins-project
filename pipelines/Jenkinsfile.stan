
pipeline {
    agent any

    tools {
        nodejs 'nodeproject'
        dockerTool 'docker-project'
    }

    environment {
        EC2_IP = '13.60.88.234'
    }

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 15, unit: 'MINUTES')
    }

    stages {
        stage('Test') {
            steps {
                sh 'mkdir -p reports && npm run test:ci'
            }
        }

        stage('Build') {
            steps {
                script {
                    env.IMAGE = "classroom-app:${env.BUILD_NUMBER}-${sh(
                        script: 'git rev-parse --short=12 HEAD',
                        returnStdout: true
                    ).trim()}"
                }

                sh 'docker build -t "$IMAGE" .'
            }
        }

        stage('Deploy') {
            steps {
                script {
                    echo "Deploying Docker image to EC2"
                }

                sshagent(credentials: ['ec2']) {
                    sh '''
                        scp -o StrictHostKeyChecking=yes \
                            scripts/deploy.sh \
                            ubuntu@${EC2_IP}:/home/ubuntu/deploy.sh

                        ssh -o StrictHostKeyChecking=yes \
                            ubuntu@${EC2_IP} \
                            "chmod +x /home/ubuntu/deploy.sh && /home/ubuntu/deploy.sh '${IMAGE}'"
                    '''
                }
            }
        }
    }

    post {
        always {
            junit testResults: 'reports/tests.xml',
                  allowEmptyResults: true
        }
    }
}
