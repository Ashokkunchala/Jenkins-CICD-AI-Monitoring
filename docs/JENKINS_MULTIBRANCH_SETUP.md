# Jenkins Multibranch Lab Setup

## Goal

Create one Jenkins Multibranch Pipeline that automatically creates a Jenkins job for every branch containing `examples/cicd-lab/Jenkinsfile`.

## 1. Create the job

Jenkins → New Item → **Multibranch Pipeline**.

Set:

- Name: `cicd-ai-lab`
- Branch source: Git
- Repository: `Ashokkunchala/Jenkins-CICD-AI-Monitoring`
- Script path: `examples/cicd-lab/Jenkinsfile`

For private repositories, use the appropriate GitHub credential or GitHub App. Do not put a GitHub token inside a Jenkinsfile.

## 2. Branch discovery

Discover all branches while learning.

Later, add pull-request discovery and webhook-driven indexing.

Expected jobs:

```text
cicd-ai-lab/
├── main
├── feature-green
├── feature-ai-analysis
├── bugfix-test-failure
├── security-sast-demo
├── release-staging
└── hotfix-rollback-demo
```

Exact folder names can vary with Jenkins Git plugin configuration.

## 3. Agent labels

The example pipeline uses:

```groovy
agent { label 'amd64' }
```

For ARM testing, duplicate a training branch and change the label to `arm64`.

## 4. AI integration

The production controller should provide:

```text
/usr/local/bin/invoke-ai-agent
```

The script should authenticate to the AI Function URL using the controller's AWS IAM role and SigV4.

Never store AWS access keys in the Jenkinsfile.

## 5. First training run

Run these in order:

1. `main`
2. `feature/green`
3. `feature/ai-analysis`
4. `bugfix/test-failure`
5. `security/sast-demo`
6. `release/staging`
7. `hotfix/rollback-demo`

Compare the stage graph and build results.

## 6. Pull request mode

After branch builds work, enable GitHub pull-request discovery. Open a PR from a training branch and verify that Jenkins validates the change before merge.

Use branch protection so required CI checks must pass before merging production code.

## 7. Recommended production separation

Use separate Multibranch Pipelines or Jenkinsfiles for actual environments when policy differs substantially:

```text
CI validation
    |
    v
artifact creation
    |
    v
staging deployment
    |
    v
approval
    |
    v
production deployment
```

Do not make `main` automatically deploy to production until environment approvals, rollback, monitoring and change controls have been implemented.
