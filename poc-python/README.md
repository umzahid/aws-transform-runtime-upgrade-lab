# Python Version-Upgrade POC — Results

Local-only follow-up to the AWS-deployed Lambda POC (`../poc/README.md`).
Ran AWS Transform's managed `AWS/python-version-upgrade` transformation
against a small Python app, entirely locally — no AWS deployment.

## Setup

- `atx` CLI 3.11.0 (already installed for the Lambda POC)
- `poc-python/` was its own nested git repo during the `atx` run (a hard
  requirement of the tool), flattened into this parent repo afterward.
  Its real commit history, preserved for the record:
  - `242909e` Add toy Python app (pre-3.9 typing style, pre-upgrade) + local test
  - `cf24707` Step 1: Upgrade Python code to 3.13 - modernized type hints (dict, str | None instead of typing.Dict, typing.Optional), replaced .format() with f-string. Build status: Success — the actual commit `atx` authored
  - `cae3504` Merge AWS Transform Python version upgrade
- Local `python3` is 3.14.5 — there's no separate 3.8 or 3.13 interpreter
  installed. This is an honest limitation: the "before" and "after" code
  both actually ran on the same 3.14 interpreter (a superset of both), so
  this proves the code is *written* in a 3.8-compatible-then-3.13-compatible
  way and *executes correctly*, not that it ran under an exact 3.13 binary.

## Commands, in order

```bash
# 1. Local baseline
python3 test/test_app.py

# 2. Run the AWS-managed transformation
atx custom def exec \
  --code-repository-path . \
  --transformation-name AWS/python-version-upgrade \
  --build-command "python3 test/test_app.py" \
  --configuration additionalPlanContext="This is a Python app that should be upgraded to Python 3.13" \
  --non-interactive \
  --trust-all-tools

# 3. Merge the result branch, flatten the nested repo
git merge --no-ff <atx-result-staging-branch>

# 4. Run again, post-upgrade
python3 test/test_app.py
```

## The actual code diff

```diff
--- a/app.py
+++ b/app.py
@@ -1,7 +1,6 @@
 """Toy app for the AWS Transform Python version-upgrade POC."""
-from typing import Dict, Optional
 
 
-def greet(name: Optional[str]) -> Dict[str, str]:
+def greet(name: str | None) -> dict[str, str]:
     display_name = name if name else "world"
-    return {"message": "Hello, {}!".format(display_name)}
+    return {"message": f"Hello, {display_name}!"}
```

Exactly the modernization expected: `typing.Dict`/`typing.Optional` (pre-3.9
style) replaced with the built-in generic `dict[str, str]` and PEP 604
union syntax `str | None` (3.10+) — plus a bonus, unprompted modernization:
`.format()` replaced with an f-string.

## Results

| Check | Before | After |
|---|---|---|
| Type hint style | `typing.Dict`, `typing.Optional` | `dict[str, str]`, `str \| None` |
| String formatting | `.format()` | f-string |
| Local test (`python3 test/test_app.py`) | `local-invoke: all assertions passed` | `local-invoke: all assertions passed` |
| Real execution, run fresh after flattening | — | `local-invoke: all assertions passed` (confirmed above) |

Agent Minutes used: 13.59.

**Conclusion:** AWS Transform's managed `AWS/python-version-upgrade`
transformation genuinely modernizes Python type-hint syntax for a newer
target version while preserving behavior — confirmed by independently
re-running the test both immediately after the transformation and again
after flattening, on the real local interpreter.
