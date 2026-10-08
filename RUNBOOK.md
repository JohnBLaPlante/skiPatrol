# Credit Risk Demo — Runbook

**Written:** 7 September 2026, after validating the full pipeline locally against a real
account (`ij38992`) and reconciling against Samiul's Native App run (1 Sep,
`error.log`). Read alongside `internal/testing-against-live-snowflake.md` (credential/scan
workflow) and `internal/effort-estimate.md` §C (conference demo scope, P1-05).

## Files in this directory

| File | What it is |
|---|---|
| `00_setup.qmd` | Run once: creates the database/schemas, generates synthetic lending data. Uses skiLift, not ODBC. |
| `01_demo.qmd` | The demo itself: Feature Store → tidymodels → Registry → champion → SPCS deploy → scoring. **Current, replaces Samiul's original.** |
| `_config.R` | Sourced by both `.qmd`s. Connection profile name, warehouse, database/schema layout — edit per environment, or set the matching env var. |
| `01_demo_samiul_original.qmd`, `_config_samiul_original.R` | Samiul's 1 Sep versions, preserved for reference. Used ODBC + a hand-built Snowpark session — both were Native-App-specific workarounds, neither needed now (see below). |
| `preflight_check.R` | Run before any live session — confirms the environment is actually ready (see below). |
| `talk-track.md` | Presenter narrative. |
| `error.log` | Samiul's original `sfr_deploy_model()` failure (P1-03's conda-pin bug, now fixed). Kept for provenance. |

## Why the rewrite — what Samiul's version worked around, and why it's gone

Samiul's version had two Native-App-specific workarounds, both now unnecessary:

1. **A hand-built Snowpark session** (`snowpark$Session$builder$configs(dict(connection_name = "workbench"))$create()`), which `sfr_connect()` picked up only by *exploiting* the
   `get_active_session()` misdetection bug that `9eebc51` fixes (see CLAUDE.md's sequencing
   warning). P1-02 added `sfr_connect(session = )` as the deliberate, supported version of
   this — but the new `.qmd` doesn't need either: `sfr_connect()`'s own auto-detection
   (profile-driven OAuth for Native App/Workbench, `connections.toml` locally, Workspace
   session token in Workspace Notebooks) handles it without any manual session plumbing.
2. **ODBC** (`DBI::dbConnect(odbc::snowflake(), ...)`), used only to get a `dplyr::tbl()`-
   compatible connection for the Feature Store SQL. skiPatrol's `sfr_connection` has no DBI/
   dbplyr methods — it's a Python/ML session wrapper, not a database connection — so dbplyr
   needs a real DBI connection. That's skiLift's job (per skiPatrol's own package
   description), not ODBC's. The new `.qmd` opens a second, small skiLift connection
   (`dbi_con`) for exactly this, alongside the skiPatrol connection (`conn`) used for
   everything else.

Neither workaround was a comment on skiPatrol/skiLift being broken — Samiul built the Quarto
port before P1-02 landed the fixes that make both unnecessary, and before the packages'
installed-in-Native-App copies would have included them (see "Before running in Native App"
below).

## Running it: three environments, one file

`_config.R`'s `CR_CONNECTION_NAME` defaults to unset (`NULL`), which lets
`sfr_connect()`/`dbConnect(Snowflake())` auto-detect. Confirmed working locally 7 Sep with a
single `connections.toml` profile. Leave it unset unless you have multiple local profiles.

`CR_WAREHOUSE` has **no working default** — it's account-specific (local testing used
Simon's own `FIELDY6961`, which won't exist elsewhere). Set it via `_config.R` or the
`CR_WAREHOUSE` env var before running, in every environment.

**Local:** needs `~/.snowflake/connections.toml` (never repo-local — see
`internal/testing-against-live-snowflake.md`) and both packages installed
(`R CMD INSTALL snowdropDB snowdropML` from the repo root, or `pkgload::load_all()` from
each, provided both packages' dependencies are resolvable from wherever you run it — see the
gotcha below on running from two separate `renv` projects).

**Posit Native App:** the platform writes its own OAuth profile; auto-detection picks it up.
No code change needed.

**Workspace Notebooks:** session-token auto-detection; no code change needed. (Note: the
mono-repo's polyglot notebook package, `snowflake-notebook-multilang`, is a *different*
piece of work — not maintained by Snowflake going forward, and not part of this demo's
dependency chain. Don't confuse the two.)

## Before running in Native App or Workbench specifically

**The P1-02/P1-03/DB-11 fixes must be in whatever build of skiLift/skiPatrol is installed
there.** As of 7 Sep these are committed locally (`skiLift` up to `98a3acb`, `skiPatrol` up
to `cef5488`) but **not pushed** anywhere (P1-01 hold — commercial leverage, see CLAUDE.md).
If Native App/Workbench installs from `posit-dev/skiLift`/`skiPatrol` or from a tarball built
before today, none of DB-11 (JWT account identifier), the P1-02 Native App auth fixes, or the
DB-4 shared-session cache fixes will be present. **Rehearsing in Native App with an old build
will reproduce old failures that are already fixed locally** — check the installed version
first, don't assume 1 Sep's environment is current.

## Timing — read this before scheduling a rehearsal

- **`sfr_deploy_model()` takes 7+ minutes**, confirmed locally 7 Sep, running from a bare
  laptop with no Native App/Workspace involvement at all. It blocks synchronously for the
  whole container image build + push + SPCS service start; by the time it returns, the
  service is already `READY`. This matches what Simon saw in the Native App (~5 min) and in
  Workspace Notebooks previously — **the delay is inherent to building a custom R/conda
  image (R + tidymodels + xgboost + ranger + rpy2 via conda-forge), not an environment-
  specific issue.**
- **Never trigger a fresh deploy live in front of an audience.** `01_demo.qmd`'s deploy chunk
  checks `sfr_get_service_status()` first and skips redeploying if the service is already
  `READY` — deploy well ahead of the session (see `preflight_check.R`), and the live run
  will skip straight past it.
- Everything else (Feature Store, training, registry, REST scoring) runs in seconds to low
  minutes even on the ~50K-row synthetic dataset.

## Optional: Model Monitoring (Section 9)

Added 7 Sep, validated live end-to-end. Skip it for a shorter demo -- nothing after it
depends on it. Three real constraints found in the process, none documented anywhere
beforehand:

1. **The model version must be logged with `task =`.** `sfr_add_monitor()` rejects a
   version registered without it. Section 7 now always sets
   `task = "TABULAR_BINARY_CLASSIFICATION"` -- harmless, pure registry metadata.
2. **Classification needs `prediction_class_columns`/`actual_class_columns`, not the
   score-column pair.** `sfr_monitor_source()` didn't expose these at all before 7 Sep --
   fixed in `skiPatrol` (`4e033ea`). If you're running against an older installed build,
   this section will fail with "Actual score column(s) were specified, but model was of
   task...".
3. **Class columns must be numeric (`0`/`1`), not `"yes"`/`"no"` strings**, and the
   timestamp column must be `TIMESTAMP_NTZ`/`DATE`, not the `TIMESTAMP_LTZ` that
   `CURRENT_TIMESTAMP()` returns by default. Both handled in the `.qmd`'s SQL.

**Stats and performance metrics compute immediately** — confirmed live, no scheduled-
refresh delay (unlike autocapture's asynchronous pipeline above). Valid performance metric
names for classification: `ROC_AUC` (needs `prediction_score_columns` too — a continuous
score, which our model doesn't expose, only a hard class label), `CLASSIFICATION_ACCURACY`
(not `"ACCURACY"` — that name is rejected), `F1_SCORE`, `PRECISION`, `RECALL`,
`MACRO_AVERAGE_PRECISION`/`RECALL`, `MICRO_AVERAGE_PRECISION`/`RECALL`.

**Drift metrics are not included.** They need a baseline distribution
(`sfr_add_monitor()`'s source config accepts a `baseline` table underneath, not yet
exposed via `sfr_monitor_source()`) -- unset by default, so `sfr_monitor_drift()` fails
with "Baseline is not set for model monitor". Follow-on, not fixed in this pass.

**Cost note:** a monitor runs on an hourly refresh against its configured warehouse
(confirmed live: `refresh_interval='1 hour'`, independent of `aggregation_window`) until
deleted or suspended. Delete it in cleanup if you're not actively using it — same
consideration as the SPCS compute pool.

**Minor rough edge, not fixed:** `sfr_show_model_monitors()` returns a single `monitor`
column containing a stringified Python object repr, not one column per field. Don't rely
on it for existence checks — use `sfr_get_monitor(reg, name = ...)` wrapped in
`tryCatch()` instead (what the `.qmd`'s idempotency guard does).

## Known gotchas

- **SQL positional scoring is fragile.** `CREDIT_RISK_SVC!PREDICT(col1, col2, ...)` takes
  positional arguments matching the model's registered input schema exactly. `input_cols`
  (from `sfr_input_cols(training_data, exclude = ...)`) preserves the training data's
  column order automatically — **don't hand-type or reorder this list**; a mismatch fails
  with a confusing type error (`Numeric value 'X' is not recognized`) rather than a clear
  one. (Found by hand-typing it in a throwaway test script — not a defect in the real
  pipeline, but a real trap if anyone "simplifies" this later.)
- **Autocapture lags by design — minutes, not seconds.** Local testing saw 0 rows after
  60s despite REST scoring genuinely succeeding through the deployed service; this is
  expected, not a defect. Autocapture writes to a Snowflake-managed inference table
  through an asynchronous pipeline — the same architecture SPCS uses for event-table
  logs/metrics, not synchronous with the inference response. No published SLA, but the
  architecture (and event-table precedent) points to roughly 1–10 minutes in practice.
  Snowflake's "immediate visibility" framing means *no pipeline to build yourself*, not
  *zero lag*. Failed requests are never captured, only successful ones.
  `01_demo.qmd`'s autocapture chunk now checks once, non-blocking, and says so plainly
  if nothing's there yet rather than hard-failing or polling live for minutes — **don't
  wait on this during a live demo**; check ahead of time, or run scoring earlier in the
  session so the rows have had time to land by the time you reach this chunk.
- **`warehouse` defaults differ between the packages** — skiLift's `dbConnect()` wants `""`
  for "not set" (an explicit `NULL` breaks its internal `nzchar()` check); skiPatrol's
  `sfr_connect()` wants `NULL` (its internal `%||%` fallback doesn't treat `""` as unset).
  `01_demo.qmd`'s connect chunk converts between them; if you add a new connection anywhere,
  match the pattern there, don't assume they're interchangeable.
- **Running skiLift and skiPatrol together needs one shared R library.** Each package has
  its own `renv` for its own development, but a script using both (like this demo) needs
  them installed into the same library — either both via `R CMD INSTALL` into the user
  library (what local testing used), or both added to one `renv` project. Don't try to
  `pkgload::load_all()` one from inside the other's `renv`-activated session.
- Harmless noise you'll see and can ignore: a `poetry`-related `reticulate` warning on
  `skiPatrol` load (no functional effect), and a Python `resource_tracker` semaphore warning
  at process exit.

## Live SPCS resources — cost while they exist, and "pre-warmed" doesn't mean "stays warm"

`R_CREDIT_POOL` (compute pool), `CREDIT_RISK_SVC` (service), and the
`R_CREDIT_IMAGES` image repo were created during local validation (7 Sep) and, unless torn
down, are still running and billing. **Still unresolved, needs a decision:** leave them
warm (avoids re-paying the 7-minute deploy closer to the date) or tear down and redeploy
fresh nearer the session. Teardown SQL is in `01_demo.qmd`'s cleanup section (`##
12. Cleanup`, currently `eval: false` — uncomment deliberately, don't blanket-enable).

**New finding, same day, ~2 hours after deploy:** checked the service again while writing
this runbook — it had gone from `READY` to `PENDING` / "No containers provisioned yet".
The compute pool itself is still `IDLE` (not deleted, `target_nodes=1`), but
`active_nodes=0` — the service scaled its container down after a period of inactivity,
independent of the pool. **"Deploy once and leave it warm" does not guarantee it stays
warm indefinitely.** Not yet characterised: whether it self-heals on the next request
(likely, but at some cold-start cost less than a full 7-minute rebuild since the image is
already pushed) or needs an explicit redeploy/resume. `preflight_check.R` will correctly
report this as FAIL either way — **always run it close to presentation time, not just
once earlier in the day.**

## Pre-flight checklist

Run `preflight_check.R` before any rehearsal or the live session itself. It checks
connection, Feature Views, a registered model with a default version set, and SPCS service
status — and tells you plainly whether a fresh deploy is needed (budget 7+ minutes if so).
