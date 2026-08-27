# Java Version-Upgrade POC — Results

Local-only follow-up to the AWS-deployed Lambda POC (`../poc/README.md`).
Ran AWS Transform's managed `AWS/java-version-upgrade` transformation
against a small Maven Java app, entirely locally — no AWS deployment.

## Setup

- `atx` CLI 3.11.0 (already installed for the Lambda POC)
- Local toolchain: OpenJDK 17.0.19 (Amazon Corretto), Maven 3.9.15 — this
  is the one language in this multi-language POC where the target version
  (17) exactly matches what's installed locally, so the "after" state is
  proven with full precision, not an approximation.
- `poc-java/` was its own nested git repo during the `atx` run (a hard
  requirement of the tool), flattened into this parent repo afterward.
  Its real commit history, preserved for the record:
  - `6c37428` Add toy Java app (verbose POJO, Java 8-style, pre-upgrade) + self-check
  - `0d3307c` Step 1: Upgrade Java version from 8 to 17 in pom.xml maven.compiler.release. Build status: Success — the actual commit `atx` authored
  - `dacbc9b` Merge AWS Transform Java version upgrade

## Commands, in order

```bash
# 1. Local baseline
mvn -q compile exec:java

# 2. Run the AWS-managed transformation
atx custom def exec \
  --code-repository-path . \
  --transformation-name AWS/java-version-upgrade \
  --build-command "mvn -q compile exec:java" \
  --configuration additionalPlanContext="This is a Maven app that should be upgraded to Java 17" \
  --non-interactive \
  --trust-all-tools

# 3. Merge the result branch, flatten the nested repo
git merge --no-ff <atx-result-staging-branch>

# 4. Run again, post-upgrade
mvn -q compile exec:java
```

## The actual code diff

```diff
--- a/pom.xml
+++ b/pom.xml
@@ -10,7 +10,7 @@
   <packaging>jar</packaging>
 
   <properties>
-    <maven.compiler.release>8</maven.compiler.release>
+    <maven.compiler.release>17</maven.compiler.release>
     <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
   </properties>
```

**Honest note:** the design anticipated the transformation might also
rewrite the hand-rolled `Greeting` POJO (private final field, explicit
constructor, getter, `toString`) into a Java 16+ `record` — a very common
Java modernization move, and something well within reach of a Java 17
target. It didn't. The transformation limited itself strictly to the
compiler-release bump, leaving `App.java` untouched. That's a legitimate,
more conservative result worth reporting honestly rather than the more
dramatic diff that was expected — `atx` itself noted in its own validation
log that this project has no dependencies or test suite beyond the
self-check, which may be why it saw no changes it judged in-scope beyond
the version bump.

## Results

| Check | Before | After |
|---|---|---|
| `pom.xml` `maven.compiler.release` | `8` | `17` |
| Build/run (`mvn -q compile exec:java`) | `local-invoke: all assertions passed` | `local-invoke: all assertions passed` |
| Real execution, run fresh after flattening | — | `local-invoke: all assertions passed` (confirmed above) |

Agent Minutes used: 15.50.

**Conclusion:** AWS Transform's managed `AWS/java-version-upgrade`
transformation correctly bumped the Maven compiler release target from 8
to 17 and confirmed the project still builds and runs on JDK 17 — a real,
verifiable upgrade, even though it was more conservative in scope (no code
style modernization) than the Python and Node.js POCs turned out to be.
