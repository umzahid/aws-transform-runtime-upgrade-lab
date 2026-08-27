# Multi-Language Local Runtime Upgrade POC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove AWS Transform's general-purpose managed transformations work across Python, Java, and Node.js by upgrading three toy apps in place, entirely locally — executing the upgraded code for real, not just reviewing a diff.

**Architecture:** Three independent `poc-<lang>/` folders, each briefly its own nested git repo (a hard requirement of `atx`) during the transformation run, then flattened into the parent repo immediately after. Same shape per language: write old-style app + test → run `atx` → verify → flatten → execute for real → write results.

**Tech Stack:** Python 3 (local interpreter 3.14.5), Java 17/Maven (Corretto 17.0.19, Maven 3.9.15), Node.js (local v26.4.0), `atx` CLI 3.11.0 (already installed).

**Spec:** `docs/superpowers/specs/2026-08-27-multi-language-runtime-upgrade-poc-design.md`

## Global Constraints

- `atx` CLI already installed and verified (`~/.local/bin/atx`, v3.11.0) — no reinstall needed.
- Every `atx custom def exec` call needs `--non-interactive --trust-all-tools` (confirmed required for unattended runs) and an explicit `--build-command` (no auto-detection).
- Transformation → target mapping:
  | Language | `--transformation-name` | `additionalPlanContext` | `--build-command` |
  |---|---|---|---|
  | Python | `AWS/python-version-upgrade` | `This is a Python app that should be upgraded to Python 3.13` | `python3 test/test_app.py` |
  | Java | `AWS/java-version-upgrade` | `This is a Maven app that should be upgraded to Java 17` | `mvn -q compile exec:java` |
  | Node.js | `AWS/nodejs-version-upgrade` | `This is a Node.js app that should be upgraded to Node.js 22` | `node test/local-invoke.js` |
- Every `poc-<lang>/` folder: `git init -b master` before running `atx`, flatten (remove `.git`, preserve its commit log as text) immediately after merging — do not leave any nested repo in the final state.
- No AWS resources are created by this plan — confirmed local-only scope. No teardown task needed.
- Base repo: `~/projects/aws-transform-runtime-upgrade-lab`, `master` branch directly (same standing consent as the Lambda POC), remote `origin` already exists (`https://github.com/umzahid/aws-transform-runtime-upgrade-lab`, private).

---

### Task 1: Python — build the toy app + local test

**Files:**
- Create: `poc-python/app.py`
- Create: `poc-python/test/test_app.py`
- Create: `poc-python/.gitignore`

**Interfaces:**
- Produces: `greet(name)` in `app.py`, returning `Dict[str, str]` via pre-3.9 `typing` generics. Task 2 relies on this exact function name/shape existing (in whatever form `atx` rewrites it to) after transformation.

- [ ] **Step 1: Write the failing test**

`poc-python/test/test_app.py`:
```python
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import greet


def main():
    result = greet("AWS Transform")
    assert result["message"] == "Hello, AWS Transform!", result

    default_result = greet(None)
    assert default_result["message"] == "Hello, world!", default_result

    print("local-invoke: all assertions passed")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run it to verify it fails**

```bash
mkdir -p poc-python/test
python3 poc-python/test/test_app.py
```
Expected: `ModuleNotFoundError: No module named 'app'` — `app.py` doesn't exist yet.

- [ ] **Step 3: Write the app**

`poc-python/app.py`:
```python
"""Toy app for the AWS Transform Python version-upgrade POC."""
from typing import Dict, Optional


def greet(name: Optional[str]) -> Dict[str, str]:
    display_name = name if name else "world"
    return {"message": "Hello, {}!".format(display_name)}
```

- [ ] **Step 4: Run it to verify it passes**

```bash
python3 poc-python/test/test_app.py
```
Expected: `local-invoke: all assertions passed`, exit 0.

- [ ] **Step 5: Init the nested repo and commit**

```bash
cd poc-python
git init -b master
printf '__pycache__/\n*.pyc\n' > .gitignore
git add .
git commit -m "Add toy Python app (pre-3.9 typing style, pre-upgrade) + local test"
cd ..
```

---

### Task 2: Python — run the upgrade, verify, flatten, execute for real

**Files:**
- Modify (by `atx`, on a branch): `poc-python/app.py`
- Create: `poc-python/README.md`
- Modify: `.gitignore` (repo root, temporarily then reverted — see Step 6)

**Interfaces:**
- Consumes: the nested repo from Task 1 Step 5.
- Produces: `poc-python/README.md` with real results; `poc-python/` flattened into the parent repo (no nested `.git` left behind).

- [ ] **Step 1: Run the transformation**

```bash
cd poc-python
atx custom def exec \
  --code-repository-path . \
  --transformation-name AWS/python-version-upgrade \
  --build-command "python3 test/test_app.py" \
  --configuration additionalPlanContext="This is a Python app that should be upgraded to Python 3.13" \
  --non-interactive \
  --trust-all-tools
```
Expected: completes, names the branch it created, reports the build command passing.

- [ ] **Step 2: Review the diff**

```bash
git branch
git diff master <branch-name>
```
Expected: `typing.Dict`/`typing.Optional` replaced with builtin generics (`dict[str, str]`, `str | None`), or equivalent modernization — record the actual diff for the README.

- [ ] **Step 3: Independently re-run the test on that branch**

```bash
git checkout <branch-name>
python3 test/test_app.py
git checkout master
```
Expected: `local-invoke: all assertions passed`.

- [ ] **Step 4: Merge**

```bash
git merge --no-ff <branch-name> -m "Merge AWS Transform Python version upgrade"
cd ..
```

- [ ] **Step 5: Flatten — remove the nested repo, preserve its history as text**

```bash
cd poc-python && git log --format='%H %s' > /tmp/poc-python-history.txt && cat /tmp/poc-python-history.txt && cd ..
rm -rf poc-python/.git
```
Note the printed commit hashes/messages — Step 8 puts them in `poc-python/README.md`.

- [ ] **Step 6: Track it in the parent repo**

```bash
cat poc-python/.gitignore
```
(No parent `.gitignore` change needed — `poc-python/` was never added to the root `.gitignore`, unlike `poc/lambda/` in the earlier POC. This step just confirms that.)

- [ ] **Step 7: Execute the upgraded code for real with the local toolchain**

```bash
python3 poc-python/test/test_app.py
```
Expected: `local-invoke: all assertions passed` — this is the final proof, run fresh after flattening, on the actual local Python 3.14 interpreter.

- [ ] **Step 8: Write `poc-python/README.md`**

Using the real diff from Step 2, the real commit history from Step 5, and the real test output from Step 7: cover setup, the exact commands run, the before/after code, and results. Follow the same structure as `poc/README.md` (the Lambda POC's write-up), adapted for a local (non-deployed) result.

- [ ] **Step 9: Commit in the parent repo**

```bash
git add poc-python
git commit -m "Add Python version-upgrade POC (3.8-style to 3.13, via AWS/python-version-upgrade)"
```

---

### Task 3: Java — build the toy app + local test

**Files:**
- Create: `poc-java/pom.xml`
- Create: `poc-java/src/main/java/com/example/App.java`
- Create: `poc-java/.gitignore`

**Interfaces:**
- Produces: `com.example.App` with a static `greet(String name)` method returning a `Greeting` (verbose POJO, pre-record style) and a `main()` self-check. Task 4 relies on `mvn -q compile exec:java` invoking this exact `mainClass`.

- [ ] **Step 1: Write the failing self-check**

`poc-java/src/main/java/com/example/App.java`:
```java
package com.example;

public class App {

    public static void main(String[] args) {
        Greeting result = greet("AWS Transform");
        if (!result.getMessage().equals("Hello, AWS Transform!")) {
            throw new AssertionError("unexpected: " + result);
        }
        Greeting defaultResult = greet(null);
        if (!defaultResult.getMessage().equals("Hello, world!")) {
            throw new AssertionError("unexpected: " + defaultResult);
        }
        System.out.println("local-invoke: all assertions passed");
    }
}
```
(This alone won't compile yet — `greet` and `Greeting` don't exist. That's the "failing test" for this task: a compile failure.)

- [ ] **Step 2: Write `pom.xml` and run to verify it fails**

`poc-java/pom.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>

  <groupId>com.example</groupId>
  <artifactId>atx-poc-java</artifactId>
  <version>1.0.0</version>
  <packaging>jar</packaging>

  <properties>
    <maven.compiler.release>8</maven.compiler.release>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
  </properties>

  <build>
    <plugins>
      <plugin>
        <groupId>org.codehaus.mojo</groupId>
        <artifactId>exec-maven-plugin</artifactId>
        <version>3.5.0</version>
        <configuration>
          <mainClass>com.example.App</mainClass>
        </configuration>
      </plugin>
    </plugins>
  </build>
</project>
```

```bash
cd poc-java
mvn -q compile exec:java
```
Expected: compile error — `cannot find symbol: method greet` / `class Greeting`.

- [ ] **Step 3: Write the `Greeting` class and `greet` method**

Add to `App.java` (inside the `App` class, alongside `main`):
```java
    public static class Greeting {
        private final String message;

        public Greeting(String message) {
            this.message = message;
        }

        public String getMessage() {
            return message;
        }

        @Override
        public String toString() {
            return "Greeting{message='" + message + "'}";
        }
    }

    public static Greeting greet(String name) {
        String displayName = (name == null || name.isEmpty()) ? "world" : name;
        return new Greeting("Hello, " + displayName + "!");
    }
```

- [ ] **Step 4: Run it to verify it passes**

```bash
mvn -q compile exec:java
```
Expected: `local-invoke: all assertions passed`, exit 0. (First run downloads `exec-maven-plugin` from Maven Central — requires network access.)

- [ ] **Step 5: Init the nested repo and commit**

```bash
printf 'target/\n' > .gitignore
git init -b master
git add .
git commit -m "Add toy Java app (verbose POJO, Java 8-style, pre-upgrade) + self-check"
cd ..
```

---

### Task 4: Java — run the upgrade, verify, flatten, execute for real

**Files:**
- Modify (by `atx`, on a branch): `poc-java/pom.xml`, `poc-java/src/main/java/com/example/App.java`
- Create: `poc-java/README.md`

**Interfaces:**
- Consumes: the nested repo from Task 3 Step 5.
- Produces: `poc-java/README.md`; `poc-java/` flattened, no nested `.git` left behind.

- [ ] **Step 1: Run the transformation**

```bash
cd poc-java
atx custom def exec \
  --code-repository-path . \
  --transformation-name AWS/java-version-upgrade \
  --build-command "mvn -q compile exec:java" \
  --configuration additionalPlanContext="This is a Maven app that should be upgraded to Java 17" \
  --non-interactive \
  --trust-all-tools
```
Expected: completes, names the branch it created, reports the build command passing.

- [ ] **Step 2: Review the diff**

```bash
git branch
git diff master <branch-name>
```
Expected: `maven.compiler.release` bumped from `8` to `17`, and plausibly the `Greeting` POJO rewritten as a `record` (Java 16+ feature) — record whichever it actually did.

- [ ] **Step 3: Independently re-run the build/test on that branch**

```bash
git checkout <branch-name>
mvn -q compile exec:java
git checkout master
```
Expected: `local-invoke: all assertions passed`.

- [ ] **Step 4: Merge**

```bash
git merge --no-ff <branch-name> -m "Merge AWS Transform Java version upgrade"
cd ..
```

- [ ] **Step 5: Flatten**

```bash
cd poc-java && git log --format='%H %s' > /tmp/poc-java-history.txt && cat /tmp/poc-java-history.txt && cd ..
rm -rf poc-java/.git
```

- [ ] **Step 6: Execute the upgraded code for real**

```bash
cd poc-java && mvn -q compile exec:java && cd ..
```
Expected: `local-invoke: all assertions passed` — run fresh after flattening, on the actual local JDK 17.

- [ ] **Step 7: Write `poc-java/README.md`**

Using the real diff, the real commit history from Step 5, and the real output from Step 6: setup, exact commands, before/after code, results. Same structure as `poc/README.md`.

- [ ] **Step 8: Commit in the parent repo**

```bash
git add poc-java
git commit -m "Add Java version-upgrade POC (8-style to 17, via AWS/java-version-upgrade)"
```

---

### Task 5: Node.js — build the toy app + local test

**Files:**
- Create: `poc-nodejs/index.js`
- Create: `poc-nodejs/package.json`
- Create: `poc-nodejs/test/local-invoke.js`
- Create: `poc-nodejs/.gitignore`

**Interfaces:**
- Produces: `formatGreeting(name, callback)` in `index.js`, old `var`/callback/`new Buffer()` style. Task 6's transformed version must keep the same exported name — the test in `local-invoke.js` is written to tolerate either callback-style or Promise-returning shapes without editing.

- [ ] **Step 1: Write the failing test**

`poc-nodejs/test/local-invoke.js`:
```js
'use strict';

const assert = require('assert');
const { formatGreeting } = require('../index.js');

function invoke(name) {
  return new Promise((resolve, reject) => {
    const maybePromise = formatGreeting(name, (err, result) => {
      if (err) return reject(err);
      resolve(result);
    });
    if (maybePromise && typeof maybePromise.then === 'function') {
      maybePromise.then(resolve, reject);
    }
  });
}

async function main() {
  const result = await invoke('AWS Transform');
  assert.strictEqual(result, 'Hello, AWS Transform!');

  const defaultResult = await invoke(undefined);
  assert.strictEqual(defaultResult, 'Hello, world!');

  console.log('local-invoke: all assertions passed');
}

main().catch((err) => {
  console.error('local-invoke: FAILED');
  console.error(err);
  process.exit(1);
});
```

- [ ] **Step 2: Run it to verify it fails**

```bash
mkdir -p poc-nodejs/test
node poc-nodejs/test/local-invoke.js
```
Expected: `Error: Cannot find module '../index.js'`.

- [ ] **Step 3: Write the app**

`poc-nodejs/index.js`:
```js
'use strict';

function formatGreeting(name, callback) {
  var displayName = name || 'world';
  var buf = new Buffer(displayName, 'utf8');
  callback(null, 'Hello, ' + buf.toString('utf8') + '!');
}

module.exports = { formatGreeting: formatGreeting };
```

`poc-nodejs/package.json`:
```json
{
  "name": "atx-poc-nodejs",
  "version": "1.0.0",
  "private": true,
  "description": "Toy Node.js app for the AWS Transform general-purpose Node.js version-upgrade POC",
  "main": "index.js",
  "scripts": {
    "test": "node test/local-invoke.js"
  },
  "engines": {
    "node": "12.x"
  }
}
```

- [ ] **Step 4: Run it to verify it passes**

```bash
node poc-nodejs/test/local-invoke.js
```
Expected: `local-invoke: all assertions passed`, exit 0 (a `DeprecationWarning` about `new Buffer()` on stderr is expected and fine — it's the exact pattern being upgraded away).

- [ ] **Step 5: Init the nested repo and commit**

```bash
cd poc-nodejs
git init -b master
printf 'node_modules/\n' > .gitignore
git add .
git commit -m "Add toy Node.js app (var/callback/new Buffer(), pre-upgrade) + local test"
cd ..
```

---

### Task 6: Node.js — run the upgrade, verify, flatten, execute for real

**Files:**
- Modify (by `atx`, on a branch): `poc-nodejs/index.js`, `poc-nodejs/package.json`
- Create: `poc-nodejs/README.md`

**Interfaces:**
- Consumes: the nested repo from Task 5 Step 5.
- Produces: `poc-nodejs/README.md`; `poc-nodejs/` flattened, no nested `.git` left behind.

- [ ] **Step 1: Run the transformation**

```bash
cd poc-nodejs
atx custom def exec \
  --code-repository-path . \
  --transformation-name AWS/nodejs-version-upgrade \
  --build-command "node test/local-invoke.js" \
  --configuration additionalPlanContext="This is a Node.js app that should be upgraded to Node.js 22" \
  --non-interactive \
  --trust-all-tools
```
Expected: completes, names the branch it created, reports the build command passing.

- [ ] **Step 2: Review the diff**

```bash
git branch
git diff master <branch-name>
```
Expected: `var` → `let`/`const`, `new Buffer(...)` → `Buffer.from(...)`, `package.json` `engines.node` bumped toward `22`. Record whatever it actually changed — this transformation may or may not also touch the callback shape (unlike the Lambda-specific transformation, this one isn't required to force async).

- [ ] **Step 3: Independently re-run the test on that branch**

```bash
git checkout <branch-name>
node test/local-invoke.js
git checkout master
```
Expected: `local-invoke: all assertions passed`.

- [ ] **Step 4: Merge**

```bash
git merge --no-ff <branch-name> -m "Merge AWS Transform Node.js version upgrade"
cd ..
```

- [ ] **Step 5: Flatten**

```bash
cd poc-nodejs && git log --format='%H %s' > /tmp/poc-nodejs-history.txt && cat /tmp/poc-nodejs-history.txt && cd ..
rm -rf poc-nodejs/.git
```

- [ ] **Step 6: Execute the upgraded code for real**

```bash
node poc-nodejs/test/local-invoke.js
```
Expected: `local-invoke: all assertions passed` — run fresh after flattening, on the actual local Node v26.4.0.

- [ ] **Step 7: Write `poc-nodejs/README.md`**

Using the real diff, the real commit history from Step 5, and the real output from Step 6: setup, exact commands, before/after code, results. Same structure as `poc/README.md`.

- [ ] **Step 8: Commit in the parent repo**

```bash
git add poc-nodejs
git commit -m "Add Node.js version-upgrade POC (12-style to 22, via AWS/nodejs-version-upgrade)"
```

---

### Task 7: Wrap up — cross-language summary, push

**Files:**
- Modify: `README.md` (repo root)

- [ ] **Step 1: Update the root README**

Add a short section (or extend the existing Status section) summarizing all three local POCs, linking to `poc-python/README.md`, `poc-java/README.md`, `poc-nodejs/README.md`, alongside the existing `poc/README.md` (Lambda). State plainly that these three are local-only (no AWS deployment), unlike the Lambda POC.

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "Summarize multi-language local runtime upgrade POC, link all three write-ups"
```

- [ ] **Step 3: Run the full local test suite one more time, on the final merged state**

```bash
python3 poc-python/test/test_app.py
(cd poc-java && mvn -q compile exec:java)
node poc-nodejs/test/local-invoke.js
```
Expected: all three print `local-invoke: all assertions passed`.

- [ ] **Step 4: Push**

```bash
git push
```
