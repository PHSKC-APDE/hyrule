tar_option_set(
  packages = c('data.table', 'hyrule', 'stringr', 'arrow', 'duckdb', 'DBI')
)

# Much of the code/functions to make the pipeline run are stored in example_workflow/R
tar_source()

# Specify input and output directories
outdir = 'output/'

