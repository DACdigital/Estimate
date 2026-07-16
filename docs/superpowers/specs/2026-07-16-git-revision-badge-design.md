# Git revision badge — design

Date: 2026-07-16
Status: approved (interactive)

## Goal

Glanceable deployed-git-revision indicator to pinpoint what runs in prod.

## Decisions (user-approved)

- **Placement:** sidebar bottom, own micro-row under the user card — `text-[10px] font-mono text-base-content/25`, centered, `hover:text-base-content/50`, `title="Deployed revision"`. Hidden entirely when revision unknown.
- **Also in `/healthz`:** liveness JSON gains `"revision": sha | "unknown"` (curl-able without login).

## Mechanism

`Estimate.BuildInfo.git_sha/0`, precedence:
1. Compile-time `GIT_SHA` env — baked into the release via Docker builder-stage `ARG GIT_SHA` + `ENV` (`.dockerignore` excludes `.git`, so the image can't self-derive it).
2. Runtime `GIT_SHA` env (deploy-set; Dotenvy loads env in prod).
3. Local `git rev-parse --short=7 HEAD` at compile time (dev/test checkouts).
4. `nil` → badge hidden, healthz `"unknown"`.

Empty-string env values are treated as absent (Docker `ARG GIT_SHA=""` default must not bake `""`).

## Out of app's control (user follow-up)

CI uses the shared `dacdigital/gitlab-ci` docker template; it (or the deployment repo) must pass `--build-arg GIT_SHA=$CI_COMMIT_SHORT_SHA` / set `GIT_SHA` env — until then prod shows nothing (graceful).

## Files

- `lib/estimate/build_info.ex` (+ test, async: false — env mutation)
- `lib/estimate_web/controllers/health_controller.ex` liveness (+ new controller test)
- `lib/estimate_web/components/layouts/app.html.heex` (badge row after user section)
- `Dockerfile` builder stage: `ARG GIT_SHA=""` + `ENV GIT_SHA=${GIT_SHA}`

Known trade-off: compile-time value goes stale in a long-lived dev session until recompile — acceptable for a deploy marker.
