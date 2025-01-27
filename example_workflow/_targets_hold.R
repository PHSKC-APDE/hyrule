# Load packages required to define the pipeline:
library(targets)
library('hyrule')

# Set target options and load functions ----
tar_option_set(
  packages = c('data.table', 'hyrule', 'stringr', 'arrow')
)

# Much of the code/functions to make the pipeline run are stored in example_workflow/R
tar_source()

# Update the data ----
## This section of targets loads, cleans, organizes, and saves the various data inputs.
## Inputs may include things like ZIP centriods or nickname lists that ultimately get transformed into predictor variables
## Derivative columns (e.g. frequencies) should also be created at this step.
## Data should generally come in two forms -- one big dataset (e.g. for deduplication or dedupe and link)
## or as two different parts (link only).

## Link only example ----
s1_load_data_link_only = list(

  tar_target(data_1, init_data(input, output_file), format = 'file'),
  tar_target(data_2, init_data(input, output_file), format = 'file'),
  tar_target(loc_history_1, init_loc_history(input, output_file), format = 'file'),
  tar_target(loc_history_2, init_loc_history(input, output_file), format = 'file'),
  tar_target(frequency_tables, create_frequency_table(data_tables = list(data_1, data_2), columns = c('first_name_noblank')))

  # Other stuff to be used
)

s1_load_data_link_dedupe = list(

  tar_target(data_1, init_data(input, output_file), format = 'file'),
  tar_target(data_2, data_1, format = 'file'),
  tar_target(loc_history_1, init_loc_history(input, output_file), format = 'file'),
  tar_target(loc_history_2, init_loc_history(input, output_file), format = 'file'),
  tar_target(frequency_tables, create_frequency_table(data_tables = list(data_1), columns = c('first_name_noblank')))

  # Other stuff to be used
)

# Training (and test) data ----

## make and save trianing data for the test ----
## Training pairs should be saved at the hash_id level (e.g. below source id)
## The hyrule package makes the pairs available at the source id level
## This function converts from source id level to a randomly selected hash id nested within source id
## Also, this function is only necessary for the purposes of demonstration

s2_convert_sid_hid = list(
  tar_target(export_training)
)

## prepare training data ----
s2_prepare_training_data = list(
  # Load files with the labeled pairs

  # Add variables to the labelled pairs

  # Create a hash on the training data so that we don't rerun things if stuff hasn't changed

  # Create the test/train split
)

# Blocking ----
s3_block = list(
  # Generate the list of blocking rules
  # Compute each list of pairs to evaluate
  # Assemble and deduplicate
  # Chunk for processing in parallel
)

# Modeling ----
s4.1_folds = list()
s4.2_screener = list()
s4.3_submodels = list()
s4.4_ensemble = list()

# Prediction ----
s5_prediction = list(
  # predictions
  # fixed links
)

# Compile results ----
s6_compile_results = list(

)

# Identify cutpoint ----
s7.1_compute_cutoffs_cv = list()
s7.2_identify_cutpoint = list()

# Create study ids ----
s8_create_study_ids = list(
  # Convert 1:1 links and networks and aggregate where required
  # Create a study id table with some amount of persistence
)
