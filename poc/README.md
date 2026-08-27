# Phase 2 POC — Results

Hands-on follow-up to the Phase 1 research doc (`../README.md`). Ran AWS
Transform's managed `AWS/lambda-nodejs-runtime-upgrade` transformation
against a real toy Lambda function and proved the in-place runtime upgrade
end to end.

## Setup

- `atx` CLI 3.11.0, installed via `curl -fsSL https://transform-cli.awsstatic.com/install.sh | bash`
- AWS profile `default`, account `043309363336`, region `us-east-1`
- `poc/lambda/` is its own nested git repo (separate from this lab's parent
  repo) — required because `atx` needs `--code-repository-path` to point at
  a real git repository

## Commands, in order

```bash
# 1. Deploy the "before" function (old runtime — nodejs18.x was still
#    creatable on this account; no need to fall back to 20.x/22.x)
poc/scripts/deploy.sh nodejs18.x

# 2. Capture the baseline invoke
poc/scripts/invoke.sh poc/results/before-response.json

# 3. Run the AWS-managed transformation
cd poc/lambda
atx custom def exec \
  --code-repository-path . \
  --transformation-name AWS/lambda-nodejs-runtime-upgrade \
  --build-command "node test/local-invoke.js" \
  --configuration additionalPlanContext="Target Node.js 24" \
  --non-interactive \
  --trust-all-tools

# 4. Merge the result branch, redeploy the SAME function on the new runtime
git checkout master
git merge --no-ff <atx-result-staging-branch>
cd ../..
poc/scripts/deploy.sh nodejs24.x

# 5. Capture the post-upgrade invoke and diff
poc/scripts/invoke.sh poc/results/after-response.json
diff poc/results/before-response.json poc/results/after-response.json
```

## Deviations from the Phase 1 research doc, discovered hands-on

- `atx custom def exec` has no auto-detected build/test command — a
  dedicated `--build-command` flag is required, or it has no validation
  gate to run at all.
- Running unattended (not from an interactive terminal) requires
  `--non-interactive` and `--trust-all-tools`, or the command hangs
  waiting for prompts.
- The branch `atx` creates is named `atx-result-staging-<timestamp>_<hash>`
  (e.g. `atx-result-staging-20260827_092714_f797793f`), not the
  `atx/lambda-nodejs-runtime-upgrade-*` pattern assumed while planning.
- Agent Minutes used for this single small-file transformation: **15.13**
  (per the CLI's own output) — useful for estimating cost before running
  this at scale.

## The actual code diff

```diff
--- a/index.js
+++ b/index.js
@@ -1,6 +1,6 @@
 'use strict';

-exports.handler = function (event, context, callback) {
+exports.handler = async function (event, context) {
   const name = (event && event.name) || 'world';
-  callback(null, { message: `Hello, ${name}!` });
+  return { message: `Hello, ${name}!` };
 };
```
```diff
--- a/package.json
+++ b/package.json
@@ -8,6 +8,6 @@
     "test": "node test/local-invoke.js"
   },
   "engines": {
-    "node": "18.x"
+    "node": ">=24"
   }
 }
```

Exactly the transformation AWS's own Node.js worked example describes:
callback-style handler rewritten to `async`/`await`, `engines.node` bumped
for the target version.

## Results

| Check | Before | After |
|---|---|---|
| Runtime (`aws lambda get-function`) | `nodejs18.x` | `nodejs24.x` |
| Function state | `Active` | `Active` |
| Invoke response | `{"message":"Hello, AWS Transform!"}` | `{"message":"Hello, AWS Transform!"}` |

Before/after invoke responses are **byte-identical** (`diff` on
`poc/results/before-response.json` vs. `poc/results/after-response.json`
produces no output), despite the runtime and code style being completely
different underneath. The local test (`poc/lambda/test/local-invoke.js`)
was independently re-run against `atx`'s transformed code (not just
trusted from its own "Build status: Success" report) and passed.

**Conclusion:** AWS Transform's managed `AWS/lambda-nodejs-runtime-upgrade`
transformation genuinely upgrades a Lambda function's runtime in place —
callback → async/await conversion, `engines` field bump, real redeploy —
while preserving behavior. Confirmed against a real AWS account, not just
read about.

## Cleanup

Real AWS resources exist (one Lambda function, one IAM role). Tear them
down when done experimenting:

```bash
poc/scripts/teardown.sh
```
