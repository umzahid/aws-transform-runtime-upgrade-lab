# Lambda Runtime Upgrade POC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove AWS Transform's managed `AWS/lambda-nodejs-runtime-upgrade` transformation works end to end by upgrading a real toy Lambda function's runtime in place, with matching invoke output before and after.

**Architecture:** A toy Node.js Lambda handler lives in `poc/lambda/`, which is deployed twice via plain AWS CLI shell scripts (`poc/scripts/`) to the same real Lambda function — once on an old runtime, once after `atx` transforms the code and we redeploy on the new runtime. A local test file doubles as `atx`'s own validation gate.

**Tech Stack:** Node.js (Lambda handler), Bash + AWS CLI v2 (deploy/invoke/teardown), `atx` CLI (AWS Transform custom).

**Spec:** `docs/superpowers/specs/2026-08-27-lambda-runtime-upgrade-poc-design.md`

## Global Constraints

- AWS profile: `default` (account `043309363336`, region `us-east-1`) — already re-authenticated.
- Lambda function name: `atx-poc-lambda-runtime-upgrade`. IAM role name: `atx-poc-lambda-runtime-upgrade-role`, policy `arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole` only.
- Transformation: AWS-managed `AWS/lambda-nodejs-runtime-upgrade` (no custom `SKILL.md` authored).
- Target runtime: `nodejs24.x` (matches the Phase 1 README's own worked example, "Target Node.js 24," and is very likely current LTS by now).
- Old-runtime candidates to try, in order, stopping at the first `create-function` success: `nodejs18.x`, `nodejs20.x`, `nodejs22.x`.
- **Plan-level refinement over the spec:** `poc/lambda/` is its own nested git repo (separate `.git`, gitignored by the parent `aws-transform-runtime-upgrade-lab` repo) — required because `atx` needs `--code-repository-path` to point at a real git repo, and isolates its generated branch from the rest of the lab.

---

### Task 1: Install and verify the `atx` CLI

**Files:** None (global CLI install; not part of this repo).

**Interfaces:**
- Produces: confirmed real flag names for `atx custom def exec` — later tasks use whatever this task's Step 3 actually finds, not blindly the README's guess.

- [ ] **Step 1: Run the install script**

```bash
curl -fsSL https://transform-cli.awsstatic.com/install.sh | bash
```
Expected: completes without error; output names the install directory.

- [ ] **Step 2: Verify the binary is on PATH**

```bash
atx --version
```
Expected: prints a version string. If `command not found`: find the install directory from Step 1's output (or check common locations, e.g. `ls ~/.local/bin/atx ~/.atx/bin/atx 2>/dev/null`), then `export PATH="<that dir>:$PATH"` and retry.

- [ ] **Step 3: Confirm the real flags for the managed-transformation command**

```bash
atx custom def exec --help
```
Expected: help text listing its flags. Compare against the three the Phase 1 README assumes: `--code-repository-path`, `--transformation-name`, `--configuration`. If any name differs, note the actual name — Task 5 uses it instead.

- [ ] **Step 4: No commit** — nothing in the repo changed.

---

### Task 2: Toy Lambda handler + local test harness

**Files:**
- Create: `poc/lambda/package.json`
- Create: `poc/lambda/index.js`
- Create: `poc/lambda/test/local-invoke.js`
- Create: `poc/lambda/.gitignore`
- Modify: `.gitignore` (repo root)
- Test: `poc/lambda/test/local-invoke.js` (this file is itself the test)

**Interfaces:**
- Produces: `exports.handler` in `index.js`, old callback-style signature `(event, context, callback)`. Task 3's `deploy.sh` references the Lambda entry point as `index.handler` — must keep matching. Task 5's transformed code must still export a handler at that same name/shape (async is fine — see the harness below).
- The `invoke(event)` helper in `local-invoke.js` accepts BOTH a callback-style handler and a Promise-returning (`async`) handler, without needing the test file itself edited — Task 5 relies on this to validate the post-transformation code with the exact same test file.

- [ ] **Step 1: Fix the root `.gitignore` for the nested-repo plan**

Open `.gitignore` at the repo root and replace the `poc/lambda/node_modules/` line with `poc/lambda/` (the whole directory — it will be its own independently git-tracked repo, not part of the parent).

- [ ] **Step 2: Write the failing test**

`poc/lambda/test/local-invoke.js`:
```js
'use strict';

const assert = require('assert');
const { handler } = require('../index.js');

function invoke(event) {
  return new Promise((resolve, reject) => {
    const maybePromise = handler(event, {}, (err, result) => {
      if (err) return reject(err);
      resolve(result);
    });
    if (maybePromise && typeof maybePromise.then === 'function') {
      maybePromise.then(resolve, reject);
    }
  });
}

async function main() {
  const result = await invoke({ name: 'AWS Transform' });
  assert.strictEqual(result.message, 'Hello, AWS Transform!');

  const defaultResult = await invoke({});
  assert.strictEqual(defaultResult.message, 'Hello, world!');

  console.log('local-invoke: all assertions passed');
}

main().catch((err) => {
  console.error('local-invoke: FAILED');
  console.error(err);
  process.exit(1);
});
```

- [ ] **Step 3: Run it to verify it fails**

```bash
mkdir -p poc/lambda/test
node poc/lambda/test/local-invoke.js
```
Expected: crashes with `Error: Cannot find module '../index.js'` — `index.js` doesn't exist yet.

- [ ] **Step 4: Write the handler and package manifest**

`poc/lambda/index.js`:
```js
'use strict';

exports.handler = function (event, context, callback) {
  const name = (event && event.name) || 'world';
  callback(null, { message: `Hello, ${name}!` });
};
```

`poc/lambda/package.json`:
```json
{
  "name": "atx-poc-lambda",
  "version": "1.0.0",
  "private": true,
  "description": "Toy Lambda handler for the AWS Transform Lambda Node.js runtime upgrade POC",
  "main": "index.js",
  "scripts": {
    "test": "node test/local-invoke.js"
  },
  "engines": {
    "node": "18.x"
  }
}
```

- [ ] **Step 5: Run it to verify it passes**

```bash
node poc/lambda/test/local-invoke.js
```
Expected: `local-invoke: all assertions passed`, exit 0.

- [ ] **Step 6: Init the nested repo and commit inside it**

```bash
cd poc/lambda
git init -b master
printf 'node_modules/\n' > .gitignore
git add .
git commit -m "Add toy Lambda handler (old callback-style, pre-upgrade) + local test harness"
cd ../..
```

- [ ] **Step 7: Commit the parent repo's gitignore fix**

```bash
git add .gitignore
git commit -m "Ignore poc/lambda/ — it is its own nested git repo, not tracked here"
```

---

### Task 3: Deploy scripts, IAM role, old-runtime deploy, baseline invoke

**Files:**
- Create: `poc/scripts/deploy.sh`
- Create: `poc/scripts/invoke.sh`
- Create: `poc/results/before-response.json`
- Test: a real `aws lambda invoke` call against the live function

**Interfaces:**
- Consumes: `poc/lambda/index.js` + `package.json` from Task 2, zipped as-is; entry point `index.handler`.
- Produces: a live Lambda function `atx-poc-lambda-runtime-upgrade` in `043309363336`/`us-east-1`, and `poc/results/before-response.json` — the baseline Task 6 diffs against.

- [ ] **Step 1: Write `deploy.sh`**

`poc/scripts/deploy.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

RUNTIME="${1:?Usage: deploy.sh <lambda-runtime> e.g. deploy.sh nodejs18.x}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAMBDA_DIR="$SCRIPT_DIR/../lambda"
PROFILE="default"
REGION="us-east-1"
FUNCTION_NAME="atx-poc-lambda-runtime-upgrade"
ROLE_NAME="atx-poc-lambda-runtime-upgrade-role"
ZIP_PATH="/tmp/atx-poc-lambda.zip"

echo "==> Ensuring IAM execution role ($ROLE_NAME) exists"
if ! aws iam get-role --role-name "$ROLE_NAME" --profile "$PROFILE" >/dev/null 2>&1; then
  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "lambda.amazonaws.com"},
        "Action": "sts:AssumeRole"
      }]
    }' \
    --profile "$PROFILE" >/dev/null

  aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
    --profile "$PROFILE"

  echo "==> Waiting for IAM role propagation"
  sleep 10
fi

ROLE_ARN="$(aws iam get-role --role-name "$ROLE_NAME" --profile "$PROFILE" --query 'Role.Arn' --output text)"

echo "==> Zipping $LAMBDA_DIR"
rm -f "$ZIP_PATH"
(cd "$LAMBDA_DIR" && zip -r -q "$ZIP_PATH" index.js package.json)

if aws lambda get-function --function-name "$FUNCTION_NAME" --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1; then
  echo "==> Function exists — updating code and runtime"
  aws lambda update-function-code \
    --function-name "$FUNCTION_NAME" \
    --zip-file "fileb://$ZIP_PATH" \
    --profile "$PROFILE" --region "$REGION" >/dev/null
  aws lambda wait function-updated --function-name "$FUNCTION_NAME" --profile "$PROFILE" --region "$REGION"
  aws lambda update-function-configuration \
    --function-name "$FUNCTION_NAME" \
    --runtime "$RUNTIME" \
    --profile "$PROFILE" --region "$REGION" >/dev/null
  aws lambda wait function-updated --function-name "$FUNCTION_NAME" --profile "$PROFILE" --region "$REGION"
else
  echo "==> Creating function with runtime $RUNTIME"
  aws lambda create-function \
    --function-name "$FUNCTION_NAME" \
    --runtime "$RUNTIME" \
    --role "$ROLE_ARN" \
    --handler index.handler \
    --zip-file "fileb://$ZIP_PATH" \
    --profile "$PROFILE" --region "$REGION" >/dev/null
  aws lambda wait function-active --function-name "$FUNCTION_NAME" --profile "$PROFILE" --region "$REGION"
fi

echo "==> Deployed $FUNCTION_NAME on runtime $RUNTIME"
aws lambda get-function --function-name "$FUNCTION_NAME" --profile "$PROFILE" --region "$REGION" --query 'Configuration.[FunctionName,Runtime,State]' --output text
```

```bash
chmod +x poc/scripts/deploy.sh
```

- [ ] **Step 2: Write `invoke.sh`**

`poc/scripts/invoke.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

PROFILE="default"
REGION="us-east-1"
FUNCTION_NAME="atx-poc-lambda-runtime-upgrade"
OUT_PATH="${1:-/tmp/atx-poc-lambda-response.json}"

aws lambda invoke \
  --function-name "$FUNCTION_NAME" \
  --payload '{"name":"AWS Transform"}' \
  --cli-binary-format raw-in-base64-out \
  --profile "$PROFILE" --region "$REGION" \
  "$OUT_PATH" >/dev/null

echo "==> Response saved to $OUT_PATH"
cat "$OUT_PATH"
echo
```

```bash
chmod +x poc/scripts/invoke.sh
```

- [ ] **Step 3: Deploy on the oldest candidate runtime, falling back if AWS rejects it**

```bash
poc/scripts/deploy.sh nodejs18.x
```
Expected: either succeeds (`Deployed atx-poc-lambda-runtime-upgrade on runtime nodejs18.x`, State `Active`), or fails with an AWS error about the runtime no longer being supported for function creation. If it fails, retry `poc/scripts/deploy.sh nodejs20.x`, then `poc/scripts/deploy.sh nodejs22.x` if that also fails. Stop at the first success and note which runtime actually worked — Task 7 records it.

- [ ] **Step 4: Confirm the function is live**

```bash
aws lambda get-function --function-name atx-poc-lambda-runtime-upgrade --profile default --region us-east-1 --query 'Configuration.[Runtime,State]' --output text
```
Expected: `<the runtime that succeeded in Step 3>	Active`

- [ ] **Step 5: Capture the baseline invoke**

```bash
mkdir -p poc/results
poc/scripts/invoke.sh poc/results/before-response.json
```
Expected output includes: `{"message":"Hello, AWS Transform!"}`

- [ ] **Step 6: Commit**

```bash
git add poc/scripts/deploy.sh poc/scripts/invoke.sh poc/results/before-response.json
git commit -m "Add deploy/invoke scripts; deploy old-runtime Lambda and capture baseline invoke"
```

---

### Task 4: Teardown script

**Files:**
- Create: `poc/scripts/teardown.sh`
- Test: shell syntax check + name-consistency check against `deploy.sh`

**Interfaces:**
- Consumes: `FUNCTION_NAME`/`ROLE_NAME` values — must stay byte-identical to `deploy.sh`'s, or teardown silently no-ops on a resource it doesn't recognize.

- [ ] **Step 1: Write `teardown.sh`**

`poc/scripts/teardown.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

PROFILE="default"
REGION="us-east-1"
FUNCTION_NAME="atx-poc-lambda-runtime-upgrade"
ROLE_NAME="atx-poc-lambda-runtime-upgrade-role"

echo "==> Deleting Lambda function $FUNCTION_NAME (if it exists)"
aws lambda delete-function --function-name "$FUNCTION_NAME" --profile "$PROFILE" --region "$REGION" 2>/dev/null \
  && echo "    deleted" || echo "    already absent, skipping"

echo "==> Detaching and deleting IAM role $ROLE_NAME (if it exists)"
if aws iam get-role --role-name "$ROLE_NAME" --profile "$PROFILE" >/dev/null 2>&1; then
  aws iam detach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
    --profile "$PROFILE"
  aws iam delete-role --role-name "$ROLE_NAME" --profile "$PROFILE"
  echo "    deleted"
else
  echo "    already absent, skipping"
fi

echo "==> Teardown complete"
```

```bash
chmod +x poc/scripts/teardown.sh
```

- [ ] **Step 2: Syntax check**

```bash
bash -n poc/scripts/teardown.sh
```
Expected: no output, exit 0.

- [ ] **Step 3: Name-consistency check**

```bash
diff <(grep '^FUNCTION_NAME=' poc/scripts/deploy.sh) <(grep '^FUNCTION_NAME=' poc/scripts/teardown.sh)
diff <(grep '^ROLE_NAME=' poc/scripts/deploy.sh) <(grep '^ROLE_NAME=' poc/scripts/teardown.sh)
```
Expected: no output from either, exit 0.

- [ ] **Step 4: Commit**

```bash
git add poc/scripts/teardown.sh
git commit -m "Add teardown script for the toy Lambda + IAM role"
```

Note: deliberately not run against real AWS in this task — the function is still needed by Tasks 5–6.

---

### Task 5: Run the AWS Transform upgrade, review the diff

**Files:**
- Modify (by `atx`, on a new branch, not by hand): `poc/lambda/index.js`, `poc/lambda/package.json`
- Test: `poc/lambda/test/local-invoke.js` (this is `atx`'s own validation gate; also re-run independently)

**Interfaces:**
- Consumes: the confirmed flags from Task 1 Step 3; the nested repo from Task 2 Step 6.
- Produces: a new git branch inside `poc/lambda` holding the transformed code (exact name reported by `atx`'s own output — capture it). Task 6 checks this branch out.

- [ ] **Step 1: Run the transformation**

```bash
cd poc/lambda
atx custom def exec \
  --code-repository-path . \
  --transformation-name AWS/lambda-nodejs-runtime-upgrade \
  --configuration additionalPlanContext="Target Node.js 24"
```
Expected: completes, output names the branch it created and reports the validation command (`npm test` → `node test/local-invoke.js`) passing. If Task 1 Step 3 found different real flag names, use those instead of the ones above.

- [ ] **Step 2: Confirm the branch exists**

```bash
git branch
```
Expected: a new branch alongside `master` (exact name from Step 1's output — use it in the steps below).

- [ ] **Step 3: Review the diff**

```bash
git diff master <branch-name>
```
Expected: `index.js`'s `exports.handler = function (event, context, callback) {...}` rewritten to `exports.handler = async function (event) {...}` (no callback param, implicit `return` instead of `callback(null, ...)`), and `package.json`'s `engines.node` bumped from `18.x` toward Node 24.

- [ ] **Step 4: Independently re-run the test on that branch**

```bash
git checkout <branch-name>
node test/local-invoke.js
git checkout master
```
Expected: `local-invoke: all assertions passed` — proves Task 2's dual-style harness genuinely validates the transformed handler too, not just `atx`'s own say-so.

- [ ] **Step 5: No commit here** — `atx` already committed to its own branch; `master` is untouched until Task 6's merge.

---

### Task 6: Redeploy the upgraded code, verify it matches

**Files:**
- Modify: `poc/lambda` (merge Task 5's branch into `master`)
- Create: `poc/results/after-response.json`

**Interfaces:**
- Consumes: the branch name from Task 5; `deploy.sh`/`invoke.sh` from Task 3; `poc/results/before-response.json` from Task 3.
- Produces: `poc/results/after-response.json`; `poc/lambda`'s `master` now holds the upgraded code — the state Task 7 documents.

- [ ] **Step 1: Merge the branch**

```bash
cd poc/lambda
git checkout master
git merge --no-ff <branch-name> -m "Merge AWS Transform Lambda Node.js runtime upgrade"
cd ../..
```

- [ ] **Step 2: Redeploy the same function on the new runtime**

```bash
poc/scripts/deploy.sh nodejs24.x
```
Expected: takes the `Function exists — updating code and runtime` path (not create), ends with `Deployed atx-poc-lambda-runtime-upgrade on runtime nodejs24.x`.

- [ ] **Step 3: Confirm the runtime actually changed**

```bash
aws lambda get-function --function-name atx-poc-lambda-runtime-upgrade --profile default --region us-east-1 --query 'Configuration.[Runtime,State]' --output text
```
Expected: `nodejs24.x	Active`

- [ ] **Step 4: Capture the post-upgrade invoke and diff against baseline**

```bash
poc/scripts/invoke.sh poc/results/after-response.json
diff poc/results/before-response.json poc/results/after-response.json
```
Expected: `diff` prints nothing — identical output, different runtime, exit 0.

- [ ] **Step 5: Commit**

```bash
git add poc/results/after-response.json
git commit -m "Redeploy upgraded Lambda (nodejs24.x) and confirm invoke output matches baseline"
```
(`poc/lambda`'s merge commit from Step 1 lives in its own nested repo history — the parent repo doesn't track `poc/lambda`'s files at all, per Task 2's gitignore fix.)

---

### Task 7: Write up the results

**Files:**
- Create: `poc/README.md`
- Modify: `README.md` (repo root)

- [ ] **Step 1: Write `poc/README.md`**

Using the actual captured results, cover: setup (`atx` install, AWS profile/region used), the exact commands run in order (deploy old → invoke → `atx exec` → merge → deploy new → invoke → diff), which old runtime candidate from Task 3 Step 3 actually succeeded, the real code diff from Task 5 Step 3 (callback → async/await), and a Results section stating both invokes returned identical output while `get-function` showed the runtime changed as expected.

- [ ] **Step 2: Commit**

```bash
git add poc/README.md
git commit -m "Write up Phase 2 POC results"
```

- [ ] **Step 3: Mark Phase 2 complete in the root README**

Change the root `README.md`'s Status checklist line:
```
- [ ] Phase 2 — hands-on POC: install `atx`, pick a target runtime and
      AWS account, run a real transformation against a sample repo,
      capture the before/after diff and validation output
```
to:
```
- [x] Phase 2 — hands-on POC: done, see [poc/README.md](poc/README.md)
      for the full write-up (before/after diff + invoke output).
```

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "Mark Phase 2 complete, link to poc/README.md"
```

---

## After all tasks: cleanup

Not part of any task above (deliberately manual, per spec) — when you're done experimenting, tear down the real AWS resources:

```bash
poc/scripts/teardown.sh
```
