# CI/CD + AI Monitoring Lab — Test Cases

This document is the practical training plan for the repository. Use it after deploying the Jenkins platform.

## 1. Jenkins Multibranch Pipeline

Create one Jenkins Multibranch Pipeline for the repository and point it at the GitHub repository.

Recommended branch discovery:

- Discover all branches
- Discover pull requests from origin
- Periodically scan the repository while learning; webhook-driven indexing can be enabled later

Jenkins should discover:

- `main`
- `feature/green`
- `feature/ai-analysis`
- `bugfix/test-failure`
- `security/sast-demo`
- `release/staging`
- `hotfix/rollback-demo`

The Jenkinsfile is located at `examples/cicd-lab/Jenkinsfile`.

If your Multibranch configuration requires the Jenkinsfile at repository root, use a Pipeline script path of `examples/cicd-lab/Jenkinsfile`.

## 2. Case matrix

| Case | Branch | Expected | What to inspect |
|---|---|---|---|
| C01 | `main` | PASS | Full green pipeline |
| C02 | `feature/green` | PASS | Feature branch isolation |
| C03 | `feature/ai-analysis` | PASS + AI stage | AI payload on healthy build |
| C04 | `bugfix/test-failure` | FAIL | Failure detection + AI diagnostics |
| C05 | `security/sast-demo` | FAIL | Security gate + AI diagnostics |
| C06 | `release/staging` | PASS | Packaging + deployment simulation |
| C07 | `hotfix/rollback-demo` | PASS | Rollback artifact preparation |
| C08 | Pull request | Review gate | Branch discovery + PR validation |
| C09 | Re-run failed build | PASS after fix | Failure history comparison |
| C10 | Agent interruption | Recovery | Spot replacement and node reconnect |
| C11 | AI unavailable | Pipeline continues with payload | Graceful degradation |
| C12 | Large log/diff | Bounded payload | Data minimization |

## 3. C01 — Main pipeline

Run `main`.

Expected stages:

1. Checkout
2. Branch Policy
3. Build
4. Unit Test
5. AI Diagnostic Payload is skipped
6. Package
7. Deploy Simulation

Inspect the archived release artifact.

## 4. C02 — Healthy feature

Run `feature/green`.

Purpose: understand that the same Jenkinsfile can execute independently for multiple branches.

Change a harmless line in the application, commit it, and watch Jenkins create a new branch build.

## 5. C03 — AI analysis on a healthy build

Run `feature/ai-analysis`.

The pipeline intentionally invokes the AI diagnostic payload even though the build is healthy.

Inspect:

- `build/ai-payload.json`
- Jenkins console output
- Lambda logs
- Step Functions execution
- AI analysis result

This demonstrates that AI can be used for proactive pipeline analysis rather than only failure recovery.

## 6. C04 — Controlled test failure

Run `bugfix/test-failure`.

The pipeline deliberately fails after the unit-test stage.

Expected behavior:

- Build becomes failed.
- AI diagnostic payload is generated.
- The helper attempts the IAM/SigV4 AI invocation.
- Payload is archived even when the AI service is unavailable.
- The failure remains visible to the engineer; AI does not silently turn a failed build green.

This is an important production principle: **AI is advisory; the CI gate remains authoritative.**

## 7. C05 — Security gate failure

Run `security/sast-demo`.

The branch contains a controlled training marker. The security stage detects it and fails.

Use this case to understand:

- security gates
- failed-stage diagnostics
- artifact retention
- AI-assisted remediation analysis
- PR review before merge

Do not copy the training marker into production code.

## 8. C06 — Release candidate

Run `release/staging`.

Expected:

- build
- test
- package
- deployment simulation
- release artifact

In a real environment, replace the simulation with a deployment job protected by an environment approval and an immutable artifact reference.

## 9. C07 — Hotfix and rollback

Run `hotfix/rollback-demo`.

The pipeline prepares a rollback artifact.

Discuss with the team:

- What version is being rolled back?
- Where is the immutable artifact?
- Who approves rollback?
- How is database compatibility handled?
- How do we verify service health after rollback?

## 10. C08 — Pull request exercise

Create a branch from `main`, modify `examples/cicd-lab/app.py`, and open a pull request.

Expected flow:

```text
Developer branch
      |
      v
Pull Request
      |
      v
Jenkins validation
      |
      +---- build
      +---- test
      +---- security
      +---- AI analysis
      |
      v
Human review
      |
      v
Merge to main
```

## 11. C09 — Failure → fix → comparison

1. Run `bugfix/test-failure`.
2. Save the Jenkins build number and AI payload.
3. Fix the defect on a new branch.
4. Run the pipeline again.
5. Compare the two build logs and AI analyses.

This is the basic feedback loop for the AI monitoring system.

## 12. C10 — Spot agent interruption

During a long-running training build, terminate the active Spot agent from AWS.

Observe:

- Jenkins node disconnect
- ASG replacement
- new agent registration
- retry/rebuild behavior
- CloudWatch events/logs

Do not perform this exercise against a real production workload.

## 13. C11 — AI service unavailable

Temporarily make the AI helper unavailable on a test controller.

Expected behavior:

- Jenkins build result remains authoritative.
- AI failure does not expose credentials.
- Diagnostic payload remains archived.
- Engineer can manually inspect the failure.

The CI/CD platform must remain useful when the AI layer is down.

## 14. C12 — Data minimization

Create a test failure with a large log or diff.

Verify that the AI payload is bounded and does not contain:

- AWS access keys
- GitHub tokens
- passwords
- private keys
- secret environment variables

## 15. Observability checklist

For each failed case inspect:

### Jenkins
- Build number
- Branch
- Stage that failed
- Console log
- Archived AI payload
- Agent used

### AWS
- CloudWatch Jenkins logs
- Lambda logs
- Step Functions execution
- SNS notifications when configured
- EC2/ASG state

### AI
- Request ID
- Input size
- Failure classification
- Suggested remediation
- Confidence/uncertainty
- Whether an auto-fix was proposed

## 16. Production learning rules

1. Never allow AI to bypass mandatory security gates.
2. Never give the AI agent unnecessary credentials.
3. Never send raw secrets to the AI model.
4. Never let generated fixes merge directly without review.
5. Keep build artifacts immutable.
6. Keep deployment credentials separate from build credentials.
7. Make rollback a tested workflow, not a manual hope.
8. Treat Spot interruption as a normal infrastructure event.
9. Keep AI failure independent from CI availability.
10. Measure AI recommendations against actual engineer outcomes.
