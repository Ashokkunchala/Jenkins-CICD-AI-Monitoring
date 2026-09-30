# CI/CD + AI Monitoring Lab

A small, dependency-light application used to exercise the Jenkins CI/CD + AI Monitoring platform.

## What this lab teaches

- Multibranch Pipeline discovery
- Feature, bugfix, security, release and hotfix workflows
- Build → test → quality → security → package → deploy-simulation
- Intentional failures that should be detected by Jenkins
- AI diagnostic payload generation after a failure
- Jenkins controller → AI agent integration
- Build artifact retention
- Branch-aware pipeline policy
- PR/review gates

## Lab branches

| Branch | Purpose | Expected result |
|---|---|---|
| `main` | Normal production-like flow | PASS |
| `feature/green` | Healthy feature branch | PASS |
| `feature/ai-analysis` | Generate a controlled pipeline warning | PASS + AI analysis |
| `bugfix/test-failure` | Intentional test failure | FAIL + AI analysis |
| `security/sast-demo` | Controlled security finding | FAIL at security gate |
| `release/staging` | Release candidate + staging simulation | PASS |
| `hotfix/rollback-demo` | Failure + rollback simulation | FAIL/rollback path |

The failure branches are deliberately broken for training. Do not merge them into `main`.

## Local test

```bash
python3 -m unittest discover -s tests -v
python3 app.py
```

The application listens on `:8080`.

## Jenkins setup

Create a Jenkins **Multibranch Pipeline** pointing at this Git repository. Configure branch discovery so Jenkins discovers the lab branches automatically.

Recommended credentials:

- `github-token`: GitHub App/token for source discovery where required
- AWS instance/task role for the AI webhook; do not put AWS keys in Jenkins credentials

The Jenkins controller image/AMI should provide `/usr/local/bin/invoke-ai-agent` for live AI integration. If it is unavailable, the pipeline still produces `build/ai-payload.json` so the exercise can be understood without AWS.

## Suggested exercise order

1. Run `main` and inspect all successful stages.
2. Run `feature/green` and compare branch behavior.
3. Run `bugfix/test-failure` and inspect the AI payload and Jenkins console.
4. Run `security/sast-demo` and inspect the security report.
5. Run `feature/ai-analysis` and inspect the advisory AI result.
6. Run `release/staging` and inspect the release artifact.
7. Run `hotfix/rollback-demo` and trace the rollback stage.
8. Create your own branch, introduce a failure, and observe how the AI analysis explains it.

See `../../docs/CI_CD_LAB_CASES.md` for detailed exercises.
