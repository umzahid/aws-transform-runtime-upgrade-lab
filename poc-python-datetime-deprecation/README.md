# Python Version-Upgrade POC #2 — Results (Real Deprecation Fix)

A follow-up to `../poc-python/README.md`. That first Python POC only
modernized type-hint *style* — nothing there was actually wrong or
deprecated, just non-idiomatic. This POC deliberately uses a genuinely
deprecated stdlib API to see whether AWS Transform's
`AWS/python-version-upgrade` transformation fixes something that actually
matters — no hints given about what the problem is.

## The forcing case: `datetime.datetime.utcnow()`

`datetime.datetime.utcnow()` was deprecated in Python 3.12 (still present,
not removed, in 3.14). Verified empirically before building anything, on
the real local Python 3.14.5:

```bash
$ python3 -W always::DeprecationWarning -c "import datetime; datetime.datetime.utcnow()"
DeprecationWarning: datetime.datetime.utcnow() is deprecated and scheduled
for removal in a future version. Use timezone-aware objects to represent
datetimes in UTC: datetime.datetime.now(datetime.UTC).
```

Unlike the Java POC's `java.rmi.activation` (fully removed, forcing a
compile break), this is the closer parallel to the Node.js POC's
`new Buffer()` case: still functional today, but flagged, with one clear
recommended replacement — appropriate since (unlike Java, where `--release`
let us fake an old JDK) there's no installed old-Python interpreter to
prove a hard break against locally.

## Setup

- Same `atx` CLI 3.11.0, same transformation as `poc-python/`
  (`AWS/python-version-upgrade`), same generic prompt
  (`"This is a Python app that should be upgraded to Python 3.13"`) —
  deliberately not hinting at the `utcnow()` issue.
- The test (`test/test_app.py`) asserts only on the functional shape of the
  output (an ISO-8601-prefixed string), never on the warning itself — so it
  stays valid, unedited, both before and after the transformation.
- `poc-python-datetime-deprecation/` was its own nested git repo during the
  `atx` run, flattened afterward. Real commit history, preserved for the
  record:
  - `f4d69c1` Add toy Python app using datetime.utcnow() (deprecated since 3.12) + test
  - `a580da2` Step 1: Replace deprecated datetime.utcnow() with datetime.now(datetime.timezone.utc) for Python 3.13 compatibility. Build status: Success — the actual commit `atx` authored
  - `d922c45` Merge AWS Transform Python version upgrade (datetime.utcnow deprecation fix)

## Commands, in order

```bash
# 1. Local baseline — passes, but warns
python3 -W always::DeprecationWarning test/test_app.py

# 2. Run the AWS-managed transformation (same generic prompt as before)
atx custom def exec \
  --code-repository-path . \
  --transformation-name AWS/python-version-upgrade \
  --build-command "python3 test/test_app.py" \
  --configuration additionalPlanContext="This is a Python app that should be upgraded to Python 3.13" \
  --non-interactive \
  --trust-all-tools

# 3. Merge the result branch, flatten the nested repo
git merge --no-ff <atx-result-staging-branch>

# 4. Run again, post-upgrade — no warning this time
python3 -W always::DeprecationWarning test/test_app.py
```

## The actual code diff

```diff
--- a/app.py
+++ b/app.py
@@ -3,5 +3,5 @@ import datetime
 
 
 def current_utc_label():
-    now = datetime.datetime.utcnow()
+    now = datetime.datetime.now(datetime.timezone.utc)
     return "UTC: {}".format(now.isoformat())
```

**Honest note:** `atx` used `datetime.timezone.utc` rather than the newer
`datetime.UTC` alias (available since 3.11) that the deprecation message
itself suggests. Both are fully correct and equivalent — `datetime.UTC` is
just a shorter alias for `datetime.timezone.utc` — so this is a completely
valid fix, just the more broadly-compatible spelling rather than the
newest one.

## Results

| Check | Before | After |
|---|---|---|
| `datetime` call | `datetime.datetime.utcnow()` | `datetime.datetime.now(datetime.timezone.utc)` |
| Test (`python3 test/test_app.py`) | `local-invoke: all assertions passed` | `local-invoke: all assertions passed` |
| `DeprecationWarning` on stderr | **present** (confirmed above) | **absent** (confirmed above) |
| Real execution, run fresh after flattening | — | `local-invoke: all assertions passed`, no warning (confirmed above) |

Agent Minutes used: 15.60.

**Conclusion:** unlike `poc-python/` (a style-only modernization with
nothing actually deprecated), this POC used a genuinely deprecated stdlib
API with real runtime consequence (a warning). AWS Transform correctly
replaced it with a fully valid timezone-aware equivalent, found with no
hints given, and the fix is independently verifiable: the warning is
genuinely gone, not just the code looking different.
