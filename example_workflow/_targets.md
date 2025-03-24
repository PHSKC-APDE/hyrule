# ML Record Linkage Pipeline


- [About](#about)
  - [On this implementation](#on-this-implementation)
  - [Using machine learning to do record
    linkage](#using-machine-learning-to-do-record-linkage)
- [Set up](#set-up)
  - [Pipeline setup](#pipeline-setup)
  - [Packages and functions](#packages-and-functions)
- [ML Record Linkage Pipeline](#ml-record-linkage-pipeline)
  - [Data Preparation](#data-preparation)
  - [Training Data](#training-data)
  - [Blocking](#blocking)
  - [Model Specification](#model-specification)
  - [Predicting Match Scores](#predicting-match-scores)
  - [Evaluation and Cutoffs](#evaluation-and-cutoffs)
  - [From 1:1 links to networks](#from-11-links-to-networks)
  - [Final Pipeline](#final-pipeline)
- [Odds and ends](#odds-and-ends-6)
  - [Final output](#final-output)
  - [Glossary](#glossary)

# About

This document is an example implementation of machine learning record
linkage within a [targets
workflow](https://books.ropensci.org/targets/). While it is designed to
be a runnable pipeline, the primary goal of this example is to provide
ideas and show options that others can adapt to their own projects.

The funding and inspiration for this document derives from the NO HARMS
grant conducted at Public Health - Seattle & King County and funded by
the CDC. The pipeline and methods described below are heavily influenced
by the New Opportunities for Health and Resilience Measures for Suicide
Prevention (NO HARMS) pipeline, but are intended to be more generalized
and flexible.

## On this implementation

While this example pipeline demonstrates a classic linkage between two
datasets, the methods can be applied to any number of datasets. The NO
HARMS project from which this pipeline comes from linked and
deduplicated \>10 administrative datasets of varying size and data
density.

The number of input datasets can be scaled up infinitely (contingent on
computational constraints), although there is a potentially trade-off
between standardization and accuracy – as a multi-dataset model may have
a lower ceiling than a series of 1:1 dataset models. On the other hand,
a multi-dataset approach more naturally allows for the application of
relationships “learned” from a high data density datasets to lower
density ones. Also, one big model is likely easier to implement and run
than a bunch of smaller specialized ones.

A single dataset being linked against itself is a method of
deduplication.

## Using machine learning to do record linkage

### Record linkage (in brief)

Record linkage (aka entity resolution) is the process by which records
within and/or between datasets are analyzed and grouped together such
that they (ideally) represent a single entity (e.g., a person).
[(Almost) all of entity
resolution](https://www.science.org/doi/full/10.1126/sciadv.abi8021) and
the documentation for the
[Splink](https://moj-analytical-services.github.io/splink/topic_guides/topic_guides_index.html)
package are excellent resources and provide a more comprehensive
description of record linkage and its variations.

### Why use machine learning?

1.  Machine learning (and most regression-esque approaches) are
    relatively flexible. If you can convert your problem into a series
    of rows (e.g., whether two records match) with some predictor
    variables – you can fit your model. Although the flexible interface
    does occasionally mean it takes longer to get started, users get a
    lot more – especially when they want to be clever and/or create
    customized predictors. For example, this workflow compares the
    address histories between two records to determine the minimum
    observed geographic distance, which is then used a predictor. This
    type of variable is difficult to encode in a probabilistic
    interface.
2.  Ensembling methods (which flow naturally from a regression/machine
    learning type approach) allow users to employ multiple model
    families (and their various permutations) to generate the final
    match score. In the ideal case, each model will be good at a
    particular part of the overall problem, and then the whole of the
    models will be greater than the sum of the parts (or at least,
    better than an individual part). If nothing else, probabilistic
    approaches can be used within an overall ensemble.
3.  Any good record linkage project is going to require some manner of
    verifying if the resulting match determinations are any good (e.g.,
    is A a link to B). Since the “hassle” of creating a manually labeled
    training dataset already needs to get done – users might as well
    consider fitting some models on it. In practice, only a few hundred
    labeled pairs (maybe 2 - 3 hours of work) is required to get a
    ensemble up and running.

### Useful Concepts

Users should familiarize themselves with the following R-packages and/or
methodological concepts:

1.  Analysis pipeline(s): This workflow uses the
    [targets](https://books.ropensci.org/targets/) and
    [`tarchetypes`](https://docs.ropensci.org/tarchetypes/) to
    orchestrate the linkage pipeline. A targets pipeline is a directed
    acyclic graph that articulates how inputs, intermediate steps, and
    outputs all interact/flow into each other. Once the pipeline is
    specified, the targets package uses static code analysis (and other
    tricks) to determine how to keep the pipeline internally consistent
    and up to date. Via some partner packages (e.g.,
    [`crew`](https://github.com/wlandau/crew)), a targets pipeline can
    be computed in parallel fairly easily as the full dependency chain
    is pre-specified.
2.  Data manipulation and storage: most data tasks (e.g., cleaning,
    reshaping) are conducted via the
    [`data.table`](https://github.com/Rdatatable/data.table) R-package
    or [duckdb](https://github.com/duckdb/duckdb-r) dialect sql (via the
    `DBI`) package. The [`glue`](https://glue.tidyverse.org/) package is
    often used to craft sql statements. The
    [`arrow`](https://arrow.apache.org/docs/r/) package (along with
    `duckdb`) provides read/write routines for `.parquet` files.
    `.parquet` files are used because they are reasonably efficient
    storage wise and allow for partial read/writes.
3.  [stacking/ensemble
    learning](https://en.wikipedia.org/wiki/Ensemble_learning): The
    linkage method is an ensemble of machine learning models combined
    via stacked generalization (aka stacking). The
    [`stacks`](https://stacks.tidymodels.org/) package provides the
    implementation of the ensembling approach while
    [`xgboost`](https://xgboost.readthedocs.io/en/stable/R-package/xgboostPresentation.html),
    [`ranger`](https://github.com/imbs-hl/ranger), and
    [`kernlab`](https://cran.r-project.org/web/packages/kernlab/kernlab.pdf)
    implement algorithms that are ensembled together. [Lasso
    regressions](https://en.wikipedia.org/wiki/Lasso_(statistics)) via
    [`glmnet`](https://cran.r-project.org/web/packages/glmnet/index.html)
    are used as a screening model. Overall, the `hyrule` package and the
    `tidymodels` suite (e.g.,
    [`parnsip`](https://parsnip.tidymodels.org/),
    [`workflows`](https://workflows.tidymodels.org/),
    [`tune`](https://tune.tidymodels.org/),
    [`stacks`](https://stacks.tidymodels.org/), and
    [`yardstick`](https://yardstick.tidymodels.org/)`)` of packages are
    used to implement the algorithms
4.  Networks/clusters: Collections of 1:1 matches (i.e., when we think
    two records are the same person) may aggregate into full-fledged
    networks (i.e., we think several records are the same person) and
    can be analyzed as such.
    [`igraph`](https://en.wikipedia.org/wiki/Ensemble_learning) is used
    to analyze and adjust the linkage networks.
5.  [string distance
    metrics](https://journal.r-project.org/archive/2014-1/loo.pdf): Many
    of the character variable based comparisons (e.g., name similarity)
    are string distance metrics. More details can be found here.
    Implementation is done via
    [`DuckDB`](https://duckdb.org/docs/sql/functions/char.html)
    routines.

# Set up

## Pipeline setup

These packages are required to set up the pipeline.

``` r
library(targets)
library(tarchetypes)
library(glue)
library('data.table')
tar_source()
```

Remove the `_targets_r` directory previously written by non-interactive
runs of the report.

``` r
tar_unscript()
```

## Packages and functions

These packages and functions are required to have the pipeline run.

``` r
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

#> Establish _targets.R and _targets_r/globals/define-globals.R.
```

# ML Record Linkage Pipeline

### The “targets” notation

The pipeline specified below uses functions and notation from the
`targets` package. Each “target” or “step” follows the general form of
`tar_target(output name, operation(inputs))` where “output_name” is the
name of the target that is created by conducting an “operation” on a set
of “inputs”. Sometimes, functions from the `tarchetypes` package are
employed. These generally follow the same convention of `tar_target`,
but are used to specific types of inputs (e.g., file paths) and/or
classes of target generate (e.g., make a new target by some set of
parameters).

### Section overview

Each subsequent section will roughly the same structure:

- Overview: A description of what the series of targets accomplishes

- Targets: Code and commentary about the individual targets (i.e. steps)

- Odds and Ends: Any additional bits of information relevant to the user
  about the given section

## Data Preparation

### Overview

This series of targets loads and cleans the input data. Once cleaned,
some derivative variables are created. The outputs of this section will
be used in subsequent sections to create the predictor variables within
the model frame(s) in the training and prediction series of targets.

### Targets

#### Specify Input Files

The two datasets (`fake_one.parquet` and `fake_two.parquet`) to be
linked are registered by `tar_files_input` and the references are stored
into `input_1` and `input_2`.

``` r
list(
  # file paths to data
  tarchetypes::tar_files_input(input_1, '../data-raw/fake_one.parquet'),
  tarchetypes::tar_files_input(input_2, '../data-raw/fake_two.parquet')
)

#> Establish _targets.R and _targets_r/targets/specify-input-data.R.
```

#### Prepare Primary Identifiers

The `data` target (a data frame saved to disk as a parquet file) is
created by appending `input_1` and `input_2` together and conducting
some data cleaning on primary identifiers like name and date of birth. A
new unique row identifier (called `clean_hash`) is also created at this
step. A detailed description of what `init_data` does is provided in the
“Odds and Ends” section below.

``` r
list(
  # Load, clean, and save datasets
  tar_target(data, init_data(
    c(input_1, input_2), 
    file.path(outdir, 'data.parquet')), format = 'file')
)
#> Establish _targets.R and _targets_r/targets/clean-primary-ids.R.
```

#### Prepare list/“history” variables

`lh` and `zh` are list (i.e. history) variables saved as data frames
within parquet files for location and zip code respectively. The
`create_location_history` and `create_history_variable` functions
compile the unique list of locations (or ZIP code) by `source_system`
and `source_id`. The resulting information is used later when
constructing list intersection flags for the model frame (e.g., these
two records have been observed at the same location).

``` r
list(
  # Prepare the location histories
  tar_target(
    lh,
    create_location_history(
      input = c(input_1, input_2),
      # This changes based on data storage/format
      output_file = file.path(outdir, 'lh.parquet'),
      id_cols = c('source_system', 'source_id'),
      X = 'X',
      Y = 'Y'
    ),
    format = 'file'
  ),
  
  # Prepare ZIP code histories
  tar_target(
    zh,
    create_history_variable(
    input = c(input_1,input_2),
    output_file = file.path(outdir, 'zh.parquet'),
    id_cols = c('source_system', 'source_id'),
    variable = 'zip_code',
    clean_function = clean_zip_code
    ),
    format = 'file'
  )
)
#> Establish _targets.R and _targets_r/targets/2nd-vars.R.
```

#### Prepare frequency variables

Predictor variables constructed from the scaled relative frequency of
certain identifiers (e.g. first name) to can be used to account for how
common values may provide less information than less common ones.
Including these types of variables, as discussed in greater detail
below, is an attempt to capture the intuition that “John” = “John” is
probably less predictive than “Unique” = “Unique” for a pair of records.

`freqs` is a series of data frames saved as `.parquet` files that
contain scaled relative frequency by value within the variables (e.g.,
`dob_clean`) specified in the column argument for
[`create_frequency_table`](R/create_frequency_table.R).

``` r
list(
  # Create frequency tables
  tar_target(
    freqs,
    create_frequency_table(
      tables = list(data),
      columns = c('first_name_noblank', 'last_name_noblank', 'dob_clean'),
      output_folder = outdir
    ), format = 'file'
  )
)
#> Establish _targets.R and _targets_r/targets/context-variables.R.
```

### Odds and Ends

#### Types of identifiers

For this workflow, identifiers and other variables come in a few main
flavors:

1.  Primary identifiers are things like source system, source id, name,
    date of birth, social security, and sex/gender. These variables
    generally do not vary over time – or at least, if they do, it
    happens only sporadically. These identifiers (or some similar
    subset) represent the core of a record and are often the basis for
    blocking criteria.
2.  Secondary identifiers are things like address, ZIP code, and phone
    number. These are things that may change with regularity and where
    the temporal characteristics of their appearance may be informative.
3.  Contextual variables are all other things that may be used for
    determining whether record A represents the same entity as record B.
    Some examples may include: household size, term frequency
    adjustment, possibility of being a twin, etc.

#### init_data()

The [`init_data`](R/init_data.R) function loads the data passed via the
`input` argument and uses some hyrule functions to do common cleaning
routines (in a somewhat opinionated manner). In this case, the two input
datasets (`input_1` and `input_2`) are appended together and processed
at the same time because the rest of the process assumes one “data”
file/table with a `source_system` column that differentiates between the
data specified by `input_1` versus `input_2`.

Within the `init_data` function, the following steps occur:

1.  Via [`hyrule::clean_names`](../R/utilities.R), name columns are
    stripped of non-character values and common prefixes/suffixes are
    removed. [`hyrule::remove_spaces`](../R/utilities.R) then removes
    any white space characters.
2.  Certain “junk” names are set to NA.
3.  Date of birth is converted into a date format and restricted to be
    from 1901 to the current year.
4.  Sex is converted into a standard character column ( e.g., ‘Male’ and
    ‘Female’ is converted to ‘M’ and ‘F’). Anything not in those two
    categories is set to NA. Depending on your data availability and/or
    use case, users may want to modify this logic to account for other
    gender data values.
5.  Some SSN cleaning code is available but commented out. This code, if
    applied, converts SSNs to strings of only numerics, removes common
    junk SSNs, and converts things to a standardized 9 digit number (as
    a character column to allow for SSNs beginning with 0).
6.  Rows with too much missing information are dropped from the dataset
7.  Rows with partial data density are filled in using data from other
    rows within the same source id. For example, if rows 1, 2 and 3 all
    derive from the same source id, and rows 2 and 3 have the same
    middle initial value but row 1 is NA, that NA is overwritten by the
    value present in rows 2 and 3. In the event that 2 and 3 disagree,
    then row 1 remains blank for that variable.

While these steps are good starting points for any linkage project, they
should not be considered immutable or complete. Each project will likely
require its own data cleaning routines as data can be messy in nearly
infinite ways.

[Documentation from the splink
package](https://moj-analytical-services.github.io/splink/demos/tutorials/01_Prerequisites.html)
describes some good general principles of data cleaning.

#### `clean_hash`

The final part of the `init_data` function is the creation of a row-wise
hash generated from the cleaned primary identifiers – in this case,
source system, source id, name, dob, and sex. This hash will
subsequently be used as the main unique row identifier and it is used to
nest variations of primary variables within a given source system and
source id combination.

Practically, using the hash (instead of source id) as the low-level
identifier allows for more data available by source id to be leveraged –
even if it conflicts with other records within the same source id. For
example, a given source id may include an entry with the name “Richard”
while a later entry is “Rick”. Using both permutations will facilitate
more candidate pairs for evaluation – reducing the chance of a false
negative (while hopefully not increasing false positives too much).

#### Example “input” data

The table below shows a few rows of the `input_1` target.

| street_number | street_name | source_id | first_name | middle_initial | last_name | sex | date_of_birth | unit_number | X | Y | zip_code | source_system |
|:---|:---|:---|:---|:---|:---|:---|:---|:---|---:|---:|:---|:---|
| NA | NA | 0_9431 | Denise | H | Rogers | NA | 09/28/1986 | NA | NA | NA | NA | System 1 |
| NA | NA | 0_5728 | Shaneka | T | Pullins | Female | 10/15/1977 | NA | NA | NA | NA | System 1 |
| NA | NA | 0_11287 | Laila | M | Garrett | Female | 01/01/1990 | NA | NA | NA | NA | System 1 |
| NA | 1st avenue south | 0_8875 | Tara | S | Lacroix | Female | 05/12/1991 | NA | NA | NA | NA | System 1 |
| NA | 1st avenue south | 0_11866 | Angela | S | Hampton | Female | 10/10/1993 | NA | NA | NA | NA | System 1 |
| NA | 25th st e | 0_11139 | Cassandra | C | Man Of The House | Female | 07/09/1957 | NA | NA | NA | NA | System 1 |

#### Example “cleaned” data

The table below displays a few rows of the `data` target. Recall that
the `data` target is a “cleaned” version of `input_1` and `input_2`.

| source_system | source_id | first_name_noblank | middle_name_noblank | last_name_noblank | sex_clean | dob_clean | clean_hash |
|:---|:---|:---|:---|:---|:---|:---|:---|
| System 1 | 0_100 | EVA | P | MCMILLON | F | 1943-12-08 | 62fe05da67ded8f2bea61c5a2ae1d5b4 |
| System 1 | 0_10000 | ERIC | J | PERES | M | 1972-02-15 | 4de711d441888ae9aecc58c1f3d5b98c |
| System 2 | 0_10001 | AMANDA | NA | PEREZ | F | 1982-07-10 | de38b20096bdec032fe5ac12e7fe3488 |
| System 2 | 0_10002 | AKBERTO | K | PEREZ | M | 2006-08-02 | 656663bf9b773bc1df222a54dde09993 |
| System 2 | 0_10003 | FELICIA | L | LADYOFTHEHOUSE | F | 1971-03-08 | faf768bdf6136246e2909f47ecd5d979 |
| System 1 | 0_10004 | MISS | L | ENNIS | M | 1973-05-31 | 61052dbd3e94d0da0cefb0a0d2f230cf |

## Training Data

### Overview

This section combines cleaned data and variables from the Data
Preparation section with manually labeled (non-)matches to create the
model frame from which the ensemble will be trained (and evaluated)
with.

The minimal structure of the labeled pairs is described in the odds and
ends section.

### Targets

#### `source_id` to `clean_hash`

The labeled pairs for this workflow comes from the `pairs` dataset
within `hyrule` package. However, this dataset specifies records as a
combination of `source_system` and `source_id` rather than as
`clean_hash`. `convert_sid_to_hid` converts `pairs` so that the records
are identified by `clean_hash` and the results are stored (as a link to
a parquet file) in `train_input.`

Note: In most workflows, this step will not be required as the training
data will be natively at the hash level. Instead, most users will want
to populate `train_input` with a set of loadable files (e.g., csv) that
can be registered with `tarchetypes::tar_files_input` and/or some of
function that loads the labeled pairs from storage. As long as
`train_input` ultimately is a path to a parquet file with at least three
columns (`id1`,`id2`, and `pair`) most subsequent targets will work with
little to no modification.

``` r
list(
  # Note: This step is mostly just so the example(s) can run
  tar_target(train_input,
             convert_sid_to_hid(
               pairs = hyrule::train, 
               arrow::read_parquet(data),
               output_file = file.path(outdir, 'training.parquet')
               ), format = 'file'
             )
  
  # usually something like the following is better
  #tarchetypes::tar_files_input(train_input,'FILEPATHS to training data goes here'))
)

#> Establish _targets.R and _targets_r/targets/prep-traindat.R.
```

#### Specifying a formula

Like most modelling/regression/machine learning exercises, a formula
must be specified. Something like `pair ~ varA + varB + varC` where
`pair` refers to the column in the training data indicating whether two
records are a match and `varA`, `varB`, and `varC` are variables that
are likely predictive of the match-iness between two records. The
commentary subsection contains a complete description of the variables.

``` r
f = pair ~ dob_year_exact + dob_mdham + gender_agree +
  first_name_jw + last_name_jw + name_swap_jw +
  complete_name_dl + middle_initial_agree + last_in_last +
  first_name_freq + last_name_freq +
  zip_overlap + exact_location
  

#> Establish _targets.R and _targets_r/globals/formula.R.
```

#### Build training model frame

The [`compile_training_data`](R/compile_training_data.R) function loads
and standardizes labeled pairs and uses the `make_model_frame` function
internally to go from labeled pairs to “training data”. Before saving
the results, some sanity checks are performed to ensure that not too
many of the labeled pairs get dropped due to missing data or some other
set of data gremlins. The results are stored in a parquet file via the
`train_test_data` target. As written, `compile_training_data` assumes
location history, zip history, and various frequency tabulations exist.
Users who do not want to (or cannot) use those bits of information will
have to update the function (and not just the invocation) accordingly.

Note: A detailed description of the
[`make_model_frame`](R/make_model_frame.R) function that combines
`train_input`, `data` and the formula (`f`) to create a model frame is
provided in the commentary section.

``` r
list(tar_target(
  train_test_data,
  compile_training_data(
    input = train_input,
    output_file = file.path(outdir, 'train_and_test.parquet'),
    formula = f,
    data = data,
    loc_history = lh,
    zip_history = zh,
    freq_tab_first_name = freqs[1],
    freq_tab_last_name = freqs[2],
    freq_tab_dob = freqs[3]
  )
)) 
#> Establish _targets.R and _targets_r/targets/training-data.R.
```

### Test/train split

Model frame (`train_test_data`) is split into two datasets: “train” and
“test.” The “train” dataset is what the linkage model(s) will be fit on
while the “test” dataset is held out of the estimation process and only
later used for the computation of fit statistics.

Two targets are specified in this block. The first, `training_hash`
takes a hash of the results from the previous step (stored in
`train_test_data`). This hash, if it changes, triggers the creation of
the `test_train_split` target which uses the `split_tt` function to
split the overall model frame into the aforementioned “train” and “test”
datasets. The two step process (hash and then split) is used so that
spurious changes in the process that creates `test_train_data` don’t get
propagated further. That is, if the model frame meaninfully changes,
downstream targets will be invalidated and recomputed, but a
non-substantive change will not trigger dependencies.

``` r
list(
  tar_target(training_hash, rlang::hash(arrow::read_parquet(train_test_data))),
  tar_target(
    test_train_split,
    split_tt(
      hash = training_hash,
      training_data = train_test_data,
      fraction = .15,
      train_of = file.path(outdir, 'train.parquet'),
      test_of = file.path(outdir, 'test.parquet')
    )              ,
    format = 'file'
  )
)
#> Establish _targets.R and _targets_r/targets/split-test-train.R.
```

### Odds and Ends

#### Training data format

Labeled pairs to be used for training must be organized into a data
frame with three columns: `id1`, `id2`, and `pair`. `id1` and `id2` in
combination refer to the pair of records that was evaluated while the
`pair` column indicates match status (0 for no match, 1 for match).
`id1` and `id2` must be filled with values that reference the low-level
row identifier (e.g., `clean_hash`)

| id1  | id2  | pair |
|:-----|:-----|-----:|
| a123 | z12b |    1 |
| ashd | qaf4 |    0 |

#### Cleaning the labeled pairs

The `compile_training_data` function that is the core of the process
that creates the `train_test_data` target enforces a few consistencies
on the labeled pairs while creating the model frame:

1.  `id1` and `id2` are standardized such that `id1` \< `id2`. Note,
    that inequality operations (e.g. `<`) work on character values.
    Roughly, its based on alphabetical ordering.
2.  Duplicates are dropped
3.  Contradictions (e.g., the first wave of training data says A !=B
    while the second set says A = B) are reconciled by taking the last
    observed value for a given `id1` and`id2` combination
4.  The records implied by the value of `id1` and/or `id2` must still
    exist within `data`. Most of the time, this will be a non-issue, but
    major changes to the data format or data cleaning routines can
    trigger this provision.

#### Example rows from `train_test_data`

``` r
load_target('train_test_data') |>
  head() |>
  knitr::kable()
```

| id1 | id2 | pair | dob_year_exact | dob_mdham | gender_agree | first_name_jw | last_name_jw | name_swap_jw | complete_name_dl | middle_initial_agree | last_in_last | first_name_freq | last_name_freq | zip_overlap | exact_location | missing_zip | missing_ah |
|:---|:---|:---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 00426cbd407157085b731609206c879b | 0654a68cf07ef09cbb21a154ee086783 | 1 | 1 | 0.00 | 1 | 0.4592593 | 1.0000000 | 0.5740741 | 0.6363636 | 1 | 0 | 0.9815 | 0.1786 | 0 | 1 | 0 | 0 |
| 00602eeea0e12ba9cc8417b2cf1fe0c0 | 35d350e69b7189670cf7ded53495ec87 | 0 | 1 | 0.00 | 1 | 0.0000000 | 0.5079365 | 0.5523810 | 0.4615385 | 1 | 0 | 1.0000 | 0.1786 | 0 | 1 | 0 | 0 |
| 006102639d754f0c215b163c31fdd2ec | cd96592ebc7ca2a21cec870eb5ca6c90 | 1 | 1 | 0.00 | 1 | 0.1333333 | 0.4888889 | 1.0000000 | 0.4545455 | 1 | 0 | 0.1574 | 0.2143 | 0 | 1 | 0 | 0 |
| 00d19cd85f59e898f819bc73e469d254 | 638c3cdf9fbc8d2a79bfc0d2688b06f1 | 0 | 0 | 0.50 | 1 | 1.0000000 | 0.5583333 | 0.5444444 | 0.8666667 | 0 | 0 | 0.0648 | 0.0179 | 0 | 0 | 0 | 0 |
| 00e4d82a5b5565baef8c87f55e6036d6 | 57a83a6ce3a48bde4578391f18218e63 | 0 | 0 | 0.75 | 0 | 0.4603175 | 1.0000000 | 1.0000000 | 0.8461538 | 1 | 0 | 0.2222 | 0.1488 | 0 | 0 | 0 | 1 |
| 00e4d82a5b5565baef8c87f55e6036d6 | 9a1691825c996a699b739926eb414840 | 0 | 0 | 0.75 | 0 | 0.5000000 | 1.0000000 | 1.0000000 | 0.8750000 | 1 | 0 | 0.0185 | 0.1488 | 0 | 0 | 0 | 1 |

#### Making the model frame

A model frame is a data frame containing the dependent and independent
variables as informed by the input data and the model formula. The
[`make_model_frame`](R/make_model_frame.R) function is used by the
`compile_training_data` function to create the model frame from the
inputs (cleaned data, derivative datasets like the frequency variables,
formula, labeled pairs, etc.). The actual computation is handled in a
temporary DuckDB database so that expressive (and relatively portable)
sql can be used. DuckDB is also quite clever when working with parquet
files and optimizing queries.

Note: `make_model_frame` function is used to do this (usually nested
within another function). This function takes in a few parquet file
paths (and/or table specified by `DBI::Id()`) and generates a sql query
that when executed in the the correct environment will return a data
frame containing pair level variables.

#### Formula description

For this exercise, the following variables are of interest (and will be
computed – see below):

1.  `dob_year_exact`: binary flag of exact match of year of birth
2.  `dob_mdham`: hamming distance between month and day of birth
3.  `gender_agree`: binary flag of an explicit match on gender
4.  `first_name_jw`: jaro-winkler distance of first names
5.  `last_name_jw`: jaro-winkler distance of last names
6.  `name_swap_jw`: jaro-winkler distance of names with first and last
    swapped
7.  `complete_name_dl`: daimaru-levenstein distance between the full
    names scaled by dividing the character length of the longer name.
    Full name is either first + last or first + middle + last. The
    minimum distance of the two versions is used.
8.  `middle_initial_agree`: binary flag indicating an eplicit match of
    middle initial
9.  `last_in_last`: binary flag indicating whether either records’ whole
    last name is contained in the other one
10. `first_name_freq`: scaled frequency \[0-1\] tabulation of first
    names
11. `last_name_freq`: scaled frequency \[0-1\] tabulation of last names
12. `zip_overlap`: binary flag indicating zip code histories ever
    overlapped (not accounting for time)
13. `exact_location`: binary flag indicating address histories overlap
    within 3 meters (location only – not spatio-temporal).

## Blocking

### Overview

Blocking creates the list of pairs to evaluate for match scores. In this
implementation, a series of sql statements are evaluated and the pairs
that fit one or more of those conditions are cached for evaluation via
the linkage model.

### Targets

#### Blocking rules

Blocking rules are specified as DuckDB friendly SQL statements and refer
to a `l`eft and a `r`ight dataset – a convenience to get the SQL to
work. In this implementation, both `l` and `r` refer to the `data`
target. A brief description of how to interpret the rules is provided in
the Odds and Ends part of this section.

The `make_block_rules` function takes the specified rules, does some
additional SQL processing/writing, and organizes them into a data.frame
(the `qgrid` target). The use of `tar_group_by` (with `qid` as the by
variable) means that the next target that depends on `qgrid` will
execute once per row (analogous to how `tar_map` is used in the Model
Specification section of this document).

``` r
blocking_rules = c(
  'l.last_name_noblank = r.last_name_noblank',
  
  'l.dob_clean = r.dob_clean',
  
  "jaro_winkler_similarity(l.first_name_noblank, r.first_name_noblank) >.7
  and datepart('year', l.dob_clean) = datepart('year', r.dob_clean)"
)

list(tarchetypes::tar_group_by(qgrid, command = make_block_rules(rules = blocking_rules), qid)) 
#> Establish _targets.R and _targets_r/targets/block-1.R.
```

### Computing and compiling pairs for evaluation

Once the blocking rules have been properly formatted and prepared, they
are computed. The `deduplicate` argument in the
[`make_block`](R/blocking.R) function (`blocks` target) governs whether
records from the same source system are “allowed” to be included in the
final set of blocked pairs. Recall that there will be a (sub)target for
every row in `qgrid`.

Once the record pairs that meet at least one blocking rules are
identified (the `blocks` target), those pairs are appended together,
de-duplicated, and split into equal size data frames as the `bids`
target (with `compile_blocks` doing the work). The file paths are then
entered into the pipeline via the `bid_files` target so that the
pipeline behaves. The resulting pairs will be evaluated for matchiness
by the record linkage model and are split into chunks to facilitate
[parallelized computation (if used/set
up)](https://books.ropensci.org/targets/performance.html#parallel-processing).

Note: records from the same source system with the same source id are
automatically excluded from final list of evaluation pairs as they will
be added as fixed links by a later step. Additionally, there are
constraints that prevent transitive repetition (e.g., only one of B - A
or A - B will be kept) of possible pairs.

``` r
list(
  tar_target(
    blocks,
    make_block(
      q = qgrid,
      data = data,
      id_col = 'clean_hash',
      deduplicate = FALSE,
      output_folder = outdir
    ),
    pattern = map(qgrid),
    format = 'file'
  ),
  tar_target(
    bids,
    compile_blocks(
      blocks = blocks,
      output_folder = outdir,
      chk_size = 10000
    ),
    format = 'file'
  ),
  tar_target(bid_files, bids)
)
#> Establish _targets.R and _targets_r/targets/block-2.R.
```

### Odds and ends

#### Writing good blocking rules

The `splink` package [has a great write up on good blocking
rules](https://moj-analytical-services.github.io/splink/demos/tutorials/03_Blocking.html)
and the approach used in this example is heavily influenced by the
splink package.

#### Rules used by this example workflow

Three rules are instantiated below:

1.  Exact match on last name
2.  Exact match on DOB
3.  Fuzzy match on first name and exact match on year

For further evaluation, a pair of records must meet at least one of the
conditions.

## Model Specification

### Overview

This section provides to code to implement the linkage model, which
consists of three parts:

1.  A lasso logistic regression that quickly screens out “obvious”
    matches and non-matches
2.  A diverse series of models that are fit via cross-validation.
3.  An ensemble model fit on the cross-validated results of the models
    generated in step 2 that makes the final match score.

Step 1 is used for computation efficiency as logistic regressions
produce match scores quickly and are good enough to produce ballpark
estimates. Together, steps 2 and 3 are a “stacking” ensemble model
approach where a diverse set of models are combined together to produce
results that are better than a single model.

### Targets

#### Screening model

The screening model (saved to `screener`) is a lasso regression. The
`fit_screening_model` function uses the “train” model frame and some
bounds (defined earlier in the document) to fit and return the screening
model.

``` r
list(
  tar_target(screener, 
  command = fit_screening_model(test_train_split[2], bounds, f))
)
#> Establish _targets.R and _targets_r/targets/screener.R.
```

#### Folds

The stacking framework requires the submodels/child models to be fit
with cross-validation (as a check against over-fitting). As such, the
training dataset is subdivided into 5 approximately equal sized chunks
via the `make_folds` function with results stored in the `tfolds`
target.

``` r
list(tar_target(tfolds, 
                command = make_folds(test_train_split[2],
                                     screener)))
#> Establish _targets.R and _targets_r/targets/submod-folds.R.
```

### Specifying submodel families

For an effective ensemble, a variety of model families are employed.
This example uses tuned versions of support vector machines, random
forests, and xgboost gradient boosted machines. The model types have
been shown to be effective in other uses cases and the underlying
algorithms are sufficiently different from each other that each set of
submodels might be able to optimize for a different subset of tasks.
Other model types (e.g., neural nets, logistic regression, etc.) can be
added to the ensemble if desired.

``` r
svm = parsnip::svm_linear(
  mode = 'classification', 
  engine = 'kernlab', 
  cost = tune())
rf = parsnip::rand_forest(
  mode = 'classification',
  trees = tune(),
  mtry = tune())
xg = parsnip::set_engine(
  parsnip::boost_tree(
    mode = 'classification',
    tree_depth = tune(),
    mtry = tune(), 
    trees = tune(),
    learn_rate = tune()),
  'xgboost', 
  objective = 'binary:logistic')

s_params = tibble::tribble(~NAME, ~MODEL,
                           'svm', quote(svm)
                           ,'rf', quote(rf)
                           ,'xg', quote(xg)
)
s_params$TUNER = 'bayes'
s_params$nm = s_params$NAME

#> Establish _targets.R and _targets_r/globals/submodel_specs.R.
```

#### Tuning and fitting the submodels

The models specified above (and organized into `s_params`) are fit using
[bayesian hyperparameter
tuning](https://tune.tidymodels.org/reference/tune_bayes.html). The
tuning process will create a series of candidate models with different
hyper-parameter settings which are ensembled together in the next
target.

`tar_map` is a short-hand way to create an individual target for each
family of submodels: `submod_svm`, `submod_xg` and `submod_rf`. These
targets will contain the model fit objects and the cross validated
results required for the subsquent ensembling step.

``` r
submods = list(
  tarchetypes::tar_map(
    values = s_params,
    names = 'nm',
    tar_target(submod,
               fit_submodel(
                 train = test_train_split[2],
                 screener = screener,
                 folds = tfolds,
                 m = MODEL,
                 theform = f,
                 apply_screen = apply_screen
                )
              )
  )
)

#> Establish _targets.R and _targets_r/targets/submod-fit.R.
```

### Stacked ensemble model

The sub-models are ensembled together in the `create_stacked_model`
function using lasso regression. Lasso regression is used because it
“automatically” performs variable selection as part of its fitting
process. The final linkage model (screening model + submodels +
ensemble) is stored in the `model` target. The `model` target is then
explicitly saved to disk (`model_path` target). This second step allows
for subsequent steps to load the model lazy way which is useful should
[parallel pipeline execution be implemented (an exercise left to the
reader)](https://books.ropensci.org/targets/performance.html#parallel-processing).

``` r
list(
tarchetypes::tar_combine(
    model,
    submods,
    command = create_stacked_model(
      !!!.x,
      mnames = s_params$nm,
      screener = screener,
      bounds = bounds
    )
  ),
  tar_target(model_path,
  {
    saveRDS(model, file.path(outdir, 'model.rds'))
    file.path(outdir, 'model.rds')
  },
  format = 'file')
)
#> Establish _targets.R and _targets_r/targets/z-ensemble.R.
```

## Predicting Match Scores

### Overview

Match score predictions are generated for all pairs created by the
blocking step. As described above, pairs are first evaluated by the
lasso screening models and those that are within the range specified by
`bounds` (default: $$.01 - .99$$) are further evaluated by the overall
ensemble. All match scores \>.05 are saved (and the ones below the
threshold are discarded to save space).

### Targets

#### Predicted links

Each chunk of pairs (as stored in the `bid_files` series of targets) is
loaded and converted into a model frame (via the `make_model_frame`
function within `predict_links`). Once in model frame format,
predictions from the linkage ensemble (i.e. `model_path`)

``` r
tar_target(preds,
        predict_links(
          pairs = bid_files,
          model = model_path,
          output_folder = outdir,
          data = data,
          loc_history = lh,
          zip_history = zh,
          freq_tab_first_name = freqs[1],
          freq_tab_last_name = freqs[2],
          freq_tab_dob = freqs[3]
        ), 
        pattern = map(bid_files), 
        iteration = 'list', 
        format = 'file')
#> Establish _targets.R and _targets_r/targets/z-predictions.R.
```

#### Fixed (a-priori) links

Depending on the linkage problem, there may be certain pairs of records
that must be considered matches, regardless of the match score. In this
example, records with the same source system and source id, but
different hash ids are automatically considered matches (they are
excluded during the blocking step, but added here). The
[fixed_links](R/fixed_links.R) function adds those records to the
results set as exact matches (i.e. match score of 1) via the `fixed`
target. Note: The result of the `fixed_links` function should match the
column structure of the predicted results.

``` r
tar_target(fixed, 
             fixed_links(
               data = data,
               model_path = model_path,
               fixed_vars = c('source_system', 'source_id'),
               id_col = 'clean_hash',
               output_file = file.path(outdir, 'fixed_links.parquet')
             ), format = 'file'
           )
#> Establish _targets.R and _targets_r/targets/fixed-links.R.
```

### Odds and Ends

## Evaluation and Cutoffs

### Overview

The ensemble produces match scores on a scale of 0 to 1. However,
whether or not two records are a “match” is a binary value and therefore
the scores must be discretized. The targets in this section compute some
cross-validated results that are then combined together to estimate a
cutpoint to maximize accuracy.

### Targets

#### Refit models with cross-validation

To find a good cutoff point, 3 rounds of 5-fold cross validation are
used. For each fold, the entire ensemble is refit via
[`cv_refit`](R/cv_refit.R)(although the hyperparameters are inherited
from the main model) on 4/5ths of the training data, and the cutoff that
optimizes accuracy is computed. `cutoff_df` in combination with
`tar_map` creates a series of targets with a `cv_co` prefix.

``` r
i = 3
cutoff_df = data.table::data.table(iter = 1:i, name = as.character(1:i))

#> Establish _targets.R and _targets_r/globals/a-cutoffs.R.
```

``` r
cv_cutoffs = list(
  tarchetypes::tar_map(
    values = cutoff_df,
    names = 'name',
    tar_target(cv_co,
                 cv_refit(
                   train = test_train_split[2],
                   model_path = model_path,
                   apply_screen = apply_screen,
                   iteration = iter,
                   nfolds = 5,
                   lasso = T 
                 ))
  )
)
#> Establish _targets.R and _targets_r/targets/b-cutoffs.R.
```

#### Identifying the cutpoint and OOS statistics

The cross-validated results are collected and summarized via the
[`identify_cutoff`](R/identify_cutoff.R) function to create the `cutme`
target using the `cv_co` targets (i.e. `cv_cutoffs`) as the primary
input to this step. The results are analyzed to determine a cutpoint
that maximizes accuracy. Out of sample fit statistics are also generated
during this step. The `yardstick` package is used to create the output
metrics.

The resulting `cutme` target contains three items:

1.  A cut-point at the value of maximum accuracy, as computed from the
    cross validation process (the `cv_co` set of products)
2.  Summarized cross-validation results (when `Iteration == 0` in the
    resulting data.frame) and the constituent parts
3.  Out of sample fit metrics.

``` r
list(
tarchetypes::tar_combine(
    cutme,
    cv_cutoffs,
    command = identify_cutoff(
      !!!.x,
      test = test_train_split[1],
      mods = model_path
    )
  ),
  tar_target(cutme_path,
  {
    saveRDS(cutme, file.path(outdir, 'cutme.rds'))
    file.path(outdir, 'cutme.rds')
  },
  format = 'file')
)
#> Establish _targets.R and _targets_r/targets/z-cutoffs.R.
```

### Odds and Ends

#### One vs. many cutpoints

This implementation calculates and uses a single global cutpoint to
determine whether a pair is a match. There is nothing inherently special
about a single cutpoint except its easier to implement. Alternative
implementations/extensions could use multiple situtation cutpoints. For
example, cutpoints based on data densisty or specific variable
combinations may be more effective for certain use cases than a single
threshold.

#### Cutme object

Reviewing the results, especially the out of sample fit metrics will
give a good indication on how the model is performing. An example table
is reproduced below:

| .metric     | .estimator | .estimate | cut_type |
|:------------|:-----------|----------:|:---------|
| accuracy    | binary     | 0.9444444 | Overall  |
| kap         | binary     | 0.8883144 | Overall  |
| f_meas      | binary     | 0.9400000 | Overall  |
| mn_log_loss | binary     | 0.2934539 | Overall  |
| roc_auc     | binary     | 0.9422345 | Overall  |

## From 1:1 links to networks

### Overview

Once a set of links at the hash id level have been identified, they must
be aggregated to the level of interest – in this case, source id. This
is done by organizing all the individual 1:1 links together into a
series of networks and aggregating those networks by source id.

### Targets

#### Compiling 1:1 links into clusters

At this stage, the results consist of of pairs (i.e., 1:1 links) of
records identified at the `clean_hash` level, whereas the goal is an
entity identifier that groups records together at the `source_system` -
`source_id` level (i.e., the atomic unit of the input data systems).

To achieve this, the [`compile_links`](#0) function aggregates the 1:1
links at the `clean_hash` level from the `preds` and `fixed` targets
into clusters/networks at the `source_id`-`source_system` level;
computing some network statistics (density and size) along the way.

Specifically, the function:

1.  Organizes 1:1 links at the `clean_hash` into a series of networks.
    For example, if A links to B, B links to C, and A, B, C have no
    other connections, then the resulting network consists of A, B, and
    C (even though A and C don’t directly match except through B).
2.  The size and density of the networks created in step 1 are computed.
    These initial results (and the cluster ID from \#1) are prefixed
    with `s1_` in the summary output
3.  Networks where size \> `min_N` and density \< `max_density` are
    subdivided based on the clustering algorithm specified by the
    `method` argument. If `recursive` is TRUE, then the subdivision
    continues until some stopping conditions are met (see the
    `clusterer` sub-function in the `compile_links` source code). When
    summary statistics are (re)computed, each level is given an
    incrementing prefix (e.g., `s2_`, `s3_`, etc.).
4.  The new set of (sub)networks are aggregated such that each
    connection is between two `source_id`s instead of `clean_hash`es.
    This may reconnect networks previously separated by \#3 and/or
    overrule below threshold match scores. Usually this occurs when a
    source system - source id contains multiple people but the process
    must assume its all one entity (since source id is the atomic unit
    of reporting).
5.  The (re)organized networks are given unique identifiers and a data
    frame that crosswalks between `clean_hash`, `source_id`, and a
    network identifier (`final_comp_id`). More details are provided in
    the odds and ends section below.

``` r
tar_target(components, 
           compile_links(
             preds,
             fixed,
             data = data, 
             id_col = 'clean_hash',
             cutpoint = cutme$cutpoint,
             output_folder = outdir,
             method = 'leiden',
             min_N = 15,
             max_density = .4,
             recursive = FALSE
           ), format = 'file')
#> Establish _targets.R and _targets_r/targets/compile-components.R.
```

### Odds and Ends

#### Example results from `components`

The first item in the `components` target is the data frame that
converts `clean_hash`es back into `source_system`-`source_id`
combinations and then finally into a final identifier: `final_comp_id`.
A subset of the table is reproduced below. The `final_comp_id`s are not
inherently deterministic between versions of the models/results – so the
same collection of records may have a different id between versions.
`first_level_id` is also provided which is the initial designation of
the network before any subdivision via clustering algorithm (it is also
the part before the first `_` in `final_comp_id`.

``` r
knitr::kable(head(load_target('components', 1)))
```

| clean_hash | final_comp_id | source_system | source_id | first_level_id |
|:---|:---|:---|:---|:---|
| 62fe05da67ded8f2bea61c5a2ae1d5b4 | 1_1 | System 1 | 0_100 | 1 |
| 35ee1cc1471040aa3a7188dc1d9e6fef | 1_3 | System 1 | 0_10029 | 1 |
| 3bccfb77c9dd360d8f4ebdf54b28f595 | 1_3 | System 2 | 0_10029 | 1 |
| 4a787e1dfee5fb2fbac0fd2c60408f39 | 1_4 | System 1 | 0_10030 | 1 |
| ae3f5920fcb592cc84f3c31b1b45f328 | 1_4 | System 2 | 0_10030 | 1 |
| 0f18f44ff69b0710ef001ea0ae69db6b | 1_5 | System 2 | 0_10031 | 1 |

The second item in the output of the `components` target is a summary
file, that reports the density (# of connections/# of total possible
connections) and size (number of nodes within the network). Columns may
be prefixed with `s#`, where the number refers to the level (each
increasing level represents a nested sub-network).

| s1_comp_id | s1_density | s1_size | s2_comp_id | s2_density | s2_size | final_comp_id | final_density | final_size |
|:---|---:|---:|:---|---:|---:|:---|---:|---:|
| 1 | 0 | 5824 | 1_1 | 0.025 | 89 | 1_1 | 0.025 | 89 |
| 1 | 0 | 5824 | 1_3 | 0.030 | 97 | 1_3 | 0.030 | 97 |
| 1 | 0 | 5824 | 1_4 | 0.032 | 69 | 1_4 | 0.032 | 69 |
| 1 | 0 | 5824 | 1_6 | 0.028 | 81 | 1_6 | 0.028 | 81 |
| 1 | 0 | 5824 | 1_9 | 0.038 | 63 | 1_9 | 0.038 | 63 |
| 1 | 0 | 5824 | 1_10 | 0.032 | 105 | 1_10 | 0.032 | 105 |

#### Applying constraints

While this example does not have any network based constraints, certain
uses cases may require the implementation of deterministic rules. For
example, when linking death records to other types of administrative
information, users may want to enforce a rule that only one death record
may within a network of linkages (otherwise, it would imply the “person”
represented by the collection of records died more than once). The
implementation of those sorts of rules is probably best done as part of
the `compile_links` function (or as a new subsequent step).

## Final Pipeline

With all the targets specified, a dependency graph can be generated. It
shows how all the various targets interact with each other.

``` mermaid
graph LR
  style Legend fill:#FFFFFF00,stroke:#000000;
  style Graph fill:#FFFFFF00,stroke:#000000;
  subgraph Legend
    direction LR
    xf1522833a4d242c5([""Up to date""]):::uptodate --- xd03d7c7dd2ddda2b([""Stem""]):::none
    xd03d7c7dd2ddda2b([""Stem""]):::none --- x6f7e04ea3427f824[""Pattern""]:::none
  end
  subgraph Graph
    direction LR
    x5607a26800187e63(["train_test_data"]):::uptodate --> x33ed306cab814ec5(["training_hash"]):::uptodate
    xfee8af392695eaee["input_1"]:::uptodate --> x050528f2087f5ab6(["zh"]):::uptodate
    xe645349da297c10c["input_2"]:::uptodate --> x050528f2087f5ab6(["zh"]):::uptodate
    x9755545176a05140(["data"]):::uptodate --> x84969cda3107a412["blocks"]:::uptodate
    x471eae9527634150(["qgrid"]):::uptodate --> x84969cda3107a412["blocks"]:::uptodate
    xfee8af392695eaee["input_1"]:::uptodate --> x5762811339fd357d(["lh"]):::uptodate
    xe645349da297c10c["input_2"]:::uptodate --> x5762811339fd357d(["lh"]):::uptodate
    x71529b40ed4eb343(["cutme"]):::uptodate --> x7a0414717566c114(["cutme_path"]):::uptodate
    xa65de58f7f180b70(["bid_files"]):::uptodate --> x49a047e761f69b68["preds"]:::uptodate
    x9755545176a05140(["data"]):::uptodate --> x49a047e761f69b68["preds"]:::uptodate
    xa94fb4c0b83ba9a4(["freqs"]):::uptodate --> x49a047e761f69b68["preds"]:::uptodate
    x5762811339fd357d(["lh"]):::uptodate --> x49a047e761f69b68["preds"]:::uptodate
    xaccaa1fc5d24385e(["model_path"]):::uptodate --> x49a047e761f69b68["preds"]:::uptodate
    x050528f2087f5ab6(["zh"]):::uptodate --> x49a047e761f69b68["preds"]:::uptodate
    x9755545176a05140(["data"]):::uptodate --> x5607a26800187e63(["train_test_data"]):::uptodate
    xa94fb4c0b83ba9a4(["freqs"]):::uptodate --> x5607a26800187e63(["train_test_data"]):::uptodate
    x5762811339fd357d(["lh"]):::uptodate --> x5607a26800187e63(["train_test_data"]):::uptodate
    xd7594ee14f5d1b90(["train_input"]):::uptodate --> x5607a26800187e63(["train_test_data"]):::uptodate
    x050528f2087f5ab6(["zh"]):::uptodate --> x5607a26800187e63(["train_test_data"]):::uptodate
    x72b796a43fd7d371(["screener"]):::uptodate --> x66e437f53ff04cfe(["submod_svm"]):::uptodate
    xc3fa1bcc9aba0cdd(["test_train_split"]):::uptodate --> x66e437f53ff04cfe(["submod_svm"]):::uptodate
    x27b62fd0d7134fa9(["tfolds"]):::uptodate --> x66e437f53ff04cfe(["submod_svm"]):::uptodate
    x9043e9d6bef6a839(["model"]):::uptodate --> xaccaa1fc5d24385e(["model_path"]):::uptodate
    x9755545176a05140(["data"]):::uptodate --> xa94fb4c0b83ba9a4(["freqs"]):::uptodate
    xc3fa1bcc9aba0cdd(["test_train_split"]):::uptodate --> x72b796a43fd7d371(["screener"]):::uptodate
    x72b796a43fd7d371(["screener"]):::uptodate --> x9043e9d6bef6a839(["model"]):::uptodate
    x9ac3e268f1e67823(["submod_rf"]):::uptodate --> x9043e9d6bef6a839(["model"]):::uptodate
    x66e437f53ff04cfe(["submod_svm"]):::uptodate --> x9043e9d6bef6a839(["model"]):::uptodate
    x0327a91a36b8b78a(["submod_xg"]):::uptodate --> x9043e9d6bef6a839(["model"]):::uptodate
    x1d906206b5b14e1d(["bids"]):::uptodate --> xa65de58f7f180b70(["bid_files"]):::uptodate
    xaccaa1fc5d24385e(["model_path"]):::uptodate --> xe829d9cc8a3fbb5a(["cv_co_1"]):::uptodate
    xc3fa1bcc9aba0cdd(["test_train_split"]):::uptodate --> xe829d9cc8a3fbb5a(["cv_co_1"]):::uptodate
    xaccaa1fc5d24385e(["model_path"]):::uptodate --> x33ce00852b070d6b(["cv_co_2"]):::uptodate
    xc3fa1bcc9aba0cdd(["test_train_split"]):::uptodate --> x33ce00852b070d6b(["cv_co_2"]):::uptodate
    x9755545176a05140(["data"]):::uptodate --> xd7594ee14f5d1b90(["train_input"]):::uptodate
    x5607a26800187e63(["train_test_data"]):::uptodate --> xc3fa1bcc9aba0cdd(["test_train_split"]):::uptodate
    x33ed306cab814ec5(["training_hash"]):::uptodate --> xc3fa1bcc9aba0cdd(["test_train_split"]):::uptodate
    xaccaa1fc5d24385e(["model_path"]):::uptodate --> x645767fb4734ee1d(["cv_co_3"]):::uptodate
    xc3fa1bcc9aba0cdd(["test_train_split"]):::uptodate --> x645767fb4734ee1d(["cv_co_3"]):::uptodate
    x72b796a43fd7d371(["screener"]):::uptodate --> x0327a91a36b8b78a(["submod_xg"]):::uptodate
    xc3fa1bcc9aba0cdd(["test_train_split"]):::uptodate --> x0327a91a36b8b78a(["submod_xg"]):::uptodate
    x27b62fd0d7134fa9(["tfolds"]):::uptodate --> x0327a91a36b8b78a(["submod_xg"]):::uptodate
    xfee8af392695eaee["input_1"]:::uptodate --> x9755545176a05140(["data"]):::uptodate
    xe645349da297c10c["input_2"]:::uptodate --> x9755545176a05140(["data"]):::uptodate
    x72b796a43fd7d371(["screener"]):::uptodate --> x9ac3e268f1e67823(["submod_rf"]):::uptodate
    xc3fa1bcc9aba0cdd(["test_train_split"]):::uptodate --> x9ac3e268f1e67823(["submod_rf"]):::uptodate
    x27b62fd0d7134fa9(["tfolds"]):::uptodate --> x9ac3e268f1e67823(["submod_rf"]):::uptodate
    x71529b40ed4eb343(["cutme"]):::uptodate --> x9662f7590fc15a9b(["components"]):::uptodate
    x9755545176a05140(["data"]):::uptodate --> x9662f7590fc15a9b(["components"]):::uptodate
    x125711b5fae4f13e(["fixed"]):::uptodate --> x9662f7590fc15a9b(["components"]):::uptodate
    x49a047e761f69b68["preds"]:::uptodate --> x9662f7590fc15a9b(["components"]):::uptodate
    x84969cda3107a412["blocks"]:::uptodate --> x1d906206b5b14e1d(["bids"]):::uptodate
    x9755545176a05140(["data"]):::uptodate --> x125711b5fae4f13e(["fixed"]):::uptodate
    xaccaa1fc5d24385e(["model_path"]):::uptodate --> x125711b5fae4f13e(["fixed"]):::uptodate
    xe829d9cc8a3fbb5a(["cv_co_1"]):::uptodate --> x71529b40ed4eb343(["cutme"]):::uptodate
    x33ce00852b070d6b(["cv_co_2"]):::uptodate --> x71529b40ed4eb343(["cutme"]):::uptodate
    x645767fb4734ee1d(["cv_co_3"]):::uptodate --> x71529b40ed4eb343(["cutme"]):::uptodate
    xaccaa1fc5d24385e(["model_path"]):::uptodate --> x71529b40ed4eb343(["cutme"]):::uptodate
    xc3fa1bcc9aba0cdd(["test_train_split"]):::uptodate --> x71529b40ed4eb343(["cutme"]):::uptodate
    xa5a0078967d8482b(["input_1_files"]):::uptodate --> xfee8af392695eaee["input_1"]:::uptodate
    x7f2c265f651235ec(["input_2_files"]):::uptodate --> xe645349da297c10c["input_2"]:::uptodate
    x72b796a43fd7d371(["screener"]):::uptodate --> x27b62fd0d7134fa9(["tfolds"]):::uptodate
    xc3fa1bcc9aba0cdd(["test_train_split"]):::uptodate --> x27b62fd0d7134fa9(["tfolds"]):::uptodate
  end
  classDef uptodate stroke:#000000,color:#ffffff,fill:#354823;
  classDef none stroke:#000000,color:#000000,fill:#94a4ac;
  linkStyle 0 stroke-width:0px;
  linkStyle 1 stroke-width:0px;
```

# Odds and ends

## Final output

The first object in the `components` output associates various source
ids with a `final_comp_id` which is the entity identifier (i.e., if
`final_comp_id` is the same for two records, then they can be considered
to represent the same person/entity).

## Glossary

1.  Source system (`source_system`): A dataset

2.  Source Id (`source_id`): The unique record identifier within a
    source system. Within a source system, all records with the same
    source id are considered a single entity.

3.  hash id (`clean_hash`): A custom generated unique identifier that is
    nested within a source system and source id that specifies a
    specific set of identifiers. For example, Dan will result in a
    different hash id than Daniel, even with all the other inputs held
    the same. The hash id serves as the base unit of analysis for the
    matching (that is, the matches are between hash ids). Things are
    later aggregated to the source system - source id level

### Running this pipeline

To use/run this pipeline, users must:

1.  Install the relevant packages:

    Packages to setup the pipeline -

    ``` r
    install.packages(c('remotes', 'tarchetypes', 'targets', 'glue', 'sf', 'data.table'))

    remotes::install_github('PHSKC-APDE/hyrule')
    ```

    Packages required for the pipeline to run -

    ``` r
    install.packages(c('data.table', 'stringr', 'arrow', 'duckdb', 'DBI', 'glue', 'stringr', 'sf', 'tidymodels', 'workflows', 'stacks', 'dplyr', 'ranger', 'xgboost', 'rlang', 'igraph'))
    ```

2.  Render `_targets.qmd` (this file). This will convert the
    target-markdown cells in this document into .R files (stored in
    [`_targets_r`](_targets_r/)). Intrepid users can use the rendered
    results (specifically the `_targets.R` file and the files stored in
    `_targets_r`) if they’d rather no longer bother with the .qmd
    approach.

3.  Run `tar_make()` to execute the pipeline.

4.  (Optional) Re-render `_targets.qmd` to populate the few sections
    that pull data from the pipeline
