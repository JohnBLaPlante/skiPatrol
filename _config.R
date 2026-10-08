# Credit Risk Demo Configuration
# Source this file at the top of each .qmd document.
# Edit the values below to match your Snowflake environment -- or set the
# matching environment variable so the same file works unmodified across
# local testing, Posit Native App, and Workspace Notebooks.

# -- Connection profile name (from ~/.snowflake/connections.toml) ------------
# Leave unset (NULL) to let sfr_connect()/dbConnect(Snowflake()) auto-detect:
# a single connections.toml profile, a Native App OAuth profile, or a
# Workspace Notebook session, in that priority order -- confirmed working
# locally with no name= argument (7 Sep). Only set this if you have multiple
# local profiles and need to pick a specific one (e.g. "ij38992" was used for
# local testing; "workbench" was Samiul's Native App/Workbench profile name).
# See internal/testing-against-live-snowflake.md.
CR_CONNECTION_NAME <- Sys.getenv("CR_CONNECTION_NAME", NA)
if (is.na(CR_CONNECTION_NAME) || !nzchar(CR_CONNECTION_NAME)) CR_CONNECTION_NAME <- NULL

# -- Warehouse -----------------------------------------------------------------
# No universal default -- this is account-specific (Simon's local testing
# used "FIELDY6961", which won't exist elsewhere). "" (not NULL -- dbConnect()/
# sfr_connect() default to "" and their internal nzchar() checks require it)
# falls back to the connection profile's / session's default warehouse; set
# CR_WAREHOUSE explicitly if your environment needs one named.
CR_WAREHOUSE <- Sys.getenv("CR_WAREHOUSE", "")

# -- Database layout ----------------------------------------------------------
CR_DATABASE        <- "CREDIT_RISK_ML"
CR_SOURCE_SCHEMA   <- "RAW_DATA"
CR_FEATURE_SCHEMA  <- "FEATURES"
CR_TRAINING_SCHEMA <- "TRAINING"
CR_REGISTRY_SCHEMA <- "MODELS"

# -- Helpers ------------------------------------------------------------------
fqn_source  <- function(name) paste(CR_DATABASE, CR_SOURCE_SCHEMA, name, sep = ".")
fqn_feature <- function(name) paste(CR_DATABASE, CR_FEATURE_SCHEMA, name, sep = ".")
fqn_training <- function(name) paste(CR_DATABASE, CR_TRAINING_SCHEMA, name, sep = ".")
fqn_model   <- function(name) paste(CR_DATABASE, CR_REGISTRY_SCHEMA, name, sep = ".")
