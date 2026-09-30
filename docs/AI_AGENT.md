# AI CI/CD Agent

The AI subsystem is an advisory and automation layer around Jenkins.

## Actions
- `webhook`: validates and bounds Jenkins payloads, then starts the state machine.
- `precheck`: analyzes code diffs.
- `analyze`: analyzes build logs and stages.
- `predict`: identifies recurring failure patterns.
- `classify`: separates development and operations issues.
- `self_fix`: optionally creates a GitHub pull request for low/medium-confidence fixes.
- `notify`: publishes a structured summary.
- `retrain`: generates a trend report from persisted issue history.

## Safety defaults
- IAM authorization for the Function URL.
- Bounded input size.
- Auto-fix disabled by default.
- Fixes are represented as GitHub pull requests.
- Secrets are loaded from Secrets Manager.
- The agent should never receive credentials or private keys in the build payload.

## Suggested Jenkins payload
```json
{
  "build_id": "job-123-42",
  "pipeline": "example-app",
  "status": "FAILURE",
  "stage": "test",
  "branch": "main",
  "commit": "abcdef123456",
  "code_diff": "...",
  "build_log": "...",
  "history": [],
  "remaining_issues": []
}
```

Keep payloads focused on diagnostics. Strip environment variables that may contain secrets before calling the webhook.
