# Design: AWS Transform Lambda Runtime Upgrade POC

## Purpose

Phase 1 of this lab (`README.md`) is research-only — a write-up of how AWS
Transform custom's "Language Version Upgrades" pattern works, compiled from
AWS docs, never run against a live account. Phase 2, this spec, is the
hands-on follow-up: actually install `atx`, run the AWS-managed
transformation `AWS/lambda-nodejs-runtime-upgrade` against a real toy Lambda
function, and deploy both the before and after versions to prove it works
end to end — not just read about it.

## Scope

In scope: one toy Node.js Lambda function, deployed twice (old runtime, then
upgraded runtime) to the same AWS account, with real invokes proving
behavior is preserved across the upgrade.

Out of scope: AWS Transform's other tracks (Mainframe, .NET, VMware),
authoring a *custom* transformation definition (we use AWS's pre-built one),
Scaled Execution across multiple repos, and the "continual learning"
lessons-curation workflow (`atx custom def learnings`) — all mentioned in
Phase 1's research but not needed to prove the core capability.

## Prerequisites (verified or to verify at implementation time)

- Node v26.4.0, git 2.54.0, AWS CLI 2.34.58 — all present locally (verified).
- `atx` CLI — not installed yet; install via the documented script
  (`curl -fsSL https://transform-cli.awsstatic.com/install.sh | bash`) as
  the first implementation task.
- AWS account: `default` CLI profile, account `043309363336`, assumed role
  `AWSReservedSSO_AdministratorAccess_...`, region `us-east-1` — session
  was expired and has since been refreshed via `aws login` (verified).
- IAM permissions for the AWS Transform custom API are **unverified** for
  this account/role. Since the role is AdministratorAccess, this is
  unlikely to block anything, but the first `atx` command run against real
  AWS is the actual verification — treat an access-denied there as a real
  finding, not a bug in this plan.
- `atx`'s exact CLI command surface (flag names, subcommands) is transcribed
  in Phase 1's `README.md` from AWS docs/blog posts and has never been run.
  Confirm real syntax via `atx --help` / `atx custom def exec --help` before
  trusting the README's example verbatim.

## Architecture

```
aws-transform-runtime-upgrade-lab/          (git repo, root: Phase 1 doc)
├── README.md                                (existing, untouched)
└── poc/
    ├── README.md                            (setup, commands, results — written last)
    ├── lambda/
    │   ├── index.js                         (old-runtime, callback-style handler)
    │   ├── package.json
    │   └── test/local-invoke.js             (local test harness)
    └── scripts/
        ├── deploy.sh                        (zip + create-function/update-function-code)
        ├── invoke.sh                        (aws lambda invoke against the real function)
        └── teardown.sh                      (delete function + IAM role)
```

`poc/lambda` is itself the git-tracked unit `atx` operates on — AWS Transform
custom requires its target to be a valid git repository, which it already
is as a subtree of this repo.

## Components

**`lambda/index.js`** — minimal handler that takes an event, does trivial
work (e.g. echoes/transforms an input string), and calls back the result.
Written callback-style on purpose, mirroring the exact before-pattern in
Phase 1's README (`exports.handler = function(event, context, callback)`),
so the upgrade has a real callback→async/await conversion to perform, not a
no-op.

**`lambda/test/local-invoke.js`** — invokes the handler locally with a fixed
sample event and asserts the output. Serves two roles: a pre-deploy sanity
check, and the build/validation command `atx` requires as its quality gate
(AWS Transform custom will not consider the transformation done until a
user-supplied test command passes against the transformed code).

**`scripts/deploy.sh`** — idempotent: creates the IAM execution role (basic
Lambda execution policy only — this function touches no other AWS
resources) on first run, zips `lambda/`, and does
`create-function`/`update-function-code` as appropriate. Takes the runtime
as an argument so the same script deploys both the before and after
versions.

**`scripts/invoke.sh`** — `aws lambda invoke` with a fixed test payload,
prints the response. Run before and after the upgrade to compare output
byte-for-byte.

**`scripts/teardown.sh`** — deletes the Lambda function and IAM role. Not
run automatically by anything else in this design; it's a deliberate,
separate step for whenever the lab is done, so a real (if trivial-cost) AWS
resource doesn't linger untracked.

## Data flow

1. Write `lambda/index.js` pinned to the oldest Node.js runtime AWS Lambda
   will still let us *create* a new function on. (Some fully-deprecated
   runtimes, e.g. nodejs14.x/16.x, may be blocked for new-function creation
   even though existing functions on them keep running — this is a real
   open risk, resolved by a discovery step in the implementation plan:
   attempt `create-function` starting from nodejs18.x and fall back to
   whatever the account actually accepts.)
2. `scripts/deploy.sh` creates the role + function with that runtime.
   `scripts/invoke.sh` proves it works pre-upgrade; output is saved for
   later comparison.
3. Install `atx`. Run it against `poc/lambda`:
   ```
   atx custom def exec \
     --code-repository-path poc/lambda \
     --transformation-name AWS/lambda-nodejs-runtime-upgrade \
     --configuration additionalPlanContext="Target Node.js 22 (current LTS)"
   ```
   (Exact flags confirmed against `atx --help` before running, per the
   prerequisites section above — this command is the README's documented
   example, not yet independently verified.)
4. Per AWS's own guardrails, this lands changes on a **separate git
   branch**, running `lambda/test/local-invoke.js` as the validation gate
   before it calls the transformation done.
5. Review the diff atx produced on that branch (callback→async/await,
   `package.json` `engines` field, any other pattern changes it made).
6. Checkout the branch, redeploy the **same** Lambda function via
   `scripts/deploy.sh` with the new runtime — proving an in-place upgrade,
   not a fresh function. `scripts/invoke.sh` again; diff the output against
   step 2's saved result — should match.
7. Write up `poc/README.md`: setup steps, the actual commands run, the
   before/after diff, before/after `invoke` output, and any surprises
   (e.g. if the discovery step in #1 didn't land on the first-guess
   runtime).
8. `scripts/teardown.sh`, run manually when the lab is done — not part of
   the "success" path, a separate deliberate cleanup step.

## Error handling / guardrails

- `deploy.sh` is written to be safely re-runnable (check-then-create for
  the role, `update-function-code` if the function already exists) so a
  failed or interrupted run doesn't require manual AWS console cleanup
  before retrying.
- If `atx`'s validation gate (the local test command) fails, that's a real
  signal the transformation broke something — the plan does not paper over
  a failing test to force the demo to "succeed."
- If IAM/API access for AWS Transform custom turns out to be missing
  despite AdministratorAccess (e.g. a service not yet enabled in this
  region/account), that gets reported as a finding, not worked around with
  broader permissions than the role already has.

## Testing

- Local: `node poc/lambda/test/local-invoke.js` — both pre- and
  post-transformation, and it's the same file atx uses as its own gate.
- Real AWS: `scripts/invoke.sh` before and after redeploy, output diffed.
- No automated test suite beyond this — matches the scale of the POC and
  the precedent set on other lab projects in this workspace.

## Cleanup story

Real AWS resources are created (one Lambda function, one IAM role) — both
essentially free at this scale but real and billable/visible in the
account. `scripts/teardown.sh` removes both. Left for the user to run
explicitly once the write-up is done, not auto-run at the end of the
implementation plan.
