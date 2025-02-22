tar_option_set(
  packages = c('data.table', 'hyrule', 'stringr', 'arrow', 'duckdb', 'DBI', 'glue', 'stringr', 'sf', 'tidymodels', 'workflows', 'stacks', 'dplyr', 'ranger', 'xgboost', 'rlang', 'igraph')
)

# Much of the code/functions to make the pipeline run are stored in example_workflow/R
tar_source()

# Specify input and output directories
outdir = 'output/'

# other global variables
apply_screen = TRUE
bounds = c(.01, .99)

