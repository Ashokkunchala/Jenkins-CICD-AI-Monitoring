import base64
import json
import logging
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from functools import lru_cache

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

bedrock = boto3.client("bedrock-runtime")
dynamodb = boto3.resource("dynamodb")
sns = boto3.client("sns")
sfn = boto3.client("stepfunctions")
secrets = boto3.client("secretsmanager")

MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "anthropic.claude-3-haiku-20240307-v1:0")
SNS_TOPIC = os.environ.get("SNS_TOPIC_ARN", "")
ISSUES_TABLE = os.environ.get("ISSUES_TABLE", "")
PREDICTIONS_TABLE = os.environ.get("PREDICTIONS_TABLE", "")
STATE_MACHINE_ARN = os.environ.get("STATE_MACHINE_ARN", "")
GITHUB_SECRET_ARN = os.environ.get("GITHUB_SECRET_ARN", "")
GITHUB_OWNER = os.environ.get("GITHUB_OWNER", "")
GITHUB_REPO = os.environ.get("GITHUB_REPO", "")
GITHUB_BASE_BRANCH = os.environ.get("GITHUB_BASE_BRANCH", "main")
GITHUB_AUTO_FIX_ENABLED = os.environ.get("GITHUB_AUTO_FIX_ENABLED", "false").lower() == "true"
MAX_EXECUTION_INPUT_BYTES = 240000

issues_table = dynamodb.Table(ISSUES_TABLE) if ISSUES_TABLE else None
predictions_table = dynamodb.Table(PREDICTIONS_TABLE) if PREDICTIONS_TABLE else None

SYSTEM_PROMPT = """You are an expert CI/CD DevOps AI agent. Your responsibilities:
1. Pre-check code for syntax errors, security vulnerabilities, and common bugs
2. Analyze build stages for failures and bottlenecks
3. Predict potential future issues based on code patterns and build history
4. Generate safe, reviewable patches for low and medium severity issues when auto-fix is explicitly enabled
5. Classify remaining issues: DEV or OPS
6. Provide clear, actionable summaries

For each analysis, return JSON with severity (low, medium, high, or critical), category, fix_suggestion, and auto_fixable (boolean)."""


def lambda_handler(event, context):
    action = event.get("action", "webhook") if isinstance(event, dict) else "webhook"
    request_id = getattr(context, "aws_request_id", "unknown")
    logger.info("AI agent action=%s request_id=%s", action, request_id)

    try:
        if action == "webhook":
            return handle_webhook(event)
        if action == "precheck":
            return precheck_code(event)
        if action == "analyze":
            return analyze_build(event)
        if action == "predict":
            return predict_issues(event)
        if action == "self_fix":
            return self_fix(event)
        if action == "classify":
            return classify_issues(event)
        if action == "notify":
            return notify(event)
        if action == "retrain":
            return retrain_model(event)
        return {"status": "error", "message": f"Unknown action: {action}"}
    except Exception as error:
        logger.exception("AI agent action failed: %s", action)
        if action == "webhook":
            return {
                "statusCode": 500,
                "body": json.dumps({"error": "Unable to start the CI/CD analysis"}),
            }
        raise error


def compact_input_items(items):
    compacted = []
    for item in items[:100]:
        encoded = json.dumps(item, default=str)
        if len(encoded) > 4000:
            item = {"summary": encoded[:4000]}
        compacted.append(item)
    return compacted


def limit_execution_input(execution_input):
    while len(json.dumps(execution_input, default=str).encode("utf-8")) > MAX_EXECUTION_INPUT_BYTES:
        if len(execution_input.get("code_diff", "")) > 10000:
            execution_input["code_diff"] = execution_input["code_diff"][: len(execution_input["code_diff"]) // 2]
        elif len(execution_input.get("build_log", "")) > 10000:
            execution_input["build_log"] = execution_input["build_log"][: len(execution_input["build_log"]) // 2]
        elif execution_input.get("history"):
            execution_input["history"] = execution_input["history"][:-1]
        elif execution_input.get("remaining_issues"):
            execution_input["remaining_issues"] = execution_input["remaining_issues"][:-1]
        else:
            break
    return execution_input


def handle_webhook(event):
    body = event.get("body", {}) if isinstance(event, dict) else {}
    if isinstance(body, str):
        try:
            if event.get("isBase64Encoded"):
                body = base64.b64decode(body)
            body = json.loads(body)
        except (ValueError, TypeError, json.JSONDecodeError):
            body = {}

    if not isinstance(body, dict):
        body = {}

    if not STATE_MACHINE_ARN:
        return {
            "statusCode": 500,
            "body": json.dumps({"error": "Workflow is not configured"}),
        }

    execution_input = limit_execution_input(
        {
            "build_id": str(body.get("build_id", "unknown"))[:200],
            "pipeline": str(body.get("pipeline", "unknown"))[:200],
            "status": str(body.get("status", "unknown"))[:100],
            "code_diff": str(body.get("code_diff", ""))[:100000],
            "build_log": str(body.get("build_log", ""))[:100000],
            "stage": str(body.get("stage", ""))[:200],
            "branch": str(body.get("branch", "main"))[:200],
            "commit": str(body.get("commit", ""))[:200],
            "history": compact_input_items(body.get("history", []))
            if isinstance(body.get("history", []), list)
            else [],
            "remaining_issues": compact_input_items(body.get("remaining_issues", []))
            if isinstance(body.get("remaining_issues", []), list)
            else [],
            "timestamp": int(time.time()),
        }
    )
    execution = sfn.start_execution(
        stateMachineArn=STATE_MACHINE_ARN,
        input=json.dumps(execution_input),
    )

    return {
        "statusCode": 200,
        "body": json.dumps(
            {
                "execution_arn": execution["executionArn"],
                "message": "Pipeline started",
            }
        ),
    }


def call_bedrock(prompt, system=SYSTEM_PROMPT):
    try:
        body = json.dumps(
            {
                "anthropic_version": "bedrock-2023-05-31",
                "max_tokens": 4096,
                "system": system,
                "messages": [{"role": "user", "content": prompt}],
            }
        )
        response = bedrock.invoke_model(
            modelId=MODEL_ID,
            contentType="application/json",
            accept="application/json",
            body=body,
        )
        result = json.loads(response["body"].read())
        return result["content"][0]["text"]
    except Exception as error:
        logger.error("Bedrock invocation failed: %s", type(error).__name__)
        return json.dumps(
            {
                "error": "AI analysis failed",
                "issues": [],
                "predictions": [],
                "fixable": [],
                "summary": "AI analysis failed",
            }
        )


def parse_json(value, fallback):
    try:
        parsed = json.loads(value)
        return parsed if isinstance(parsed, type(fallback)) else fallback
    except (TypeError, ValueError, json.JSONDecodeError):
        return fallback


def precheck_code(event):
    code_diff = event.get("code_diff", "")
    if not code_diff:
        return {"issues": [], "summary": "No code changes to check", "score": 100}

    prompt = f"""Analyze this code diff for syntax errors, security vulnerabilities, bugs, and code quality issues.
Return a JSON object with issues: array of {{severity, category, file, line, description, fix_suggestion, auto_fixable}}, summary, and score from 0 to 100.

Code diff:
```diff
{code_diff[:10000]}
```"""
    result = parse_json(
        call_bedrock(prompt),
        {"issues": [], "summary": "AI analysis failed", "score": 0},
    )
    save_issues(event.get("build_id", "unknown"), result, event.get("pipeline", "cicd"))
    return result


def analyze_build(event):
    build_log = event.get("build_log", "")
    stage = event.get("stage", "")
    precheck = event.get("precheck_result", {})
    prompt = f"""Analyze this build log for stage "{stage}".
Return JSON with issues, stage_status, duration_estimate, optimization_tips, and summary.

Build log:
```
{build_log[:10000]}
```

Pre-check results: {json.dumps(precheck, default=str)}"""
    fallback = {
        "issues": [],
        "stage_status": "unknown",
        "summary": "AI analysis failed",
    }
    return parse_json(call_bedrock(prompt), fallback)


def predict_issues(event):
    analysis = event.get("analysis", {})
    history = event.get("history", [])
    prompt = f"""Based on this build analysis and historical patterns, predict potential future issues.
Return JSON with predictions: array of {{issue, probability, impact, timeframe, prevention}}, fixable: array of {{severity, file, description, issue, patch}}, and summary.

Analysis: {json.dumps(analysis, default=str)}
History: {json.dumps(history[:5], default=str)}"""
    fallback = {"predictions": [], "fixable": [], "summary": "AI analysis failed"}
    result = parse_json(call_bedrock(prompt), fallback)
    save_predictions(event.get("build_id", "unknown"), result)
    return result


def self_fix(event):
    if not GITHUB_AUTO_FIX_ENABLED or not GITHUB_SECRET_ARN or not GITHUB_OWNER or not GITHUB_REPO:
        return {
            "fixed": [],
            "failed": [],
            "skipped": True,
            "summary": "Auto-fix is disabled or GitHub is not configured",
        }

    candidates = event.get("fixable_issues", [])
    if not isinstance(candidates, list):
        candidates = []
    fixable = [
        issue
        for issue in candidates[:5]
        if isinstance(issue, dict) and issue.get("severity", "").lower() in {"low", "medium"}
    ]
    code_diff = event.get("code_diff", "")
    fixed = []
    failed = []

    for issue in fixable:
        prompt = f"""Generate a git patch to fix this issue:
Issue: {json.dumps(issue, default=str)}
Code context:
```
{code_diff[:5000]}
```
Return ONLY a unified patch starting with diff --git."""
        patch = call_bedrock(
            prompt,
            "You are a code fixer. Generate precise, reviewable patches. Return ONLY the patch.",
        )
        try:
            if patch and "diff --git" in patch:
                create_github_pull_request(issue, patch)
                fixed.append(issue)
            else:
                failed.append(issue)
        except Exception as error:
            logger.error("GitHub auto-fix failed: %s", type(error).__name__)
            failed.append(issue)

    return {
        "fixed": fixed,
        "failed": failed,
        "skipped": False,
        "summary": f"Fixed {len(fixed)}, failed {len(failed)}",
    }


def classify_issues(event):
    remaining_issues = event.get("remaining_issues", [])
    if not isinstance(remaining_issues, list):
        remaining_issues = []
    if not remaining_issues:
        for result_key in ("precheck_result", "analysis", "fix_result"):
            result = event.get(result_key, {})
            if isinstance(result, dict) and isinstance(result.get("issues"), list):
                remaining_issues.extend(result["issues"])
    prompt = f"""Classify each issue as DEV (developer code, syntax, or feature bugs) or OPS (infrastructure, configuration, pipeline, or deployment).
Return JSON with dev_issues, ops_issues, dev_assignees, ops_assignees, and summary.
Issues: {json.dumps(remaining_issues, default=str)}"""
    fallback = {
        "dev_issues": remaining_issues,
        "ops_issues": [],
        "summary": "AI analysis failed",
    }
    return parse_json(call_bedrock(prompt), fallback)


def notify(event):
    payload = event.get("payload", event)
    if not isinstance(payload, dict):
        payload = {}
    precheck = payload.get("precheck_result", {})
    analysis = payload.get("analysis", {})
    fix_result = payload.get("fix_result", {})
    classification = payload.get("classification", {})
    summary = payload.get("summary")
    if not isinstance(summary, dict):
        summary = {}
    else:
        summary = dict(summary)
    if isinstance(precheck, dict):
        summary.setdefault("issues", precheck.get("issues", []))
        summary.setdefault("score", precheck.get("score", "N/A"))
        summary.setdefault("summary", precheck.get("summary", "No summary"))
    if isinstance(analysis, dict):
        summary.setdefault("analysis", analysis)
    if isinstance(fix_result, dict):
        summary.setdefault("fixed", fix_result.get("fixed", []))
    if isinstance(classification, dict):
        summary.setdefault("dev_issues", classification.get("dev_issues", []))
        summary.setdefault("ops_issues", classification.get("ops_issues", []))
    summary.setdefault("build_id", payload.get("build_id", "unknown"))
    message = format_alert_message(summary)

    if SNS_TOPIC:
        sns.publish(
            TopicArn=SNS_TOPIC,
            Subject=f"[CI/CD Agent] Build Analysis - {summary.get('score', 'N/A')}/100",
            Message=json.dumps(
                {
                    "default": message,
                    "email": message,
                    "https": json.dumps(
                        {
                            "@type": "MessageCard",
                            "@context": "http://schema.org/extensions",
                            "themeColor": get_theme_color(summary.get("score", 50)),
                            "title": f"CI/CD Agent: Build {summary.get('build_id', 'unknown')}",
                            "text": message,
                        }
                    ),
                }
            ),
            MessageStructure="json",
        )

    return {"status": "notified", "summary": summary}


def save_issues(build_id, data, pipeline="cicd"):
    if issues_table is None:
        return
    try:
        issues_table.put_item(
            Item={
                "build_id": str(build_id),
                "pipeline": str(pipeline)[:200],
                "issues": data.get("issues", []),
                "score": data.get("score", 0),
                "summary": data.get("summary", ""),
                "timestamp": int(time.time()),
            }
        )
    except Exception as error:
        logger.error("DynamoDB issue save failed: %s", type(error).__name__)


def save_predictions(build_id, data):
    if predictions_table is None:
        return
    try:
        predictions_table.put_item(
            Item={
                "prediction_id": f"{build_id}-{int(time.time())}",
                "build_id": str(build_id),
                "predictions": data.get("predictions", []),
                "fixable": data.get("fixable", []),
                "summary": data.get("summary", ""),
                "ttl": int(time.time()) + 2592000,
            }
        )
    except Exception as error:
        logger.error("DynamoDB prediction save failed: %s", type(error).__name__)


def retrain_model(event):
    if issues_table is None:
        return {"status": "skipped", "message": "Issues table is not configured"}

    try:
        items = []
        scan_kwargs = {}
        while len(items) < 50:
            response = issues_table.scan(Limit=50, **scan_kwargs)
            items.extend(response.get("Items", []))
            last_key = response.get("LastEvaluatedKey")
            if not last_key or len(items) >= 50:
                break
            scan_kwargs["ExclusiveStartKey"] = last_key
        items = items[:50]
        prompt = f"""Analyze this build history and generate a trend report with common failure patterns, process improvements, prediction accuracy, and action items.
History: {json.dumps(items, default=str)}"""
        return {"status": "retrained", "report": call_bedrock(prompt)}
    except Exception as error:
        logger.error("Retrain failed: %s", type(error).__name__)
        return {"status": "error", "message": "Retrain failed"}


@lru_cache(maxsize=1)
def get_github_token():
    if not GITHUB_SECRET_ARN:
        return ""
    response = secrets.get_secret_value(SecretId=GITHUB_SECRET_ARN)
    return response.get("SecretString", "")


def github_request(path, method="GET", payload=None):
    token = get_github_token()
    if not token:
        raise RuntimeError("GitHub token is not configured")
    request = urllib.request.Request(
        f"https://api.github.com{path}",
        data=json.dumps(payload).encode() if payload is not None else None,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "Content-Type": "application/json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
        method=method,
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.loads(response.read().decode())


def safe_branch_component(value):
    value = re.sub(r"[^A-Za-z0-9._-]+", "-", str(value)).strip("-.")
    return value[:60] or "build"


def patch_paths(patch):
    paths = []
    for line in patch.splitlines():
        match = re.match(r"diff --git a/(.+) b/(.+)", line)
        if match and match.group(2) not in paths:
            paths.append(match.group(2))
    return paths


def create_github_pull_request(issue, patch):
    owner = urllib.parse.quote(GITHUB_OWNER, safe="")
    repo = urllib.parse.quote(GITHUB_REPO, safe="")
    base_branch = GITHUB_BASE_BRANCH or "main"
    base_ref = github_request(
        f"/repos/{owner}/{repo}/git/ref/heads/{urllib.parse.quote(base_branch, safe='')}"
    )
    base_sha = base_ref["object"]["sha"]
    paths = patch_paths(patch)
    if not paths:
        raise ValueError("Patch did not contain any files")

    original_files = {}
    existing_files = {}
    for path in paths:
        encoded_path = urllib.parse.quote(path, safe="/")
        try:
            existing = github_request(
                f"/repos/{owner}/{repo}/contents/{encoded_path}?ref={urllib.parse.quote(base_branch, safe='')}"
            )
        except urllib.error.HTTPError as error:
            if error.code != 404:
                raise
            existing = {}
        existing_files[path] = existing
        if existing.get("content"):
            original_files[path] = base64.b64decode(existing["content"]).decode()
        else:
            original_files[path] = ""

    files = parse_patch_files(patch, original_files)
    if not files:
        raise ValueError("Patch did not contain any applicable files")

    branch = f"ai-fix/{safe_branch_component(issue.get('file', 'build'))}-{int(time.time())}"
    github_request(
        f"/repos/{owner}/{repo}/git/refs",
        method="POST",
        payload={"ref": f"refs/heads/{branch}", "sha": base_sha},
    )

    for path, content in files.items():
        encoded_path = urllib.parse.quote(path, safe="/")
        existing = existing_files[path]
        payload = {
            "message": f"AI fix: {path}",
            "content": base64.b64encode(content.encode()).decode(),
            "branch": branch,
        }
        if "sha" in existing:
            payload["sha"] = existing["sha"]
        if content == "":
            if "sha" not in existing:
                continue
            github_request(
                f"/repos/{owner}/{repo}/contents/{encoded_path}",
                method="DELETE",
                payload={"message": f"AI fix: remove {path}", "branch": branch, "sha": existing["sha"]},
            )
        else:
            github_request(f"/repos/{owner}/{repo}/contents/{encoded_path}", method="PUT", payload=payload)

    title = f"[AI-FIX] {str(issue.get('description', 'Automated fix'))[:80]}"
    body = f"Automated fix by the CI/CD AI agent.\n\nIssue: {json.dumps(issue, default=str)}\n\n```diff\n{patch[:100000]}\n```"
    pull_request = github_request(
        f"/repos/{owner}/{repo}/pulls",
        method="POST",
        payload={"title": title, "body": body, "head": branch, "base": base_branch},
    )
    return pull_request["html_url"]


def parse_patch_files(patch, original_files=None):
    original_files = original_files or {}
    files = {}
    current = None
    lines = []
    for line in patch.splitlines():
        match = re.match(r"diff --git a/(.+) b/(.+)", line)
        if match:
            if current:
                files[current] = apply_patch_to_file(original_files.get(current, ""), lines)
            current = match.group(2)
            lines = []
            continue
        if current:
            lines.append(line)
    if current:
        files[current] = apply_patch_to_file(original_files.get(current, ""), lines)
    return {path: content for path, content in files.items() if content is not None}


def apply_patch_to_file(original, patch_lines):
    source = original.splitlines(keepends=True)
    output = []
    source_index = 0
    index = 0
    while index < len(patch_lines):
        line = patch_lines[index]
        match = re.match(r"@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", line)
        if not match:
            index += 1
            continue
        old_start = int(match.group(1)) - 1
        if old_start < source_index or old_start > len(source):
            return None
        output.extend(source[source_index:old_start])
        source_index = old_start
        index += 1
        while index < len(patch_lines) and not patch_lines[index].startswith("@@"):
            patch_line = patch_lines[index]
            if patch_line.startswith("+"):
                output.append(patch_line[1:] + "\n")
            elif patch_line.startswith("-"):
                if source_index >= len(source) or source[source_index].rstrip("\n") != patch_line[1:]:
                    return None
                source_index += 1
            elif patch_line.startswith(" "):
                if source_index >= len(source) or source[source_index].rstrip("\n") != patch_line[1:]:
                    return None
                output.append(source[source_index])
                source_index += 1
            index += 1
    output.extend(source[source_index:])
    return "".join(output)


def format_alert_message(summary):
    issues = summary.get("issues", [])
    fixed = summary.get("fixed", [])
    dev_issues = summary.get("dev_issues", [])
    ops_issues = summary.get("ops_issues", [])
    lines = [
        "=== CI/CD AI Agent Report ===",
        f"Build: {summary.get('build_id', 'N/A')}",
        f"Score: {summary.get('score', 'N/A')}/100",
        f"Issues found: {len(issues) if isinstance(issues, list) else 0}",
        f"Auto-fixed: {len(fixed) if isinstance(fixed, list) else 0}",
        "",
        "--- Summary ---",
        str(summary.get("summary", "No summary")),
        "",
        "--- DEV Issues ---",
    ]
    for issue in dev_issues if isinstance(dev_issues, list) else []:
        lines.append(f"  - {issue.get('description', str(issue))} [{issue.get('severity', 'unknown')}]")
    lines.extend(["", "--- OPS Issues ---"])
    for issue in ops_issues if isinstance(ops_issues, list) else []:
        lines.append(f"  - {issue.get('description', str(issue))} [{issue.get('severity', 'unknown')}]")
    return "\n".join(lines)


def get_theme_color(score):
    try:
        numeric_score = float(score)
    except (TypeError, ValueError):
        numeric_score = 50
    if numeric_score >= 80:
        return "00FF00"
    if numeric_score >= 50:
        return "FFA500"
    return "FF0000"
