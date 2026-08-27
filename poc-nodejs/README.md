# Node.js Version-Upgrade POC — Results

Local-only follow-up to the AWS-deployed Lambda POC (`../poc/README.md`).
Ran AWS Transform's **general-purpose** managed `AWS/nodejs-version-upgrade`
transformation — distinct from `AWS/lambda-nodejs-runtime-upgrade` already
used for the Lambda POC — against a small plain Node.js module, entirely
locally, no AWS deployment.

## Setup

- `atx` CLI 3.11.0 (already installed for the Lambda POC)
- Local `node` is v26.4.0, comfortably above the Node 22 target — the
  upgraded code runs on the real, current local Node.js.
- `poc-nodejs/` was its own nested git repo during the `atx` run (a hard
  requirement of the tool), flattened into this parent repo afterward.
  Its real commit history, preserved for the record:
  - `c4f6611` Add toy Node.js app (var/callback/new Buffer(), pre-upgrade) + local test
  - `52f876e` Step 1: Upgrade Node.js from 12.x to 22.x - Updated engines field in package.json, replaced deprecated new Buffer() with Buffer.from() in index.js. Build status: Success — the actual commit `atx` authored
  - `cb83465` Merge AWS Transform Node.js version upgrade

## Commands, in order

```bash
# 1. Local baseline (prints a DeprecationWarning for new Buffer() — expected)
node test/local-invoke.js

# 2. Run the AWS-managed transformation
atx custom def exec \
  --code-repository-path . \
  --transformation-name AWS/nodejs-version-upgrade \
  --build-command "node test/local-invoke.js" \
  --configuration additionalPlanContext="This is a Node.js app that should be upgraded to Node.js 22" \
  --non-interactive \
  --trust-all-tools

# 3. Merge the result branch, flatten the nested repo
git merge --no-ff <atx-result-staging-branch>

# 4. Run again, post-upgrade — no deprecation warning this time
node test/local-invoke.js
```

## The actual code diff

```diff
--- a/index.js
+++ b/index.js
@@ -2,7 +2,7 @@
 
 function formatGreeting(name, callback) {
   var displayName = name || 'world';
-  var buf = new Buffer(displayName, 'utf8');
+  var buf = Buffer.from(displayName, 'utf8');
   callback(null, 'Hello, ' + buf.toString('utf8') + '!');
 }
```
```diff
--- a/package.json
+++ b/package.json
@@ -8,6 +8,6 @@
     "test": "node test/local-invoke.js"
   },
   "engines": {
-    "node": "12.x"
+    "node": "22.x"
   }
 }
```

**Honest note:** same pattern as the Java POC — the transformation was more
conservative than the Lambda-specific one. It fixed exactly the deprecated
API (`new Buffer()` → `Buffer.from()`) and the version metadata, but left
`var` untouched rather than modernizing to `let`/`const`, and didn't touch
the callback-style function signature (unlike the Lambda transformation,
this general one isn't obligated to force async/await — it targets version
compatibility, not a specific runtime interface contract).

## Results

| Check | Before | After |
|---|---|---|
| `Buffer` construction | `new Buffer(...)` (deprecated) | `Buffer.from(...)` |
| `package.json` `engines.node` | `12.x` | `22.x` |
| Local test output | `local-invoke: all assertions passed` + `DeprecationWarning` | `local-invoke: all assertions passed`, **no warning** |
| Real execution, run fresh after flattening | — | `local-invoke: all assertions passed`, no warning (confirmed above) |

Agent Minutes used: 14.95.

**Conclusion:** AWS Transform's managed `AWS/nodejs-version-upgrade`
transformation correctly identified and fixed the exact deprecated-API
pattern Phase 1's own research doc called out (`new Buffer()`), bumped the
declared engine version, and the fix is independently verifiable: the
runtime deprecation warning is genuinely gone after the upgrade, not just
the code looking different.
