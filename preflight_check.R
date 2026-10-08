# Credit Risk Demo -- Pre-flight Check
# =============================================================================
# Run this before any rehearsal or the live session itself. Confirms the
# environment is actually ready rather than discovering a problem live.
# Does NOT deploy anything -- if the service isn't ready, it tells you to
# run 01_demo.qmd's deploy chunk yourself (budget 7+ minutes) rather than
# doing it automatically here.

suppressPackageStartupMessages({
  library(skiLift)
  library(skiPatrol)
})
source("_config.R")

pass <- function(msg) cat(sprintf("  OK   %s\n", msg))
fail <- function(msg) cat(sprintf("  FAIL %s\n", msg))
info <- function(msg) cat(sprintf("  ..   %s\n", msg))

overall_ok <- TRUE

cat("=== 1. Connection ===\n")
conn <- tryCatch(
  sfr_connect(name = CR_CONNECTION_NAME, database = CR_DATABASE,
              schema = CR_REGISTRY_SCHEMA,
              warehouse = if (!is.null(CR_WAREHOUSE) && nzchar(CR_WAREHOUSE)) CR_WAREHOUSE else NULL),
  error = function(e) { fail(sprintf("sfr_connect() failed: %s", conditionMessage(e))); NULL }
)
if (is.null(conn)) {
  overall_ok <- FALSE
} else {
  pass(sprintf("Connected (account resolved, warehouse=%s)", conn$warehouse %||% "<default>"))
}

if (!is.null(conn)) {
  reg <- sfr_model_registry(conn, database = CR_DATABASE, schema = CR_REGISTRY_SCHEMA)

  cat("\n=== 2. Feature Store ===\n")
  fs <- tryCatch(
    sfr_feature_store(conn, database = CR_DATABASE, schema = CR_FEATURE_SCHEMA,
                       warehouse = conn$warehouse, create = FALSE),
    error = function(e) { fail(sprintf("Feature Store not reachable: %s", conditionMessage(e))); NULL }
  )
  if (!is.null(fs)) {
    fvs <- tryCatch(sfr_list_feature_views(fs), error = function(e) NULL)
    expected_fvs <- c("CUSTOMER_PROFILE_FV", "PAYMENT_BEHAVIOR_FV", "CREDIT_HISTORY_FV")
    present <- expected_fvs %in% (fvs$NAME %||% character(0))
    if (all(present)) {
      pass(sprintf("All %d expected Feature Views present", length(expected_fvs)))
    } else {
      fail(sprintf("Missing Feature Views: %s", paste(expected_fvs[!present], collapse = ", ")))
      overall_ok <- FALSE
    }
  } else {
    overall_ok <- FALSE
  }

  cat("\n=== 3. Model Registry ===\n")
  versions <- tryCatch(sfr_show_model_versions(reg, "SFR_CREDIT_RISK_SCORER"),
                        error = function(e) NULL)
  if (is.null(versions) || nrow(versions) == 0) {
    fail("SFR_CREDIT_RISK_SCORER has no registered versions")
    overall_ok <- FALSE
  } else {
    pass(sprintf("%d version(s) registered", nrow(versions)))
    info(paste("Versions:", paste(versions$name, collapse = ", ")))
  }

  cat("\n=== 4. SPCS Service ===\n")
  svc_status <- tryCatch(sfr_get_service_status(reg, "credit_risk_svc"),
                          error = function(e) NULL)
  if (is.null(svc_status)) {
    info("Service not found -- 01_demo.qmd's deploy chunk will create it (budget 7+ min)")
  } else if (identical(svc_status$status, "READY")) {
    pass("Service READY -- live run will skip redeploy")
  } else {
    fail(sprintf("Service exists but status is '%s', not READY", svc_status$status))
    overall_ok <- FALSE
  }

  cat("\n=== 5. Champion version set ===\n")
  model_info <- tryCatch(sfr_get_model(reg, "SFR_CREDIT_RISK_SCORER"),
                          error = function(e) NULL)
  if (!is.null(model_info) && !is.null(model_info$default_version) &&
      nzchar(model_info$default_version)) {
    pass(sprintf("Default (champion) version set: %s", model_info$default_version))
  } else {
    fail("No default version set on SFR_CREDIT_RISK_SCORER -- run 01_demo.qmd's set-champion chunk")
    overall_ok <- FALSE
  }
}

cat("\n=================================\n")
if (overall_ok) {
  cat("PRE-FLIGHT: PASS -- ready for rehearsal/live run.\n")
} else {
  cat("PRE-FLIGHT: FAIL -- see above. Do not attempt the live demo until resolved.\n")
}
