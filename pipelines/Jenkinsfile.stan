pipeline {
    agent any

    tools {
        nodejs 'nodeproject'
    }

    environment {
        EC2_IP   = '13.60.241.251'
        SSH_OPTS = '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes'
    }

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 15, unit: 'MINUTES')
        ansiColor('xterm') // Makes console outputs colorful and easier to read
    }

    stages {
        stage('Test') {
            steps {
                sh 'mkdir -p reports'
                // Ensured clean install and forced the test runner to exit when finished
                sh 'npm ci'
                sh 'npm run test:ci -- --forceExit' 
            }
        }

        stage('Build') {
            steps {
                script {
                    // Cleaner, safer way to grab the short commit ID without variable leaks
                    def commitId = sh(script: 'git rev-parse --short=12 HEAD', returnStdout: true).trim()
                    env.IMAGE = "classroom-app:${env.BUILD_NUMBER}-${commitId}"
                }
                sh 'docker build -t "$IMAGE" .'
            }
        }

        stage('Deploy to EC2') {
            steps {
                echo "🚀 Deploying $IMAGE to EC2..."

                sshagent(credentials: ['ec2']) {
                    // Added SSH options to automatically bypass host key verification prompts
                    sh """
                        scp ${env.SSH_OPTS} scripts/deploy.sh ubuntu@${env.EC2_IP}:/home/ubuntu/deploy.sh
                        
                        ssh ${env.SSH_OPTS} ubuntu@${env.EC2_IP} \
                            "chmod +x /home/ubuntu/deploy.sh && bash /home/ubuntu/deploy.sh '${env.IMAGE}'"
                    """
                }
            }
        }
    }

    post {
        success {
            echo '✅ Pipeline completed successfully!'
        }
        failure {
            echo '❌ Pipeline failed. Check the console output.'
        }
    }
}

