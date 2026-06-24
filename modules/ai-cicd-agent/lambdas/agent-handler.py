import os
import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

bedrock = boto3.client("bedrock-runtime")
dynamodb = boto3.resource("dynamodb")
sns = boto3.client("sns")
sfn = boto3.client("stepfunctions")

MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "anthropic.claude-3-haiku-20240307-v1:0")
SNS_TOPIC = os.environ.get("SNS_TOPIC_ARN", "")
ISSUES_TABLE = os.environ.get("ISSUES_TABLE", "")
PREDICTIONS_TABLE = os.environ.get("PREDICTIONS_TABLE", "")
GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "")
GITHUB_OWNER = os.environ.get("GITHUB_OWNER", "")
GITHUB_REPO = os.environ.get("GITHUB_REPO", "")

issues_table = dynamodb.Table(ISSUES_TABLE)
predictions_table = dynamodb.Table(PREDICTIONS_TABLE)

SYSTEM_PROMPT = """You are an expert CI/CD DevOps AI agent. Your responsibilities:
1. Pre-check code for syntax errors, security vulnerabilities, and common bugs
2. Analyze build stages for failures and bottlenecks
3. Predict potential future issues based on code patterns and build history
4. Self-fix low to medium severity issues by generating patches
5. Classify remaining issues: DEV (logic, syntax, feature bugs) or OPS (infra, config, pipeline)
6. Provide clear, actionable summaries

For each analysis, return JSON with: severity (low/medium/high/critical), category (code/build/test/infra/security/performance), fix_suggestion, and auto_fixable (boolean)."""


def lambda_handler(event, context):
    logger.info(f"Event: {json.dumps(event)}")

    action = event.get("action", "webhook")

    if action == "webhook":
        return handle_webhook(event)
    elif action == "precheck":
        return precheck_code(event)
    elif action == "analyze":
        return analyze_build(event)
    elif action == "predict":
        return predict_issues(event)
    elif action == "self_fix":
        return self_fix(event)
    elif action == "classify":
        return classify_issues(event)
    elif action == "notify":
        return notify(event)
    elif action == "retrain":
        return retrain_model(event)
    else:
        return {"status": "error", "message": f"Unknown action: {action}"}


def handle_webhook(event):
    """Entry point from Jenkins webhook. Start Step Functions execution."""
    body = event.get("body", {})
    if isinstance(body, str):
        try:
            body = json.loads(body)
        except json.JSONDecodeError:
            body = {}

    state_machine_arn = body.get("state_machine_arn", event.get("state_machine_arn", ""))
    if not state_machine_arn:
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "state_machine_arn required in webhook payload"})
        }

    execution = sfn.start_execution(
        stateMachineArn=state_machine_arn,
        input=json.dumps({
            "build_id": body.get("build_id", "unknown"),
            "pipeline": body.get("pipeline", "unknown"),
            "status": body.get("status", "unknown"),
            "code_diff": body.get("code_diff", ""),
            "build_log": body.get("build_log", ""),
            "stage": body.get("stage", ""),
            "branch": body.get("branch", "main"),
            "commit": body.get("commit", ""),
            "timestamp": context.aws_request_id
        })
    )

    return {
        "statusCode": 200,
        "body": json.dumps({
            "execution_arn": execution["executionArn"],
            "message": "Pipeline started"
        })
    }


def call_bedrock(prompt, system=SYSTEM_PROMPT):
    """Invoke Claude Haiku via Bedrock."""
    try:
        body = json.dumps({
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 4096,
            "system": system,
            "messages": [{"role": "user", "content": prompt}]
        })

        response = bedrock.invoke_model(
            modelId=MODEL_ID,
            contentType="application/json",
            accept="application/json",
            body=body
        )

        result = json.loads(response["body"].read())
        content = result["content"][0]["text"]
        return content
    except Exception as e:
        logger.error(f"Bedrock error: {e}")
        return json.dumps({"error": str(e), "issues": [], "summary": "AI analysis failed"})


def precheck_code(event):
    """Pre-check code diff for issues."""
    code_diff = event.get("code_diff", "")
    if not code_diff:
        return {"issues": [], "summary": "No code changes to check"}

    prompt = f"""Analyze this code diff for syntax errors, security vulnerabilities, bugs, and code quality issues.
Return a JSON object with:
- issues: array of {{severity, category, file, line, description, fix_suggestion, auto_fixable}}
- summary: brief overview
- score: 0-100 quality score

Code diff:
```diff
{code_diff[:10000]}
```"""

    result = call_bedrock(prompt)
    try:
        parsed = json.loads(result)
    except json.JSONDecodeError:
        parsed = {"issues": [], "summary": result, "score": 50}

    save_issues(event.get("build_id", "unknown"), parsed)
    return parsed


def analyze_build(event):
    """Analyze build stage output."""
    build_log = event.get("build_log", "")
    stage = event.get("stage", "")
    precheck = event.get("precheck_result", {})

    prompt = f"""Analyze this build log for stage "{stage}".
Identify failures, warnings, bottlenecks, and areas for optimization.
Return JSON: {{issues, stage_status, duration_estimate, optimization_tips, summary}}

Build log:
```
{build_log[:10000]}
```

Pre-check results: {json.dumps(precheck)}"""

    result = call_bedrock(prompt)
    try:
        return json.loads(result)
    except json.JSONDecodeError:
        return {"issues": [], "stage_status": "unknown", "summary": result}


def predict_issues(event):
    """Predict future issues from patterns."""
    analysis = event.get("analysis", {})
    history = event.get("history", [])

    prompt = f"""Based on this build analysis and historical patterns, predict potential future issues.
Return JSON: {{predictions: [{{issue, probability, impact, timeframe, prevention}}], fixable: [{{issue, patch}}], summary}}

Analysis: {json.dumps(analysis)}
History: {json.dumps(history[:5])}"""

    result = call_bedrock(prompt)
    try:
        parsed = json.loads(result)
    except json.JSONDecodeError:
        parsed = {"predictions": [], "fixable": [], "summary": result}

    save_predictions(event.get("build_id", "unknown"), parsed)
    return parsed


def self_fix(event):
    """Auto-fix low/medium issues."""
    fixable = event.get("fixable_issues", [])
    code_diff = event.get("code_diff", "")
    fixed = []
    failed = []

    for issue in fixable[:5]:
        prompt = f"""Generate a git patch to fix this issue:

Issue: {json.dumps(issue)}

Code context:
```
{code_diff[:5000]}
```

Return ONLY the patch/diff in unified format starting with 'diff --git'."""

        patch = call_bedrock(prompt, "You are a code fixer. Generate precise git patches. Return ONLY the patch.")
        try:
            if patch and "diff --git" in patch:
                apply_patch_via_github(issue, patch)
                fixed.append(issue)
            else:
                failed.append(issue)
        except Exception as e:
            logger.error(f"Failed to apply patch: {e}")
            failed.append(issue)

    return {"fixed": fixed, "failed": failed, "summary": f"Fixed {len(fixed)}, failed {len(failed)}"}


def classify_issues(event):
    """Classify remaining issues as DEV or OPS."""
    remaining = event.get("remaining_issues", [])
    if not remaining:
        remaining = []

    prompt = f"""Classify each issue as DEV (developer: code logic, syntax, feature bugs) or OPS (devops: infra, config, pipeline, deployment).
Return JSON: {{dev_issues: [...], ops_issues: [...], dev_assignees: [...], ops_assignees: [...], summary}}

Issues: {json.dumps(remaining)}"""

    result = call_bedrock(prompt)
    try:
        return json.loads(result)
    except json.JSONDecodeError:
        return {"dev_issues": remaining, "ops_issues": [], "summary": result}


def notify(event):
    """Send alert via SNS."""
    summary = event.get("summary", {})

    message = format_alert_message(summary)

    if SNS_TOPIC:
        sns.publish(
            TopicArn=SNS_TOPIC,
            Subject=f"[CI/CD Agent] Build Analysis - {summary.get('score', 'N/A')}/100",
            Message=json.dumps({
                "default": message,
                "email": message,
                "https": json.dumps({
                    "@type": "MessageCard",
                    "@context": "http://schema.org/extensions",
                    "themeColor": get_theme_color(summary.get("score", 50)),
                    "title": f"CI/CD Agent: Build {summary.get('build_id', 'unknown')}",
                    "text": message,
                    "sections": [
                        {
                            "facts": [
                                {"name": "Score", "value": str(summary.get("score", "N/A"))},
                                {"name": "Issues", "value": str(len(summary.get("issues", [])))},
                                {"name": "Auto-fixed", "value": str(len(summary.get("fixed", [])))},
                                {"name": "Dev Issues", "value": str(len(summary.get("dev_issues", [])))},
                                {"name": "Ops Issues", "value": str(len(summary.get("ops_issues", [])))}
                            ]
                        }
                    ]
                })
            }),
            MessageStructure="json"
        )

    return {"status": "notified", "summary": summary}


def save_issues(build_id, data):
    """Persist issues to DynamoDB."""
    try:
        issues_table.put_item(Item={
            "build_id": build_id,
            "pipeline": "cicd",
            "issues": data.get("issues", []),
            "score": data.get("score", 0),
            "summary": data.get("summary", ""),
            "timestamp": int(__import__("time").time())
        })
    except Exception as e:
        logger.error(f"DynamoDB save error: {e}")


def save_predictions(build_id, data):
    """Persist predictions to DynamoDB."""
    try:
        import time
        predictions_table.put_item(Item={
            "prediction_id": f"{build_id}-{int(time.time())}",
            "build_id": build_id,
            "predictions": data.get("predictions", []),
            "fixable": data.get("fixable", []),
            "summary": data.get("summary", ""),
            "ttl": int(time.time()) + 2592000
        })
    except Exception as e:
        logger.error(f"DynamoDB predict save error: {e}")


def retrain_model(event):
    """Weekly retrain: scan history and generate trend report."""
    try:
        response = issues_table.scan()
        items = response.get("Items", [])

        prompt = f"""Analyze this build history and generate a trend report with:
1. Most common failure patterns
2. Recommended process improvements
3. Prediction accuracy assessment
4. Action items

History: {json.dumps(items[-50:])}"""

        report = call_bedrock(prompt)
        return {"status": "retrained", "report": report}
    except Exception as e:
        return {"status": "error", "message": str(e)}


def apply_patch_via_github(issue, patch):
    """Apply fix via GitHub API."""
    if not (GITHUB_TOKEN and GITHUB_OWNER and GITHUB_REPO):
        logger.warning("GitHub credentials not configured, skipping auto-fix")
        return

    import urllib.request
    import base64

    headers = {
        "Authorization": f"token {GITHUB_TOKEN}",
        "Accept": "application/vnd.github.v3+json",
        "Content-Type": "application/json"
    }

    data = json.dumps({
        "title": f"[AI-FIX] {issue.get('description', 'Auto-fix')[:50]}",
        "body": f"Auto-generated fix by CI/CD AI Agent\n\nIssue: {json.dumps(issue)}\n\nPatch:\n```diff\n{patch}\n```",
        "head": f"ai-fix/{int(__import__('time').time())}",
        "base": "main"
    }).encode()

    req = urllib.request.Request(
        f"https://api.github.com/repos/{GITHUB_OWNER}/{GITHUB_REPO}/pulls",
        data=data, headers=headers, method="POST"
    )
    urllib.request.urlopen(req)


def format_alert_message(summary):
    lines = [
        "=== CI/CD AI Agent Report ===",
        f"Build: {summary.get('build_id', 'N/A')}",
        f"Score: {summary.get('score', 'N/A')}/100",
        f"Issues found: {len(summary.get('issues', []))}",
        f"Auto-fixed: {len(summary.get('fixed', []))}",
        "",
        "--- Summary ---",
        summary.get("summary", "No summary"),
        "",
        "--- DEV Issues ---",
    ]

    for i in summary.get("dev_issues", []):
        lines.append(f"  - {i.get('description', str(i))} [{i.get('severity', 'unknown')}]")

    lines.append("")
    lines.append("--- OPS Issues ---")
    for i in summary.get("ops_issues", []):
        lines.append(f"  - {i.get('description', str(i))} [{i.get('severity', 'unknown')}]")

    return "\n".join(lines)


def get_theme_color(score):
    if score >= 80:
        return "00FF00"
    elif score >= 50:
        return "FFA500"
    return "FF0000"
