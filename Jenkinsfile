GIT_COMMIT_HASH = ""

pipeline {
    agent none
    options {
        buildDiscarder(logRotator(artifactDaysToKeepStr: "7", artifactNumToKeepStr: "2"))
        disableConcurrentBuilds(abortPrevious: true)
    }

    parameters {
        string(
            name: 'SAUNAFS_REF',
            defaultValue: 'dev',
            description: 'What SaunaFS git reference to use'
        )
    }

    stages {
        stage('Human approval for fork PRs') {
            when { expression { env.CHANGE_FORK } }  // set only for PRs from forks
            options { timeout(time: 24, unit: 'HOURS') }
            steps {
                input(
                    message: "Approve running privileged steps for fork PR #${env.CHANGE_ID}?",
                    submitter: 'leil-io*c-devs',
                    ok: 'Run privileged stages'
                )
            }
        }

        stage('Get build metadata') {
            agent {label 'linux'}
            steps {
                checkout scm
                script {
                    GIT_COMMIT_HASH = sh(
                        script: 'git rev-parse HEAD',
                        returnStdout: true,
                    ).trim()
                }
            }
            post {
                cleanup {
                    cleanWs(cleanWhenNotBuilt: true,
                        deleteDirs: true,
                        disableDeferredWipeout: true,
                        notFailBuild: true,
                    )
                }
            }
        }


        stage('Build packages') {
            steps {
                script {
                    build (
                        job: 'SaunaFS Packages (Dev)',
                        parameters: [
                            string(name: 'PACKAGE_REF', value: GIT_COMMIT_HASH),
                            string(name: 'SAUNAFS_REF', value: params.SAUNAFS_REF),
                            string(name: 'REPOSITORY', value: "Experimental"),
                            booleanParam(name: 'NO_DEPLOY', value: true)
                        ]
                    )
                }
            }
        }
    }
}
