# Custom Transformation POC — POJO to Record

Every prior POC used an AWS-managed transformation. This one authors and
runs a **custom** transformation definition — the "Define Transformation"
step every earlier run skipped — to fix the exact gap `poc-java` left
behind: `AWS/java-version-upgrade` correctly bumped the compiler target
from 8 to 17 but did not modernize the hand-rolled `Greeting` POJO into a
Java 16+ `record`, even though it's a textbook candidate.

## The transformation definition

`definition/SKILL.md` — YAML frontmatter (`name`, `description`) plus a
natural-language body describing the pattern to detect (an immutable
value-holder: private final fields, a constructor that assigns them, a
getter per field, no other logic), what to do (rewrite as a `record`,
remove now-redundant `toString()`/`equals()`/`hashCode()` overrides, update
`getX()` call sites to the record's `x()` accessor), and a worked
before/after example — plus an explicit guardrail: only apply when the
target Java version is 16 or higher.

This is the same file format `atx custom def save-draft`/`publish` expect,
discovered empirically:

```
SKILL.md must start with --- frontmatter delimiter
```

## Registering the transformation

```bash
atx custom def save-draft \
  --transformation-name emumba-java-pojo-to-record \
  --description "Convert simple immutable value-holder POJOs into Java records (Java 16+)" \
  --source-directory definition

# save-draft alone was not enough — exec reported "not found in the registry"
# until the definition was published:
atx custom def publish \
  --transformation-name emumba-java-pojo-to-record \
  --source-directory definition \
  --description "Convert simple immutable value-holder POJOs into Java records (Java 16+)"
```

## The toy app

Same `Greeting` POJO pattern as `poc-java`, but already pinned to Java 17
from the start — isolating the test to just this one rule, not mixed in
with a version bump.

## Commands

```bash
cd app
atx custom def exec \
  --code-repository-path . \
  --transformation-name emumba-java-pojo-to-record \
  --build-command "mvn -q clean compile exec:java" \
  --non-interactive \
  --trust-all-tools
```

## The actual code diff

```diff
--- a/src/main/java/com/example/App.java
+++ b/src/main/java/com/example/App.java
@@ -2,21 +2,7 @@ package com.example;

 public class App {

-    public static class Greeting {
-        private final String message;
-
-        public Greeting(String message) {
-            this.message = message;
-        }
-
-        public String getMessage() {
-            return message;
-        }
-
-        @Override
-        public String toString() {
-            return "Greeting{message='" + message + "'}";
-        }
+    public record Greeting(String message) {
     }

     public static Greeting greet(String name) {
@@ -26,11 +12,11 @@ public class App {

     public static void main(String[] args) {
         Greeting result = greet("AWS Transform");
-        if (!result.getMessage().equals("Hello, AWS Transform!")) {
+        if (!result.message().equals("Hello, AWS Transform!")) {
             throw new AssertionError("unexpected: " + result);
         }
         Greeting defaultResult = greet(null);
-        if (!defaultResult.getMessage().equals("Hello, world!")) {
+        if (!defaultResult.message().equals("Hello, world!")) {
             throw new AssertionError("unexpected: " + defaultResult);
         }
         System.out.println("local-invoke: all assertions passed");
```

Exactly what the definition specified: the POJO became a one-line record,
the redundant `toString()` was removed, and — the harder part — both call
sites were correctly updated from `.getMessage()` to `.message()`, not
just the class declaration.

## A real rough edge hit along the way

`atx custom def get -n <name>` retrieves a definition into the **current
working directory** — running it from inside the target app's own folder
(to double check the published definition) dropped a stray
`emumba-java-pojo-to-record/` copy into the app itself, which then got
swept up into `atx`'s own transformation commit (`git add`-style behavior
inside the container). Removed with a follow-up commit before flattening.
Worth remembering: run `def get` from a scratch directory, never from
inside a repo that's about to be transformed.

## Results

| Check | Before | After |
|---|---|---|
| `Greeting` shape | hand-rolled POJO (7 lines) | `record Greeting(String message) {}` (1 line) |
| Call sites | `.getMessage()` | `.message()` (both updated) |
| `toString()` override | present | removed (record generates one) |
| Build (`mvn clean compile exec:java`) | `local-invoke: all assertions passed` | `local-invoke: all assertions passed` |
| Real execution, run fresh after flattening | — | `local-invoke: all assertions passed` (confirmed above) |

Agent Minutes used: 11.87.

**Conclusion:** AWS Transform's custom transformation mechanism works as
documented — a plain-language `SKILL.md` with a worked example is enough
to get correct, non-trivial refactoring (including consistent call-site
updates, not just the declaration) applied automatically, filling exactly
the gap the AWS-managed transformation left behind.
