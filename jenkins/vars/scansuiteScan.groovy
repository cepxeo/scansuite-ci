/*
 * ScanSuite for Jenkins: a shared-library step.
 *
 * Add this repository's jenkins directory as a Global Pipeline Library
 * (Manage Jenkins > System > Global Pipeline Libraries, e.g. named "scansuite"),
 * store the API token as a "Secret text" credential, then:
 *
 *   @Library('scansuite') _
 *   pipeline {
 *     agent any
 *     stages {
 *       stage('ScanSuite') {
 *         steps {
 *           scansuiteScan(url: 'https://scansuite.example.com', team: 'appsec', product: 'my-service',
 *                         credentialsId: 'scansuite-ci-token',
 *                         profile: env.CHANGE_ID ? 'quick-classic' : 'standard-ai', changedOnly: env.CHANGE_ID != null)
 *         }
 *       }
 *     }
 *   }
 *
 * Needs the Docker Pipeline plugin. Returns the exit code; a failed gate (1)
 * fails the build unless unstableOnGate is true, which marks it UNSTABLE.
 */
def call(Map config = [:]) {
    def image = config.image ?: 'appsec4u/scansuite-ci:1'
    def environment = [
        "SCANSUITE_URL=${config.url ?: ''}",
        "SCANSUITE_TEAM=${config.team ?: ''}",
        "SCANSUITE_PRODUCT=${config.product ?: ''}",
        "SCANSUITE_PRODUCT_ID=${config.productId ?: ''}",
        "SCANSUITE_PROFILE=${config.profile ?: ''}",
        "SCANSUITE_CHANGED_ONLY=${config.changedOnly ? '1' : ''}",
        "SCANSUITE_BASE=${config.base ?: ''}",
        "SCANSUITE_FAIL_ON_SEVERITY=${config.failOnSeverity ?: 'high'}",
        "SCANSUITE_MAX=${config.max ?: ''}",
        "SCANSUITE_BLOCK_CLASS=${config.blockClass ?: ''}",
        "SCANSUITE_MIN_CONFIDENCE=${config.minConfidence ?: 'any'}",
        "SCANSUITE_CA_BUNDLE=${config.caBundle ?: ''}",
        "SCANSUITE_STRICT_TLS=${config.strictTls ? '1' : ''}",
    ]
    def extra = config.args ?: ''
    int code = 0
    withCredentials([string(credentialsId: config.credentialsId ?: 'scansuite-ci-token', variable: 'SCANSUITE_TOKEN')]) {
        docker.image(image).inside('--entrypoint=') {
            withEnv(environment) {
                code = sh(script: "scansuite-ci --junit scansuite-junit.xml --summary-json scansuite.json ${extra}",
                          returnStatus: true)
            }
        }
    }
    junit allowEmptyResults: true, testResults: 'scansuite-junit.xml'
    archiveArtifacts allowEmptyArchive: true, artifacts: 'scansuite.json'
    if (code == 1 && config.unstableOnGate) {
        unstable('ScanSuite quality gate failed')
    } else if (code != 0) {
        error("ScanSuite exited with ${code} (1 gate failed, 2 scan failed, 3 configuration, 4 timeout, 5 server)")
    }
    return code
}
