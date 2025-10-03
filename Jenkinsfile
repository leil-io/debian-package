def willDoSnapshot(repoChoice) {
    return repoChoice in ['Development', 'Experimental']
}

def getBuildSuffix(repoChoice) {
    switch (repoChoice) {
        case "Production":
            return "-official"
        case "Staging":
            return "-staging"
        case "Development":
            return "-dev"
        case "Experimental":
            return "-experimental"
        default:
            error("Repository choice not supported!")
    }
}

def getTargetRepositorySuffix(repoChoice) {
    switch (repoChoice) {
        case "Production":
            return ""
        case "Staging":
            return "-staging"
        case "Development":
            return "-dev"
        case "Experimental":
            return "-experimental"
        default:
            error("Repository choice not supported!")
    }
}

@NonCPS
def getVersionFromDebFilename(filename) {
    def m = (filename =~ /.+?_(.+?)_.+\.deb$/)
    assert m.matches()
    return m[0][1]
}

pipeline {
    agent none

    options {
        buildDiscarder(logRotator(artifactDaysToKeepStr: "7", artifactNumToKeepStr: "2"))
        disableConcurrentBuilds(abortPrevious: true)
    }

    parameters {
        string(name: 'PACKAGE_REF', defaultValue: '', description: 'The git reference (branch, tag or hash) for the debian packaging scripts.')
        string(name: 'SAUNAFS_REF', defaultValue: 'dev', description: 'The git reference (branch, tag or hash) to build from the saunafs repository.')
        choice(name: 'REPOSITORY', choices: ['Experimental', 'Development', 'Staging', 'Production'], description: 'Target package repository.')
        booleanParam(name: 'NO_DEPLOY', defaultValue: false, description: 'If true, packages will not be deployed to the repository.')
    }

    environment {
        REF = "${params.SAUNAFS_REF}"
        SNAPSHOT = willDoSnapshot(params.REPOSITORY)
        VERSION_SUFFIX = getBuildSuffix(params.REPOSITORY)
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
        stage('Build, Package, and Deploy') {
            matrix {
                axes {
                    axis {
                        name 'DISTRIBUTION'
                        values 'ubuntu-22.04', 'ubuntu-24.04'
                    }
                }
                agent {
                    label "build-agent-${DISTRIBUTION}"
                }
                stages {
                    stage('Build, deploy and test') {
                        stages {
                            stage('Checkout and Build') {
                                steps {
                                    script {
                                        def ref = params.PACKAGE_REF?.trim()

                                        if (ref) {
                                            echo "Building with ${ref}"
                                            checkout([$class: 'GitSCM',
                                                branches: [[name: ref]],
                                            ])
                                        } else {
                                            echo "Checking out normally"
                                            checkout scm
                                        }
                                        sh './package.sh'
                                        sh "mkdir -p ${DISTRIBUTION}"
                                        sh "mv build/* ${DISTRIBUTION}"
                                    }
                                }
                            }
                            stage('Archive for Manual Download') {
                                steps {
                                    archiveArtifacts(artifacts:
                                        "${DISTRIBUTION}/*.deb",
                                        followSymlinks: false,
                                        allowEmptyArchive: false
                                    )
                                }
                            }
                            stage('Deploy') {
                                environment {
                                    NEXUS_AUTH = credentials('nexus-deployment-credentials')
                                    REPO_NAME = "saunafs-${DISTRIBUTION}${getTargetRepositorySuffix(params.REPOSITORY)}"
                                }
                                when { expression { !params.NO_DEPLOY } }
                                steps {
                                    script {
                                        sh "./deliver-packages.sh '${DISTRIBUTION}'"
                                    }
                                }
                            }
                            stage('Test Ansible') {
                                when { expression { !params.NO_DEPLOY } }
                                steps {
                                    script {
                                        def REPO_URL = "https://repo.saunafs.com/repository/"
                                        def REPO_NAME = REPO_URL + "saunafs-${DISTRIBUTION}${getTargetRepositorySuffix(params.REPOSITORY)}/"
                                        def deb = sh(script: "ls -t ${DISTRIBUTION}/saunafs-*.deb | head -1", returnStdout: true).trim()
                                        def version = getVersionFromDebFilename(deb)

                                        def repoUrlParamMap = [
                                            "ubuntu-22.04": "SAUNAFS_REPO_URL_JAMMY",
                                            "ubuntu-24.04": "SAUNAFS_REPO_URL_NOBLE"
                                        ]
                                        def params = [
                                            string(name: 'SAUNAFS_VERSION', value: "${version}")
                                        ]

                                        repoUrlParamMap.each { distro, paramName ->
                                            def value = (distro == DISTRIBUTION) ? "${REPO_NAME}" : ""
                                            params << string(name: paramName, value: value)
                                        }
                                        def repoUrlParamName = repoUrlParamMap[DISTRIBUTION]

                                        if (repoUrlParamName) {
                                            build(job: 'Leil Storage Ansible/main',
                                                parameters: params
                                            )
                                        } else {
                                            error("Repository not in map for ansible tests")
                                        }
                                    }
                                }
                            }
                        }
                        post {
                            cleanup {
                                script {
                                    def buildDir = "${DISTRIBUTION}"
                                    if (fileExists(buildDir)) {
                                        dir(buildDir) {
                                            deleteDir()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
