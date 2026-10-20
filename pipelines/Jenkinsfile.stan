pipeline {
    agent any
    tools { 
        nodejs 'nodeproject' 
        dockerTool 'docker-project'
    }
    environment {
        EC2_IP = '13.60.88.234'
    }
    options { timestamps(); disableConcurrentBuilds(); timeout(time: 15, unit: 'MINUTES') }
    stages {
        stage('Test') { steps { sh 'mkdir -p reports && npm run test:ci' } }
        stage('Build') {
            steps {
                script { env.IMAGE = "classroom-app:${env.BUILD_NUMBER}-${sh(script: 'git rev-parse --short=12 HEAD', returnStdout: true).trim()}" }
                sh 'docker build -t "$IMAGE" .'
        stage('deploy') {
            steps {
                script { env.IMAGE = "classroom-app:${env.BUILD_NUMBER}-${sh(script: 'git rev-parse --short=12 HEAD', returnStdout: true).trim()}" }
                sh 'docker build -t "$IMAGE" .'
                }
            }
        stage('Deploy production') {
            steps {
               script {
                       echo "deploying to shell-script to ec2"
                       def shellCmd = "bash scripts/deploy.sh"
                       sshagent(credentials: ['ec2']) {
                       sh "scp -o StrictHostKeyChecking=no deploy.sh ubuntu@{EC2_IP}:/home/ubuntu"
                       sh "ssh -o StrictHostKeyChecking=no deploy.sh ubuntu@{EC2_IP} ${shellCmd}"
                       }
                  }
            }
