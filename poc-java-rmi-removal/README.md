# Java Version-Upgrade POC #2 — Results (Real Removed-API Fix)

A follow-up to `../poc-java/README.md`. That first Java POC only bumped a
version property — there was nothing in the toy app that actually needed
to change to compile on Java 17, so the transformation had nothing real to
fix. This POC deliberately builds a Java 11 app that uses an API **removed**
in Java 17, to see whether AWS Transform's `AWS/java-version-upgrade`
transformation can find and fix a genuine breaking change on its own — no
hints given about what the problem is.

## The forcing case: `java.rmi.activation`

RMI Activation (`java.rmi.activation.*`) was deprecated in JDK 15 and
**removed entirely in JDK 17** (JEP 407) — it has no drop-in replacement,
since it was removed as obsolete. This was verified empirically before
building anything, against the real local JDK 17:

```bash
$ javac --release 11 RmiCheck.java   # importing java.rmi.activation.ActivationException
exit: 0   # compiles fine at release 11

$ javac RmiCheck.java                # no --release flag, targets JDK 17 directly
error: package java.rmi.activation does not exist
```

The toy app (`App.java`) declares `greet()`/`main()` as
`throws ActivationException`, imported from `java.rmi.activation` — a
realistic pattern for legacy code carrying an unused checked-exception
declaration from old RMI-based integration code. Confirmed with a **clean**
Maven build (`mvn clean compile exec:java`, ruling out stale-bytecode false
positives) that this genuinely:
- Compiles and runs fine at `maven.compiler.release=11`
- **Fails to compile** at `release=17`: `package java.rmi.activation does not exist`

## Setup

- Same `atx` CLI 3.11.0, same transformation as `poc-java/`
  (`AWS/java-version-upgrade`), same generic prompt
  (`"This is a Maven app that should be upgraded to Java 17"`) —
  deliberately not hinting at the RMI Activation issue.
- `poc-java-rmi-removal/` was its own nested git repo during the `atx` run,
  flattened afterward. Real commit history, preserved for the record:
  - `0d91f13` Add toy Java app (11, uses now-removed java.rmi.activation) + self-check
  - `285c88a` Step 1: Upgrade Java version from 11 to 17 and replace removed java.rmi.activation.ActivationException with Exception. Build status: Success — the actual commit `atx` authored
  - `c87086f` Merge AWS Transform Java version upgrade (RMI Activation removal fix)

## Commands, in order

```bash
# 1. Local baseline (release 11)
mvn -q clean compile exec:java

# 2. Run the AWS-managed transformation (same generic prompt as before)
atx custom def exec \
  --code-repository-path . \
  --transformation-name AWS/java-version-upgrade \
  --build-command "mvn -q clean compile exec:java" \
  --configuration additionalPlanContext="This is a Maven app that should be upgraded to Java 17" \
  --non-interactive \
  --trust-all-tools

# 3. Merge the result branch, flatten the nested repo
git merge --no-ff <atx-result-staging-branch>

# 4. Run again, post-upgrade
mvn -q clean compile exec:java
```

## The actual code diff

```diff
--- a/pom.xml
+++ b/pom.xml
@@ -10,7 +10,7 @@
   <properties>
-    <maven.compiler.release>11</maven.compiler.release>
+    <maven.compiler.release>17</maven.compiler.release>
```
```diff
--- a/src/main/java/com/example/App.java
+++ b/src/main/java/com/example/App.java
@@ -1,7 +1,5 @@
 package com.example;
 
-import java.rmi.activation.ActivationException;
-
 public class App {
@@ -21,12 +19,12 @@
-    public static Greeting greet(String name) throws ActivationException {
+    public static Greeting greet(String name) throws Exception {
         ...
-    public static void main(String[] args) throws ActivationException {
+    public static void main(String[] args) throws Exception {
```

**This is the real result we were after**: `atx` correctly identified that
`java.rmi.activation.ActivationException` no longer exists on the target
version, removed the import, and — since there's no drop-in replacement for
a removed, obsolete API — made the sound judgment call to widen the
`throws` clause to the generic `Exception` (the exception was never
actually thrown in this code, so this is a completely correct, minimal
fix). It found this on its own from a generic "upgrade to Java 17"
instruction; nothing in the prompt mentioned RMI Activation.

## Results

| Check | Before (release 11) | After (release 17) |
|---|---|---|
| `java.rmi.activation` usage | present, compiles | removed entirely |
| `maven.compiler.release` | `11` | `17` |
| Clean build (`mvn clean compile exec:java`) | `local-invoke: all assertions passed` | `local-invoke: all assertions passed` |
| Naive property-only bump (no code fix) | — | **fails**: `package java.rmi.activation does not exist` (proven above) |
| Real execution, run fresh after flattening | — | `local-invoke: all assertions passed` (confirmed above) |

Agent Minutes used: 17.09.

**Conclusion:** unlike `poc-java/` (which only needed — and only got — a
version-number bump), this POC deliberately included a genuine JDK-17
breaking change with no automatic fallback. AWS Transform's
`AWS/java-version-upgrade` transformation found the actual removed API and
applied a sound, minimal, correct fix without being told what the problem
was — a materially stronger proof of the capability than the first Java
POC.
