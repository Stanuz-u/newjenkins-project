
pipeline {
    agent any

    tools {
        nodejs 'nodeproject'
    }

    environment {
        EC2_IP = '13.60.241.251'
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
                    def commitId = sh(
                        script: 'git rev-parse --short=12 HEAD',
                        returnStdout: true
                    ).trim()

                    env.IMAGE = "classroom-app:${env.BUILD_NUMBER}-${commitId}"
                }

                sh 'docker build -t "$IMAGE" .'
            }
        }

        stage('Deploy to EC2') {
            steps {
                echo 'Deploying application to EC2...'

                sshagent(credentials: ['ec2']) {
                    sh '''
                        scp scripts/deploy.sh \
                            "ubuntu@$EC2_IP:/home/ubuntu/deploy.sh"

                        ssh "ubuntu@$EC2_IP" \
                            "chmod +x /home/ubuntu/deploy.sh && bash /home/ubuntu/deploy.sh '$IMAGE'"
                    '''
                }
            }
        }
    }

    post {
        success {
            echo 'Pipeline completed successfully!'
        }

        failure {
            echo 'Pipeline failed. Check the console output.'
        }
    }
}
