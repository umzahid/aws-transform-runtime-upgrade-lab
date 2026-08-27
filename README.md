# AWS Transform — Runtime / Language Version Upgrades

Research notes on how AWS Transform performs automated language-version
upgrades (e.g. Java 11 → 17, Python 3.8 → 3.11, Node.js legacy → current
LTS). This is a **research/exploration doc, phase 1** of a two-phase
learning task — phase 2 is a hands-on POC that actually runs the tool
against a small sample app, not yet started.

Compiled from AWS's own documentation and blog posts (linked at the
bottom) plus general language-upgrade knowledge — not yet verified
against a live AWS account.

## 1. Where this sits in AWS Transform

AWS Transform is AWS's agentic-AI modernization service, split into a
few tracks:

| Track | What it's for |
|---|---|
| AWS Transform for Mainframe | COBOL/mainframe analysis, decomposition, refactoring |
| AWS Transform for .NET (Windows) | .NET Framework → cross-platform .NET |
| AWS Transform for VMware | Discovery/planning/migration off VMware |
| **AWS Transform custom** | Everything else — including **language version upgrades** |

Runtime upgrades (Java, Python, Node.js version bumps) live under
**AWS Transform custom**, a general-purpose agentic transformation
engine driven by a CLI called `atx`. It's not a single-purpose "Java
upgrader" — it's a framework where "upgrade the language version" is
one of ten documented transformation *patterns* (others include SDK
migrations, framework upgrades, dependency bumps, even
language-to-language rewrites).

## 2. The "Language Version Upgrades" pattern

AWS classifies this pattern as **Low–Medium complexity**, with named
examples:

- Java 8 → 17
- Python 3.9 → 3.13
- Node.js 12 → 22
- TypeScript version upgrades

The framing matters: this is *upgrading to a newer version of the same
language*, distinct from (and simpler than) "Framework Upgrades"
(Spring Boot 2→3), "Framework Migrations" (Angular→React), or
"Language-to-Language Migrations" (Java→Python) — those sit higher on
AWS's own complexity scale.

## 3. Worked examples — what actually changes

**Java 11 → 17**
- Sealed classes, records, pattern matching become available — the
  agent may modernize idiomatic code, not just make it compile
- Removed/deprecated APIs (e.g. `SecurityManager` deprecation path
  starting in 17) need call-site fixes
- Module system (JPMS) friction if `module-info.java` or
  reflection-heavy libraries are involved
- Build tooling: Maven/Gradle plugin versions, `--release` flags, CI
  base image bumps

**Python 3.8 → 3.11**
- `distutils` deprecation, changes to `typing` (e.g. `TypedDict`,
  `Generic` behavior)
- Removed/relocated stdlib aliases (e.g. things 3.8 code imports
  straight from `collections` that later versions require from
  `collections.abc`)
- f-string and `match`/`case` (3.10+) as modernization opportunities,
  not just compatibility fixes
- Dependency compatibility sweep — pinned packages that don't support
  3.11 wheels yet

**Node.js (legacy → current LTS)**
- AWS's own worked example: callback-style handlers rewritten to
  `async`/`await`
  ```js
  // before
  exports.handler = function(event, context, callback) { callback(null, result); };
  // after
  exports.handler = async function(event) { return result; };
  ```
- `package.json` `engines` field, native `fetch` replacing
  `node-fetch`, deprecated Buffer constructors

In all three cases, the tool doesn't just bump a version string — it
does a dependency-compatibility pass and a code-pattern pass, then
proves the result via a build/test command you supply.

## 4. The workflow, mapped to real CLI commands

AWS describes a four-phase cycle:

1. **Define Transformation** — skipped entirely if you use an
   AWS-managed one (e.g. `AWS/lambda-nodejs-runtime-upgrade`).
   Otherwise you write a `SKILL.md` (natural language + docs + code
   samples) describing the upgrade.
2. **Pilot / PoC** — run against a small sample first:
   ```bash
   atx custom def exec \
     --code-repository-path . \
     --transformation-name AWS/lambda-nodejs-runtime-upgrade \
     --configuration additionalPlanContext="Target Node.js 24"
   ```
3. **Scaled Execution** — same command, run in bulk across many repos,
   tracked via a web dashboard (repos registered / completed /
   in-progress / failed).
4. **Monitor and Review** — the "continual learning" system extracts
   **lessons** from every run (explicit feedback + implicit issues it
   hit while debugging); you curate them with `atx custom def
   learnings`.

## 5. Guardrails — what it will and won't do

- Changes land on a **separate git branch** — nothing auto-merges
- A **build/validation command** you supply is the quality gate: tests
  must pass, dependency compatibility must be confirmed, before it
  calls the job done
- You can layer on your own extra checks (security scans, perf/pen
  tests) before deploying
- For Lambda specifically, AWS recommends deploying via **Versions +
  Aliases with traffic shifting**, so a bad upgrade is a fast rollback,
  not an incident
- **Lessons are account- and transformation-specific** — they don't
  leak across AWS customers, and you can archive ones that turn out to
  be bad advice

## 6. Prerequisites checklist for the hands-on phase (not started yet)

- OS: Linux/macOS/WSL
- **Node.js 20+ and Git** installed locally (the `atx` CLI itself needs
  Node, independent of which language you're upgrading)
- Install: `curl -fsSL https://transform-cli.awsstatic.com/install.sh | bash`,
  verify with `atx --version`
- A real **git repository** as the target — `atx` requires the working
  directory to be a valid git repo
- **AWS credentials** (existing AWS CLI profile) with IAM permissions
  for the AWS Transform custom API — not yet verified against any
  actual account/region
- Network egress to `transform-cli.awsstatic.com` and
  `transform-custom.<region>.api.aws`
- A small sample app pinned to an old runtime (e.g. a toy Python 3.8
  or Node callback-style Lambda) to actually run the upgrade against —
  cheaper and faster to verify than pointing it at something real

## Status

- [x] Phase 1 — research and write up how the capability works (this doc)
- [x] Phase 2 — hands-on POC: done, see [poc/README.md](poc/README.md)
      for the full write-up (before/after diff + invoke output)
- [x] Phase 2b — multi-language local POC: done, no AWS deployment (unlike
      Phase 2's Lambda POC, which deployed to real AWS). Proved AWS
      Transform's general-purpose managed transformations across three
      languages, each executed for real on the local toolchain after the
      upgrade:
  - [poc-python/README.md](poc-python/README.md) — `AWS/python-version-upgrade`,
    3.8-style → 3.13 (`typing.Dict`/`Optional` → `dict`/`str | None`)
  - [poc-java/README.md](poc-java/README.md) — `AWS/java-version-upgrade`,
    8 → 17 (`maven.compiler.release` bump)
  - [poc-nodejs/README.md](poc-nodejs/README.md) — `AWS/nodejs-version-upgrade`,
    12 → 22 (`new Buffer()` → `Buffer.from()`, deprecation warning
    confirmed gone after upgrade)
- [x] Phase 2c — [poc-java-rmi-removal/README.md](poc-java-rmi-removal/README.md):
      a second, harder Java case. `poc-java` above only needed a version
      bump; this one deliberately uses `java.rmi.activation` — an API
      genuinely removed in JDK 17 (JEP 407), verified empirically to break
      a naive version bump. `AWS/java-version-upgrade` found and correctly
      fixed it with no hints given.
- [x] Phase 2d — [poc-python-datetime-deprecation/README.md](poc-python-datetime-deprecation/README.md):
      a second, harder Python case. `poc-python` above only needed a
      typing-style modernization; this one deliberately uses
      `datetime.datetime.utcnow()` — genuinely deprecated since Python 3.12,
      verified to raise a real `DeprecationWarning` locally.
      `AWS/python-version-upgrade` replaced it with
      `datetime.now(datetime.timezone.utc)`, confirmed to genuinely remove
      the warning, with no hints given.

## Sources

- [AWS Transform custom docs](https://docs.aws.amazon.com/transform/latest/userguide/custom.html)
- [Getting Started with AWS Transform custom](https://docs.aws.amazon.com/transform/latest/userguide/custom-get-started.html)
- [Upgrading Lambda function runtimes at scale with AWS Transform custom](https://aws.amazon.com/blogs/compute/upgrading-lambda-function-runtimes-at-scale-with-aws-transform-custom/)
- [Automate AWS Lambda Runtime Upgrades with AWS Transform custom](https://aws.amazon.com/blogs/devops/automate-aws-lambda-runtime-upgrades-with-aws-transform-custom/)
