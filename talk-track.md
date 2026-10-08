# Credit Risk Demo — Talk Track

**Written:** 7 September 2026. For whoever presents `01_demo.qmd` live — Samiul, Chandra, or
Simon. Pairs with `RUNBOOK.md` (environment/technical) and `preflight_check.R` (run this
first, always).

**Golden rule: run `preflight_check.R` before you present, every time.** If it says FAIL,
fix that before touching the notebook live. If the SPCS service isn't `READY`, deploy ahead
of time — never trigger `sfr_deploy_model()` live (7+ minutes of dead air).

## Framing (30 seconds, before opening the notebook)

*"Were using this use-case as an example, but any ML modelling use-case would it apply here. This is a credit risk scoring model, built and deployed entirely inside Snowflake, using
R. Not R exporting data out to score it somewhere else — R running against a Snowflake Feature Store, Model Registry, and a container service, all native to the platform. You can interact with create, modify, manage/deploy, and drop any of the objects within Snowflakes ML eco-system. The point isn't the credit risk use case, it's that any organisations existing R/tidymodels workflow doesn't have to leave Snowflake to go to production, and R users can interact with Snowflake using existing R skills , packages and tooling, in an R idiomatic way."*

## Section 1 — Setup and Connect

Skip narrating the connection mechanics unless asked. One line: *"This connects the same way
regardless of where it's running — locally, in a Native App, in a Workspace Notebook — the
package figures out the right method itself. It uses the default connection parameters it detects for the environment it's running in, but you can over ride those defaults."* Move on quickly; this section has no visual payoff.

## Section 2 — Feature Store

**This is a good place to slow down.** Three feature views, each defined as an ordinary
`dplyr` pipeline:

- **CUSTOMER_PROFILE_FV** — static demographics, defined via a rendered SQL string (show
  `dbplyr::sql_render()` output — *"this is just dplyr, compiled to SQL, nothing exotic"*).
- **PAYMENT_BEHAVIOR_FV** — the interesting one: `refresh_freq = "1 hour"` makes this a
  **Dynamic Table**. *"Snowflake keeps this current automatically — no cron job, no
  Airflow DAG, it's a property of the feature definition."*
- **CREDIT_HISTORY_FV** — same pattern, static this time.

Talking point: *"Define once here, and the exact same feature logic runs at training time
and at inference time later — that consistency is usually where ML pipelines quietly break - or inaccuracies are introduced due to subtle changes in logic.  The Feature Views that you create here can be used by other Data Scientists, including Python users.  Were creating re-usable assets here that will build as a collection of managed features over time.  The defined transformation from the dplyr code, translated to SQL within Snowflake runs as a continuous data-pipeline using Snowflakes Dynamic Tables, so any changes in the underlying source tables, are autmatically applied to the Feature View based on the defined refresh frequency setting"*

## Section 3 — EDA

Three charts (default distribution, income vs default, employment length vs default). Let
these land — the story is "realistic signal, ~15% default rate, not toy data." Don't over-
narrate the ggplot code.

## Section 4 — Training Data from Feature Store

One line: *"The Feature Store does the joins — I just tell it which spine table to use (contains entity-keys + training-label) and which features I want."*  `sfr_generate_training_data()` is the payoff line to say out loud. 

## Section 5–6 — tidymodels Training and Evaluation

Standard tidymodels — audience familiar with R will recognise this model pipeline immediately, which is the point: *"Nothing about the modeling code is Snowflake-specific."* Show the CV comparison chart and the ROC curves; skip narrating the recipe steps in detail.

**As tested 7 Sep:** Logistic Regression AUC 0.877 beat XGBoost AUC 0.817 on this synthetic
data (unusual for XGBoost to lose, but this is intentionally simple synthetic data —
mention it if asked, don't dwell on it).

## Section 7 — Register Models and Select Champion

**Key moment.** Both models get registered as versions of one logical model
(`SFR_CREDIT_RISK_SCORER`), metrics attached, then champion selection happens
**programmatically from the registry** — not from a local R variable. Say this explicitly:
*"The registry is the source of truth. Anyone downstream querying this model gets whatever
version is marked default — governed, not tribal knowledge."*

## Section 8 — Deploy and Inference

**If `preflight_check.R` passed, the deploy chunk will print "Service already READY —
skipping redeploy" almost instantly.** That's expected and good — say so: *"This step
normally takes several minutes to build and deploy the container image service and
endpoints; it's already warm from earlier today."* Don't apologize for skipping it — frame
it as exactly what you'd do in production (deploy once, serve many times). You can manage
versions of models, and deploy new models when ready to replace an existing in-service
model.

Show both scoring paths:
- **REST** (`sfr_predict()`) — the R-native path.
- **SQL** (`CREDIT_RISK_SVC!PREDICT(...)`) — *"and here's the same model, callable from plain
  SQL — any BI tool, any scheduled task, no R or Python required to use it."* This is
  usually the line that lands best with a mixed technical/business audience.

**Autocapture:** don't wait on this live — it's an asynchronous pipeline (same
architecture as SPCS event-table logs/metrics), typically 1–10 minutes before rows
appear, even though the scoring itself already succeeded. **Line to use if it's not there
yet:** *"This logs automatically to an inference table for observability — it's an
async pipeline, so there's usually a few minutes' lag between a request and the row
landing; the scoring itself is what matters here, this fills in shortly after."* Confident,
not apologetic — this is documented Snowflake behaviour, not something broken in this
demo. If you want it to actually show rows live, run the REST/SQL scoring chunks a few
minutes before you reach this section (e.g. during Q&A on an earlier section) rather than
immediately before.

## Section 9 (Optional) — Model Monitoring

**Skip this entirely if time is short** — nothing later depends on it. If you include it:
*"Registering and deploying a model is the start, not the end — this is the same registry
tracking drift and performance over time, automatically, on a schedule."* Show the stats
(volume) and performance (accuracy/F1) numbers — they compute immediately, no waiting.
**Don't promise drift metrics** — those need a baseline setup that isn't wired up yet
(see `RUNBOOK.md`); if asked, say so plainly rather than trying to show it.

## If something breaks live

- **Deploy chunk actually starts building (service wasn't pre-warmed):** narrate through it
  — *"this is building a container with R, tidymodels, and the model dependencies baked in
  — normally a few minutes"* — and either wait it out with commentary, or cut to Q&A and
  come back once it's ready. Don't stand in silence.
- **A step errors outright:** you have `01_demo_samiul_original.qmd`'s output and this
  session's own validated run as a fallback narrative — you can talk through what *should*
  happen and show registry/Feature Store state from the Snowflake UI directly while the
  R side is debugged off-screen.
- **Connection fails:** almost certainly an environment/credential issue, not a code issue —
  don't try to debug package internals live; switch to the backup environment if there is
  one, or move to Q&A.

## Timing budget (rough, for a ~15 minute slot)

| Section | Minutes |
|---|---:|
| Framing | 0.5 |
| Setup/connect | 0.5 (narrate, don't dwell) |
| Feature Store | 3 |
| EDA | 1.5 |
| Training/evaluation | 3 |
| Registry/champion | 2 |
| Deploy + scoring | 3 (assumes pre-warmed service) |
| Monitoring (optional) | 1.5 (skip entirely if short on time) |
| Buffer/Q&A | 1.5 |
