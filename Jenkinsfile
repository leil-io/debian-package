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
        string(name: 'LEILFS_REF', defaultValue: 'dev', description: 'The git reference (branch, tag or hash) to build from the leilfs repository.')
        choice(name: 'REPOSITORY', choices: ['Experimental', 'Development', 'Staging', 'Production'], description: 'Target package repository.')
        booleanParam(name: 'NO_DEPLOY', defaultValue: false, description: 'If true, packages will not be deployed to the repository.')
    }

    environment {
        REF = "${params.LEILFS_REF}"
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

        stage('Resolve Build Identity') {
            agent { label "waiting-agent" }
            steps {
                script {
                    def sourceRef = params.LEILFS_REF?.trim() ?: 'dev'

                    def sourceIdentity
                    withEnv(["SOURCE_REF=${sourceRef}"]) {
                        // Use a metadata-only clone here so branches, tags, and raw commit hashes
                        // resolve compatibly with package.sh without downloading a full working tree.
                        sourceIdentity = sh(
                            script: '''
                                set -e
                                temp_dir=$(mktemp -d)
                                cleanup() {
                                    rm -rf "$temp_dir"
                                }
                                trap cleanup EXIT

                                git clone --quiet --filter=blob:none --sparse https://github.com/leil-io/leilfs/ "$temp_dir/leilfs"
                                cd "$temp_dir/leilfs"
                                git checkout -q "$SOURCE_REF"

                                resolved_commit=$(git rev-parse HEAD)
                                resolved_branch=$(basename "$(git name-rev "$resolved_commit" | awk '{print $2}')")
                                printf '%s\n%s\n' "$resolved_commit" "$resolved_branch"
                            ''',
                            returnStdout: true
                        ).trim().readLines()
                    }

                    def sharedSnapshotTimestamp = env.SNAPSHOT == 'true'
                        ? sh(script: 'date +%Y.%m.%d~%H.%M.%S', returnStdout: true).trim()
                        : ''

                    def buildIdentityFile = [
                        "REF='${sourceIdentity[0]}'",
                        "RESOLVED_GIT_COMMIT='${sourceIdentity[0]}'",
                        "RESOLVED_GIT_BRANCH='${sourceIdentity[1]}'",
                        "SNAPSHOT_TIMESTAMP_OVERRIDE='${sharedSnapshotTimestamp}'"
                    ].join('\n') + '\n'

                    writeFile file: '.build-identity.env', text: buildIdentityFile
                    stash name: 'build-identity', includes: '.build-identity.env'

                    echo "Resolved LeilFS commit for all distro builds: ${sourceIdentity[0]}"
                    echo "Resolved LeilFS branch for all distro builds: ${sourceIdentity[1]}"
                    if (sharedSnapshotTimestamp) {
                        echo "Shared snapshot timestamp for all distro builds: ${sharedSnapshotTimestamp}"
                    }
                }
            }
        }

        stage('Build, Package, and Deploy') {
            matrix {
                axes {
                    axis {
                        name 'DISTRIBUTION'
                        values 'ubuntu-22.04', 'ubuntu-24.04', 'ubuntu-26.04'
                    }
                }

                stages {
                    stage('Build and Deploy') {
                        agent { label "build-agent-${DISTRIBUTION}" }
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

                                        unstash 'build-identity'
                                        sh '''
                                            set -a
                                            . ./.build-identity.env
                                            set +a
                                            ./package.sh
                                        '''
                                        sh "mkdir -p ${DISTRIBUTION}"
                                        sh "mv build/* ${DISTRIBUTION}"

                                        def deb = sh(
                                            script: "ls -t ${DISTRIBUTION}/saunafs-*.deb | head -1",
                                            returnStdout: true
                                        ).trim()
                                        def version = getVersionFromDebFilename(deb)

                                        writeFile file: "${DISTRIBUTION}/package-version.txt", text: version
                                        stash name: "package-metadata-${DISTRIBUTION}", includes: "${DISTRIBUTION}/package-version.txt"
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

        stage('Test Ansible') {
            agent { label "waiting-agent" }
            when { expression { !params.NO_DEPLOY } }
            steps {
                script {
                    def repoUrlParamMap = [
                        "ubuntu-22.04": "SAUNAFS_REPO_URL_JAMMY",
                        "ubuntu-24.04": "SAUNAFS_REPO_URL_NOBLE",
                        "ubuntu-26.04": "SAUNAFS_REPO_URL_RESOLUTE",
                    ]
                    // Keep this list in sync with the matrix axis above. Declarative matrix
                    // axes require string literals here, so this stage cannot reuse a shared
                    // Groovy list without switching to a more scripted pipeline structure.
                    def distributions = repoUrlParamMap.keySet().toList()

                    def repoUrlBase = "https://repo.leil.io/repository/"
                    def repoUrls = distributions.collectEntries { dist ->
                        [(dist): "${repoUrlBase}saunafs-${dist}${getTargetRepositorySuffix(params.REPOSITORY)}/"]
                    }

                    def versions = [:]
                    repoUrls.keySet().each { distribution ->
                        unstash "package-metadata-${distribution}"
                        versions[distribution] = readFile("${distribution}/package-version.txt").trim()
                    }

                    versions.each { dist, version ->
                        echo "Test Ansible input version for ${dist}: ${version}"
                    }

                    def distinctVersions = versions.values().toSet()
                    if (distinctVersions.size() != 1) {
                        error(
                            "Expected identical package versions across distros, found: " +
                            versions.collect { dist, version -> "${dist}='${version}'" }.join(', ')
                        )
                    }

                    def ansibleVersion = distinctVersions.first()

                    echo "Test Ansible exact shared version: ${ansibleVersion}"

                    def jobParams = [string(name: 'LEILFS_VERSION', value: ansibleVersion)]
                    distributions.each { dist ->
                        if (repoUrlParamMap[dist]) {
                            jobParams << string(name: repoUrlParamMap[dist], value: repoUrls[dist])
                        } else {
                            error("No repository URL parameter mapping found for distribution: ${dist}")
                        }
                    }

                    build(
                        job: 'Leil Storage Ansible/main',
                        parameters: jobParams
                    )
                }
            }
        }
    }
}
