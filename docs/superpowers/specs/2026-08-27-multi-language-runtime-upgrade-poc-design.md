# Design: Multi-Language Local Runtime Upgrade POC

## Purpose

The first Phase 2 POC (`poc/`) proved AWS Transform's managed
`AWS/lambda-nodejs-runtime-upgrade` transformation against a real, deployed
AWS Lambda function. This spec covers a follow-up, broader POC: prove the
same capability across **three languages** — Python, Java, and Node.js —
using AWS's general-purpose (non-Lambda-specific) managed transformations,
entirely **local** — no cloud deployment step. The goal is breadth (does
this work across languages, not just one Lambda runtime) rather than depth
of any single deployment story.

## Scope

In scope: one small toy app per language (Python, Java, Node.js), each
upgraded in place via its own AWS-managed transformation, verified by
actually running the transformed code locally (not just reviewing a diff).

Out of scope: any AWS deployment (Lambda, EC2, or otherwise) — confirmed
explicitly with the user; custom-authored transformation definitions —
all three transformations used already exist as AWS-managed definitions in
the registry (`atx custom def list`), so no `SKILL.md` authoring is needed.

## Prerequisites (verified locally before designing this)

- `atx` CLI 3.11.0 — already installed (`~/.local/bin/atx`), reused from
  the Lambda POC.
- Registry confirmed to contain (via `atx custom def list`):
  `AWS/python-version-upgrade`, `AWS/java-version-upgrade`,
  `AWS/nodejs-version-upgrade` (general-purpose — distinct from
  `AWS/lambda-nodejs-runtime-upgrade`, already used and not reused here).
- Local toolchains verified present: `python3` 3.14.5, OpenJDK 17.0.19
  (Corretto) + `javac` 17.0.19 + Maven 3.9.15, Node.js v26.4.0.
- AWS credentials still required — `atx` itself is an AWS service call even
  though nothing gets deployed. Reuses the same `default` CLI profile
  already authenticated in the prior session.
- Java's build/validation command needs Maven's `exec-maven-plugin`,
  fetched from Maven Central on first run — requires network access once.

## Target versions (chosen so the "after" code can actually run on what's
## installed locally, not just be diffed)

| Language | Transformation | Source (as-written) | Target |
|---|---|---|---|
| Python | `AWS/python-version-upgrade` | 3.8-style | 3.13 |
| Java | `AWS/java-version-upgrade` | 8-style | 17 |
| Node.js | `AWS/nodejs-version-upgrade` | 12-style | 22 |

All three match Phase 1's own named worked examples (not arbitrary
choices). Python and Node.js targets are proven by running the transformed
code on the single locally-installed interpreter (3.14 and v26.4.0
respectively, both supersets of the target syntax) — this is an honest
limitation worth stating plainly: we are not proving execution under an
*exact* 3.13 or Node-22 interpreter, only that the code is written in a way
compatible with it and runs correctly on a newer one. Java is the one
language where the target (17) exactly matches the installed JDK, so it
gets a fully precise proof.

## Architecture

```
aws-transform-runtime-upgrade-lab/
├── poc/                          (existing, Lambda-specific — untouched)
├── poc-python/
│   ├── README.md                 (written last)
│   ├── app.py                    (old-style: typing.Dict/Optional)
│   └── test/
│       └── test_app.py           (plain assert-based, no pytest)
├── poc-java/
│   ├── README.md
│   ├── pom.xml                   (exec-maven-plugin configured, target 8 → 17)
│   └── src/main/java/com/example/App.java   (verbose POJO before, record-eligible after)
└── poc-nodejs/
    ├── README.md
    ├── package.json              (engines.node bumped by the transformation)
    ├── index.js                  (var / new Buffer() / callback style)
    └── test/
        └── local-invoke.js       (plain assert-based, dual callback/promise-tolerant)
```

Each `poc-<lang>/` is `git init`'d as its **own repo only for the duration
of the `atx` run** (a hard requirement of the tool — same as `poc/lambda`
before it), then **flattened immediately after merging** — its `.git`
removed, real commit history preserved as text in that folder's
`README.md`. This applies the lesson learned from the Lambda POC directly,
rather than repeating the same gap.

## Components

**`poc-python/app.py`** — a `greet(name)` function using pre-3.9 typing
style (`typing.Dict`, `typing.Optional`) to describe its return shape — a
concrete, well-known modernization target (`dict[str, str]`, `str | None`).

**`poc-python/test/test_app.py`** — calls `greet` directly, asserts on the
returned message for both a given name and the default case, prints a pass
marker, exits non-zero on failure. Doubles as `atx`'s validation gate
(`--build-command "python3 test/test_app.py"`).

**`poc-java/src/main/java/com/example/App.java`** — a static nested
`Greeting` class written as a verbose hand-rolled POJO (private final
field, explicit constructor, getter, `toString`) — the single most common
Java modernization target for a `record` (Java 16+, in reach of target 17).
`main()` runs the same two assertions as the other languages and exits
non-zero on failure — no JUnit dependency added, consistent with the
Python/Node test philosophy.

**`poc-java/pom.xml`** — minimal single-module Maven project,
`maven.compiler.release` starting at `8`, `exec-maven-plugin` configured
with `mainClass=com.example.App` so `mvn -q compile exec:java` runs the
self-check directly. This is also the `--build-command` `atx` uses.

**`poc-nodejs/index.js`** — `formatGreeting(name, callback)` written with
`var`, callback style, and the deprecated `new Buffer(str, 'utf8')`
constructor (Phase 1's own cited example of a Node-version-relevant
pattern). Distinct code from `poc/lambda` — this is a general Node.js
module, not shaped like a Lambda handler, since the transformation here is
general-purpose, not Lambda-specific.

**`poc-nodejs/test/local-invoke.js`** — calls `formatGreeting` directly;
tolerant of the function staying callback-style or becoming
Promise-returning after transformation (same dual-mode pattern proven to
work in the Lambda POC), so the same test file validates both before and
after without editing.

## Data flow (per language, run independently but following the same shape)

1. Write the "before" app + local test in the style described above.
2. `git init` that folder as its own repo, first commit.
3. Run `atx custom def exec` with the language's transformation name,
   `--build-command` set to that language's test command, `--configuration
   additionalPlanContext="..."` naming the target version, plus
   `--non-interactive --trust-all-tools` (all confirmed necessary from the
   Lambda POC's Task 1/5 findings).
4. Review the diff on the branch `atx` creates; independently re-run the
   local test on that branch (don't trust `atx`'s own "Build status:
   Success" report alone).
5. Merge the branch into that folder's `master`.
6. **Flatten immediately**: remove the nested `.git`, preserve its commit
   log as text in `poc-<lang>/README.md`, `git add` the folder's files into
   the parent repo.
7. Actually execute the upgraded code with the real local toolchain
   (`python3 test/test_app.py`, `mvn -q compile exec:java`, `node
   test/local-invoke.js`) as the final proof, not just a reviewed diff.
8. Write `poc-<lang>/README.md`: the actual before/after code diff, the
   real test output, and (where available) version-relevant metadata that
   changed (`typing` → builtin generics, `maven.compiler.release`,
   `package.json` `engines.node`).

## Error handling / guardrails

- If a language's transformation fails its build/validation gate, that's a
  real signal reported as-is — not papered over to force a "success"
  narrative, same principle as the Lambda POC.
- Java's dependency on network access (Maven Central for
  `exec-maven-plugin`) is called out up front rather than discovered
  mid-run.
- Each language's sub-POC is independent — if one language's transformation
  behaves unexpectedly, that doesn't block the other two from proceeding
  and being reported honestly on their own merits.

## Testing

- Same three-tier proof as the Lambda POC: (1) local test passes before
  the transformation, (2) `atx`'s own validation gate passes during the
  transformation, (3) the test is independently re-run after, on the
  transformed branch, by us — not just trusted from `atx`'s report.
- Additionally here: the transformed code is actually executed with the
  real locally-installed toolchain post-merge, not just diffed.

## Cleanup story

None needed beyond normal repo hygiene — no AWS resources are created by
this POC (confirmed with the user), so there is nothing external to tear
down. The only "resource" created is Maven's local `~/.m2/repository`
cache from the `exec-maven-plugin` download, which is a normal, harmless,
reusable local build cache — not cleaned up as part of this POC.
