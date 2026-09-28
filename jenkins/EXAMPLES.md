# ScanSuite on Jenkins — examples

Two ways to run it, both on the published `appsec4u/scansuite-ci:1` image:

- **The shared-library step** ([`vars/scansuiteScan.groovy`](vars/scansuiteScan.groovy)) —
  add this repo's `jenkins/` directory as a Global Pipeline Library (Manage Jenkins →
  System → Global Pipeline Libraries, e.g. named `scansuite`). Needs the **Docker
  Pipeline** plugin. It publishes the JUnit report and archives the JSON/SARIF.
- **A Docker agent with a raw command** — no library; run the image directly.

Store the token as a **Secret text** credential and pass its ID as `credentialsId`.
Step options: `url`, `team`, `product`/`productId`, `credentialsId`, `profile`,
`changedOnly`, `base`, `failOnSeverity`, `max`, `blockClass`, `minConfidence`,
`strictTls`, `caBundle`, `unstableOnGate`, `image`, and `args` (more client flags).

---

## 1. Multibranch — quick PR gate, standard on branches, nightly deep

```groovy
@Library('scansuite') _
pipeline {
  agent any
  triggers { cron(env.BRANCH_NAME == 'main' ? 'H 2 * * *' : '') }
  stages {
    stage('ScanSuite') {
      steps {
        scansuiteScan(
          url: 'https://scansuite.example.com', team: 'appsec', product: 'my-service',
          credentialsId: 'scansuite-ci-token',
          profile: env.CHANGE_ID ? 'quick' : (currentBuild.getBuildCauses('hudson.triggers.TimerTrigger$TimerTriggerCause') ? 'deep' : 'standard'),
          changedOnly: env.CHANGE_ID != null,
          blockClass: 'sql_injection,command_injection')
      }
    }
  }
}
```

## 2. Release gate — reachable-only, block secrets, keep the report

```groovy
@Library('scansuite') _
pipeline {
  agent any
  stages {
    stage('ScanSuite release gate') {
      steps {
        scansuiteScan(
          url: 'https://scansuite.example.com', team: 'appsec', product: 'my-service',
          credentialsId: 'scansuite-ci-token',
          profile: 'standard',
          failOnSeverity: 'medium',
          minConfidence: 'reachable',
          args: '--fail-on-secrets all --report-zip scansuite-report.zip')
      }
    }
  }
  post { always { archiveArtifacts allowEmptyArchive: true, artifacts: 'scansuite-report.zip' } }
}
```

## 3. Non-blocking — mark the build UNSTABLE instead of failing it

```groovy
@Library('scansuite') _
pipeline {
  agent any
  stages {
    stage('ScanSuite') {
      steps {
        scansuiteScan(
          url: 'https://scansuite.example.com', team: 'appsec', product: 'my-service',
          credentialsId: 'scansuite-ci-token',
          profile: 'standard',
          unstableOnGate: true)      // a failed gate → UNSTABLE, not FAILURE
      }
    }
  }
}
```

## 4. Per-severity budget on the nightly job

```groovy
@Library('scansuite') _
pipeline {
  agent any
  triggers { cron('H 2 * * *') }
  stages {
    stage('ScanSuite nightly') {
      steps {
        scansuiteScan(
          url: 'https://scansuite.example.com', team: 'appsec', product: 'my-service',
          credentialsId: 'scansuite-ci-token',
          profile: 'deep',
          max: 'high=0,critical=0,medium=10',
          args: '--timeout 14400')
      }
    }
  }
}
```

## 5. Without the library — a Docker agent and a raw command

Clear the image entrypoint; read the token from a credential into the environment.

```groovy
pipeline {
  agent { docker { image 'appsec4u/scansuite-ci:1'; args '--entrypoint=' } }
  environment {
    SCANSUITE_URL = 'https://scansuite.example.com'
    SCANSUITE_TEAM = 'appsec'
    SCANSUITE_PRODUCT = 'my-service'
    SCANSUITE_TOKEN = credentials('scansuite-ci-token')
  }
  stages {
    stage('ScanSuite') {
      steps {
        sh '''scansuite-ci --profile quick --changed-only \
                --block-class sql_injection --fail-on-severity high \
                --junit scansuite-junit.xml --sarif scansuite.sarif'''
      }
    }
  }
  post {
    always {
      junit allowEmptyResults: true, testResults: 'scansuite-junit.xml'
      archiveArtifacts allowEmptyArchive: true, artifacts: 'scansuite.sarif'
    }
  }
}
```

## 6. Monorepo — one stage per service

```groovy
@Library('scansuite') _
pipeline {
  agent any
  stages {
    stage('ScanSuite services') {
      steps {
        script {
          for (svc in ['payments', 'web-frontend']) {
            scansuiteScan(
              url: 'https://scansuite.example.com', team: 'appsec', product: svc,
              credentialsId: 'scansuite-ci-token',
              profile: 'quick', changedOnly: env.CHANGE_ID != null,
              args: "--source-dir services/${svc}",
              unstableOnGate: true)
          }
        }
      }
    }
  }
}
```

---

## Fine-grained AI scans

`--scanners` / `--options` are CLI-only, so pass them through the step's **`args`**.
Gate settings have their own step options (`failOnSeverity`, `minConfidence`, `max`);
combine them freely.

## 7. Full AI SAST — reachability + architecture + git history (default branch)

```groovy
@Library('scansuite') _
pipeline {
  agent any
  stages {
    stage('AI SAST') {
      steps {
        scansuiteScan(
          url: 'https://scansuite.example.com', team: 'appsec', product: 'my-service',
          credentialsId: 'scansuite-ci-token',
          failOnSeverity: 'high',
          args: '--scanners mlsast --options mlsast_reachability,mlsast_security_architecture,mlsast_git_history --sarif scansuite.sarif')
      }
    }
  }
}
```

## 8. AI SAST on a change request — changed-only, reachable-only

```groovy
@Library('scansuite') _
pipeline {
  agent any
  stages {
    stage('AI SAST (PR)') {
      when { changeRequest() }
      steps {
        scansuiteScan(
          url: 'https://scansuite.example.com', team: 'appsec', product: 'my-service',
          credentialsId: 'scansuite-ci-token',
          changedOnly: true, minConfidence: 'reachable', failOnSeverity: 'high',
          args: '--scanners mlsast --options mlsast_reachability')
      }
    }
  }
}
```

## 9. AI dependency checks (SCA) — reachable-only

```groovy
@Library('scansuite') _
pipeline {
  agent any
  stages {
    stage('AI dependencies') {
      steps {
        scansuiteScan(
          url: 'https://scansuite.example.com', team: 'appsec', product: 'my-service',
          credentialsId: 'scansuite-ci-token',
          minConfidence: 'reachable', failOnSeverity: 'high',
          args: '--scanners dep_checks --options dep_checks_ai,dep_checks_reachability')
      }
    }
  }
}
```

## 10. AI secret scanning — verified, new secrets only

Needs `credential.read` on the token; otherwise add `--fail-on-secrets none` to `args`.

```groovy
@Library('scansuite') _
pipeline {
  agent any
  stages {
    stage('AI secrets') {
      steps {
        scansuiteScan(
          url: 'https://scansuite.example.com', team: 'appsec', product: 'my-service',
          credentialsId: 'scansuite-ci-token',
          failOnSeverity: 'none',
          args: '--scanners secrets --options secrets_ai --fail-on-secrets new')
      }
    }
  }
}
```

## 11. Deep nightly — everything AI, plus the cross-file boundary hunt

```groovy
@Library('scansuite') _
pipeline {
  agent any
  triggers { cron('H 2 * * *') }
  stages {
    stage('AI deep') {
      steps {
        scansuiteScan(
          url: 'https://scansuite.example.com', team: 'appsec', product: 'my-service',
          credentialsId: 'scansuite-ci-token',
          max: 'high=0,critical=0,medium=10',
          args: '''--scanners mlsast,dep_checks,secrets \
                   --options mlsast_reachability,mlsast_security_architecture,mlsast_boundary_hunt,dep_checks_ai,dep_checks_reachability,secrets_ai \
                   --fail-on-secrets all --timeout 14400 --report-zip scansuite-report.zip''')
      }
    }
  }
  post { always { archiveArtifacts allowEmptyArchive: true, artifacts: 'scansuite-report.zip' } }
}
```
