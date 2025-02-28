# ML Record Linkage Pipeline


- [Overview](#overview)
  - [About this document](#about-this-document)
- [Set up](#set-up)
  - [Pipeline setup](#pipeline-setup)
  - [Packages and functions](#packages-and-functions)
- [ML Record Linkage Pipeline](#ml-record-linkage-pipeline)
  - [Prepare Data](#prepare-data)
  - [Training data](#training-data)
  - [Model specification](#model-specification)
  - [Blocking](#blocking)
  - [Predicting match scores](#predicting-match-scores)
  - [Evaluation and cutoffs](#evaluation-and-cutoffs)
  - [From 1:1 links to networks](#from-11-links-to-networks)
- [Final Pipeline](#final-pipeline)
- [Odds and ends](#odds-and-ends)
  - [Glossary](#glossary)

Packages to setup the pipeline

``` r
install.packages(c('remotes', 'tarchetypes', 'targets', 'glue', 'sf', 'data.table'))
```

Packages required for the pipeline

``` r
install.packages(c('data.table', 'stringr', 'arrow', 'duckdb', 'DBI', 'glue', 'stringr', 'sf', 'tidymodels', 'workflows', 'stacks', 'dplyr', 'ranger', 'xgboost', 'rlang', 'igraph'))
```

# Overview

## About this document

This document is an example implementation of machine learning record
linkage within a [targets
workflow](https://books.ropensci.org/targets/). While it is designed to
be a runnable pipeline, the primary goal of this example is to provide
ideas and show options that analysts can adapt to their own projects.

The funding and inspiration for this document derives from the NO HARMS
grant conducted at Public Health - Seattle & King County and funded by
the CDC. The pipeline and methods described below are heavily influenced
by the NO HARMS pipeline, but are intended to be more generalized and
flexible.

### Useful Concepts

Users should familiarize themselves with the following R-packages and/or
methodological concepts:

1.  [targets](https://books.ropensci.org/targets/) and
    [`tarchetypes`](https://docs.ropensci.org/tarchetypes/): These
    R-packages are used to orchestrate the linkage pipeline. A targets
    pipeline is a directed acyclic graph that governs how inputs,
    intermediate steps, and outputs all interact/flow into each other.
    The pipeline can identify changes in the code and inputs for a
    particular step and propagate the need to update to downstream
    steps. Via some partner packages
    (e.g. [`crew`](https://github.com/wlandau/crew)), a targets pipeline
    can be computed in parallel fairly easily as the full dependency
    chain is pre-specified.
2.  [`data.table`](https://github.com/Rdatatable/data.table),
    [duckdb](https://github.com/duckdb/duckdb-r) (R-package, overall
    reference): Most of the data manipulation within this pipeline is
    either conducted via the `data.table` R-package or `duckdb` dialect
    sql (via the `DBI`) package. The
    [`glue`](https://glue.tidyverse.org/) package is often used to craft
    sql statements.
3.  `.parquet` files: The [`arrow`](https://arrow.apache.org/docs/r/)
    package (along with `duckdb`) provides read/write routines for
    `.parquet` files. `.parquet` files are used because they are
    reasonably efficient storage wise and allow for partial read/writes.
    `DuckDB` in particular has effective routines for
    reading/manipulating `.parquet` files.
4.  [`tidymodels`](https://www.tidymodels.org/): This example (and the
    `hyrule` package) relies on the `tidymodels` suite of packages for
    model specification, fitting, and evaluation. The main packages used
    are [`parnsip`](https://parsnip.tidymodels.org/),
    [`workflows`](https://workflows.tidymodels.org/),
    [`tune`](https://tune.tidymodels.org/),
    [`stacks`](https://stacks.tidymodels.org/), and
    [`yardstick`](https://yardstick.tidymodels.org/).
5.  *machine learning*: This example uses
    [`xgboost`](https://xgboost.readthedocs.io/en/stable/R-package/xgboostPresentation.html)
    gradient boosted machines,
    [`ranger`](https://github.com/imbs-hl/ranger) random forests, and
    [`kernlab`](https://cran.r-project.org/web/packages/kernlab/kernlab.pdf)
    support vector machines.
6.  [*stacking/ensemble
    learning*](https://en.wikipedia.org/wiki/Ensemble_learning): This
    method uses stacked generalization (aka stacking) for model
    ensembling. The [`stacks`](https://stacks.tidymodels.org/) package
    provides the implementation.
7.  [`igraph`](https://en.wikipedia.org/wiki/Ensemble_learning): A
    package for working with networks/graphs. Collections of 1:1 matches
    may aggregate into full-fledged networks and can be analyzed as
    such.
8.  [*string distance
    metrics*](https://journal.r-project.org/archive/2014-1/loo.pdf):
    Many of the character variable based comparisons (e.g. name
    similarity) are string distance metrics. More details can be found
    here. Implementation is done via
    [`DuckDB`](https://duckdb.org/docs/sql/functions/char.html)
    routines.

# Set up

## Pipeline setup

These packages are required to set up the pipeline.

``` r
library(targets)
# library('hyrule')
library(tarchetypes)
library(glue)
# library('sf')
library('data.table')
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

## Prepare Data

There are two main flavors of record linkage supported by this pipeline:

1.  Link only: Data sets are assumed to have no duplicates, and
    therefore within dataset linkages are computed. This is specified
    during the blocking step, and in this example, largely depends on a
    `source_system` variable.
2.  De-duplicate (and link): One or more datasets are appended together
    and within and between dataset linkages are computed.

Determining on what type of approach to take occurs during the blocking
step (which determines the pairs to be evaluated).

### An aside on types of identifiers

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

### Primary Identifiers

In the code below, the `tarchetypes::tar_files_input` ingests the file
path of the supplied data files and makes a checkpoint on the file –
beginning the dependency chain

The [`init_data`](R/init_data.R) function loads the data passed via the
`input` argument and uses some hyrule functions to do common cleaning
routines (in a somewhat opinionated manner). In this case, the two input
datasets (`input_1` and `input_2`) are appended together and processed
at the same time because the rest of the process assumes one “data”
file/table with a `source_system` column that differentiates between the
data specified by `input_1` versus `input_2`.

``` r
list(
  # file paths to data
  tarchetypes::tar_files_input(input_1, '../data-raw/fake_one.parquet'),
  tarchetypes::tar_files_input(input_2, '../data-raw/fake_two.parquet'),
  
  # Load, clean, and save datasets
  tar_target(data, init_data(c(input_1, input_2), file.path(outdir, 'data.parquet')), format = 'file')


)
#> Establish _targets.R and _targets_r/targets/primary-identifiers.R.
```

Within the `init_data` function, the following steps occur:

1.  Via [`hyrule::clean_names`](../R/utilities.R), name columns are
    stripped of non-character values and common prefixes/suffixes are
    removed. [`hyrule::remove_spaces`](../R/utilities.R) then removes
    any white space characters.
2.  Date of birth is converted into a date format and restricted to be
    from 1901 to the current year.
3.  Sex is converted into a standard character column ( e.g. ‘Male’ and
    ‘Female’ is converted to ‘M’ and ‘F’). Anything not in those two
    categories is set to NA.
4.  Some SSN cleaning code is available as comments. This code, if
    applied, converts SSNs to strings of only numerics, removes common
    junk SSNs, and converts things to a standardized 9 digit number (as
    a character column to allow for SSNs beginning with 0).
5.  Rows with too much missing information are dropped from the dataset
6.  Rows with partial data density are filled in using data from other
    rows within the same source id. For example, if rows 1, 2 and 3 all
    derive from the same source id, and rows 2 and 3 have the same
    middle initial value but row 1 is NA, that NA is overwritten by the
    value present in rows 2 and 3. In the event that 2 and 3 disagree,
    then row 1 remains blank for that variable.

While these steps are good starting points for any linkage project, they
should not be considered immutable or complete. Each project will likely
require its own data cleaning routines as data can be messy in nearly
infinite ways.

#### Row hashes

The final main step fo the `init_data` function is the creation of a
row-wise hash is generated based off the cleaned primary identifiers –
in this case, source system, source id, name, dob, and sex. This hash
will subsequently be used as the main unique row identifier and it is
used to nest variations of primary variables within a given source
system and source id combination.

Practically, using the hash (instead of source id) as the low-level
identifier instead of source id allows for more data available by source
id to be leveraged to improve the linkage process. For example, if
source ID sometimes has Richard as the first name and sometimes as Rick,
then both permutations can be used for blocking and evaluating possible
links to identify more matches.

Handling the data in this way (row based) instead of aggregating thing
into list-columns and using set operations also improves computational
efficiency – especially for blocking.

### Example input data

| street_number | street_name | source_id | first_name | middle_initial | last_name | sex | date_of_birth | unit_number | X | Y | zip_code | source_system |
|:---|:---|:---|:---|:---|:---|:---|:---|:---|---:|---:|:---|:---|
| NA | NA | 0_9431 | Denise | H | Rogers | NA | 09/28/1986 | NA | NA | NA | NA | System 1 |
| NA | NA | 0_5728 | Shaneka | T | Pullins | Female | 10/15/1977 | NA | NA | NA | NA | System 1 |
| NA | NA | 0_11287 | Laila | M | Garrett | Female | 01/01/1990 | NA | NA | NA | NA | System 1 |
| NA | 1st avenue south | 0_8875 | Tara | S | Lacroix | Female | 05/12/1991 | NA | NA | NA | NA | System 1 |
| NA | 1st avenue south | 0_11866 | Angela | S | Hampton | Female | 10/10/1993 | NA | NA | NA | NA | System 1 |
| NA | 25th st e | 0_11139 | Cassandra | C | Man Of The House | Female | 07/09/1957 | NA | NA | NA | NA | System 1 |

### Example “cleaned” data

| source_system | source_id | first_name_noblank | middle_name_noblank | last_name_noblank | sex_clean | dob_clean | clean_hash |
|:---|:---|:---|:---|:---|:---|:---|:---|
| System 1 | 0_100 | EVA | P | MCMILLON | F | 1943-12-08 | 62fe05da67ded8f2bea61c5a2ae1d5b4 |
| System 1 | 0_10000 | ERIC | J | PERES | M | 1972-02-15 | 4de711d441888ae9aecc58c1f3d5b98c |
| System 2 | 0_10001 | AMANDA | NA | PEREZ | F | 1982-07-10 | de38b20096bdec032fe5ac12e7fe3488 |
| System 2 | 0_10002 | AKBERTO | K | PEREZ | M | 2006-08-02 | 656663bf9b773bc1df222a54dde09993 |
| System 2 | 0_10003 | FELICIA | L | LADYOFTHEHOUSE | F | 1971-03-08 | faf768bdf6136246e2909f47ecd5d979 |
| System 1 | 0_10004 | MISS | L | ENNIS | M | 1973-05-31 | 61052dbd3e94d0da0cefb0a0d2f230cf |

### Secondary identifiers

Secondary identifiers are primarily variables not included within the id
hash and/or ones that will not be used for blocking. These variables are
also more likely to change over time and/or have higher levels of
missingness. Common examples include
[addresses](R/create_history_variable.R) and [ZIP
code](R/create_history_variable.R). Unlike the primary identifiers,
these data are treated as list columns/sets/histories (e.g. does the
address history for record A overlap with that of record B) and are kept
at the source id level (at least in this document).

Note: The sample data used in this document only has one (or zero)
addresses associated with each source id. However, the “history”
approach to data transformation and analysis is used for demonstration
purposes. The code (or at least the method) is scalable to longer
histories and a one entry history is legitimate in any case.

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

### Contextual variables

Frequency variables are useful to include within the modelling framework
as they can adjust/downweight common names. For example, “John Smith”
and “John Smith” likely is less informative than “Unique Name” and
“Unique Name” because John Smith is more common. Using the
[`create_frequency_table`](R/create_frequency_table.R) function, any
variable can be the source of a frequency variable. For a given input
value (e.g. John), the resulting relative frequency value computed and
then scaled between 0 and 1.

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

### Other data cleaning ideas

1.  Common “junk” names (e.g. John Doe) should be removed. Reviewing the
    names with high frequency is generally a good way to find “junk”
    names.
2.  Limit date of birth values to reasonable limits (e.g. 1900 - current
    year).

## Training data

### Creating (new) training data

Unlike probabilistic methods (e.g. splink), machine learning methods
require training data to operate (although probabilistic methods
probably require manually labeled pairs to be useful anyway). When
beginning a new project, a few options are available:

1.  Borrow from a previously fit ML model
2.  Borrow from a probabilistic model
3.  Use some deterministic rules to generate matches/non-matches
4.  Randomly sampled manually labeled pairs

Regardless of the approach, the goal is to have enough pairs to fit a
draft model. The draft model can then be used to generate match scores
that can inform the selection of additional pairs for manual labeling.

### Prepping training data for this workflow

The `pairs` dataset within `hyrule` is at the source id rather than the
hash level. This next target/block of code converts from source id to
hash id. Generally, this step will not be required as the training data
will be natively at the hash level. Additionally, most users will have
their training pairs stored in a database and/or as a set of loadable
files (e.g. csv) that can be read in with
`tarchetypes::tar_files_input`.

Minimally, labeled pairs (e.g. training data) should be stored in the
following format:

| id1 | id2 | pair |
|----:|----:|-----:|
|   1 |   3 |    0 |
|   2 |   4 |    1 |

`id1`, `id2`, and `pair` are all required columns. `pair` must be a
numeric column with the values of 0 (no-match), 1 (match), or -1
(unknown). Additional columns can be added to the dataset, but they will
be unused by the current implementation.

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

### Specifying a formula

Like most modelling/regression/machine learning exercises, a formula
must be specified. Something like `pair ~ varA + varB + varC` where
`pair` refers to the column in the training data indicating whether two
records are a match and `varA`, `varB`, and `varC` are variables that
are likely predictive of the match-iness between two records. For this
exercise, the following variables are of interest (and will be computed
– see below):

1.  `dob_year_exact`: exact match of year of birth
2.  `dob_mdham`: hamming distance between month and day of birth
3.  `gender_agree`: gender explicitly matches
4.  `first_name_jw`: jaro-winkler distance of first names
5.  `last_name_jw`: jaro-winkler distance of last names
6.  `name_swap_jw`: jaro-winkler distance of names with first and last
    swapped
7.  `complete_name_dl`: daimaru-levenstein distance between the full
    names. Full name is either first + last or first + middle + last.
    The minimum distance of the two versions is used.
8.  `middle_initial_agree`: Explicit match of middle initial
9.  `last_in_last`: where either records’ whole last name is contained
    in the other one
10. `first_name_freq`: Scaled frequency tabulation of first names
11. `last_name_freq`: Scaled frequency tabulation of last names
12. `zip_overlap`: Binary flag indicating zip code histories ever
    overlapped (not accounting for time)
13. `exact_location`: binary flag indicating address histories overlap
    within 3 meters (location only – not spatio-temporal).

``` r
f = pair ~ dob_year_exact + dob_mdham + gender_agree +
  first_name_jw + last_name_jw + name_swap_jw +
  complete_name_dl + middle_initial_agree + last_in_last +
  first_name_freq + last_name_freq +
  zip_overlap + exact_location
  

#> Establish _targets.R and _targets_r/globals/formula.R.
```

### Creating the variables

To create the variables specified by the formula, this workflow uses a
function called [`make_model_frame`](R/make_model_frame.R).
`make_model_frame` takes a number of inputs (datasets, the training
pairs, frequency tables, etc.) and computes the required columns from
the data. The actual computation is handled in a temporary DuckDB
database so that expressive (and relatively portable) sql can be used.
DuckDB is also quite clever when working with parquet files and
optimizing queries.

### Compile training data

#### Load and prepare training data

At this stage, the `train_input` step is a basic data.frame (technically
a file path to a data.frame) with three columns: `id1`, `id2`, and
`pair`. As described above, the first two columns specify pairs of
records while the `pair` column is a binary flag indicating whether the
two (hash) ids are a match (1) or not (0). To be usable for model
fitting, the training pairs must be screened for duplicates,
contradictions (e.g. the first wave of training data says A !=B while
the second set says A = B) must be reconciled, and the ids must be
checked for validity (e.g. the input data might have changed the hash
for a particular row so that a given pair in the training data doesn’t
have a counterpart in the main data).

#### Computing prediction variables

Once the training pairs are prepared, the predictor variables must be
created. In this workflow, the `make_model_frame` function is used to do
this (usually nested within another function). This function takes in a
few parquet file paths (and/or table specified by `DBI::Id()`) and
generates a sql query that when executed in the the correct environment
will return a data frame containing pair level variables.

For preparing the training data,
[`compile_training_data`](R/compile_training_data.R) loads and
standardizes labeled pairs, uses `make_model_frame` (with the previously
created targets as inputs) to go from labeled pairs to “training data.”
Before saving the results, some sanity checks are performed to ensure
that too many of the labeled pairs get dropped due to missing data or
some other set of data gremlins.

``` r

list(
  tar_target(
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
    )
  )

#> Establish _targets.R and _targets_r/targets/training-data.R.
```

### Test/train split

The labeled data is split into two chunks datasets “train” and “test.”
The training dataset will inform the models that will be fit on the
later sections while the “test” dataset is held out and will be used to
generate out of sample fit metrics.

``` r
list(
  tar_target(
    training_hash,
    rlang::hash(arrow::read_parquet(train_test_data))
  ),
  
  tar_target(test_train_split, 
             split_tt(hash = training_hash, 
                      training_data = train_test_data, 
                      fraction = .15, 
                      train_of = file.path(outdir, 'train.parquet'), 
                      test_of = file.path(outdir, 'test.parquet'))
             , format = 'file')
  
)
#> Establish _targets.R and _targets_r/targets/split-test-train.R.
```

## Model specification

The linkage model consists of three parts:

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

### Screening model

``` r
list(
  tar_target(screener, 
  command = fit_screening_model(test_train_split[2], bounds, f))
)
#> Establish _targets.R and _targets_r/targets/screener.R.
```

### Submodels

For an effective ensemble, a variety of model families are employed.
This example uses tuned versions of support vector machines, random
forests, and xgboost gradient boosted machines.

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

The stacking framework requires the submodels/child models to be fit
with cross-validation (as a check against over-fitting). As such, the
training dataset is subdivided into 5 approximately equal sized chunks.

``` r
list(
  tar_target(tfolds, command = make_folds(test_train_split[2], screener))
)
#> Establish _targets.R and _targets_r/targets/submod-folds.R.
```

The models undergo [bayesian hyperparameter
tuning](https://tune.tidymodels.org/reference/tune_bayes.html) and the
best performing models are considered for inclusion in the ensemble.

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

The submodels are ensembled together via a lasso regression. The output
model object is also saved.

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

## Blocking

Blocking creates the list of pairs to evaluate for match scores. In this
implementation, a series of sql statements are evaluated and the pairs
that fit one or more of those conditions are cached for evaluation via
the linkage model.

### Specifying blocking rules with SQL

Blocking rules are specified as DuckDB friendly SQL statements and refer
to a `l` and a `r` dataset. In this implementation, both `l` and `r` are
the `data` target. The `splink` package[has a great write up on good
blocking
rules](https://moj-analytical-services.github.io/splink/demos/tutorials/03_Blocking.html)
and the approach used in this example is heavily influenced by the
splink package.

Three rules are instantiated below:

1.  Exact match on last name
2.  Exact match on DOB
3.  Fuzzy match on first name and exact match on year

For further evaluation, a pair of records must meet at least one of the
conditions.

``` r
blocking_rules = c(
  'l.last_name_noblank = r.last_name_noblank',
  'l.dob_clean = r.dob_clean',
  "jaro_winkler_similarity(l.first_name_noblank, r.first_name_noblank) >.7
   and datepart('year', l.dob_clean) = datepart('year', r.dob_clean)"
  )

list(
  tarchetypes::tar_group_by(qgrid, 
                            command = make_block_rules(rules = blocking_rules),
                            qid)
)

#> Establish _targets.R and _targets_r/targets/block-1.R.
```

### Computing and compiling pairs for evaluation

Once the blocking rules have been properly formatted and prepared, they
are then computed. The `deduplicate` argument in the
[`make_block`](R/blocking.R) function (`blocks` target) governs whether
records from the same source system are “allowed” to be included in the
final set of blocked pairs. Records from the same source system with the
same source id are automatically excluded from final list of evaluation
pairs as they will be added as fixed links by a later step.

``` r
list(
tar_target(blocks, make_block(q = qgrid, 
                              data = data, 
                              id_col = 'clean_hash',
                              deduplicate = FALSE,
                              output_folder = outdir),
           pattern = map(qgrid),
           format = 'file'),

tar_target(bids, compile_blocks(blocks = blocks, 
                                output_folder = outdir, 
                                chk_size = 10000), format = 'file'),
tar_target(bid_files, bids)
)
#> Establish _targets.R and _targets_r/targets/block-2.R.
```

At the end of the blocking process, the `bid_files` target links to a
series of data.frames (saved as parquet files) that consist of the pairs
that be assessed for match probability.

## Predicting match scores

### Using the ensemble

For all blocked pairs, a match score is generated and those where the
match probability is \>.05 are saved. As described above, pairs are
first evaluated by the lasso screening models and those that are within
the range specified by `bounds` (default: $$.01 - .99$$) are further
evaluated by the overall ensemble.

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

### Fixed links

Depending on the linkage problem, there may be certain pairs of records
that must be considered matches, regardless of the match score. In this
example, records with the same source system and source id, but
different hash ids are automatically considered matches (they are
ignored during the blocking step, but added here). The
[fixed_links](R/fixed_links.R) function adds those records to the
results set as exact matches (i.e. match score of 1).

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

## Evaluation and cutoffs

The ensemble produces match scores on a scale of 0 to 1. However,
whether or not two records are a “match” is a binary value and therefore
the scores must be discretized. To find a good cutoff point, 3 rounds of
5-fold cross validation are used. For each fold, the entire ensemble is
refit via [`cv_refit`](R/cv_refit.R)(although the hyperparameters are
inherited from the main model) on 4/5ths of the training data, and the
cutoff that optimizes accuracy is computed.

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

### Identifying the cutpoint and OOS statistics

The cross-validated results are collected and summarized via the
[`identify_cutoff`](R/identify_cutoff.R) function during the `cutme`
target. The results are analyzed to determine a cutpoint that maximizes
accuracy. Out of sample fit statistics are also generated during this
step.

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

The resulting `cutme` target contains three items:

1.  A cut-point at the value of maximum accuracy, as computed from the
    cross validation process (the `cv_co` set of products)
2.  Summarized cross-validation results (when `Iteration == 0` in the
    resulting data.frame) and the constituent parts
3.  Out of sample fit metrics.

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

Once a set of links at the hash id level have been identified, they must
be aggregated to the level of interest – in this case, source id. This
is done by organizing all the individual 1:1 links together into a
series of networks and aggregating those networks by source id. The
[`compile_links`](R/compile_links.R) function does this two step
aggregation process and computes some metrics at each scale (e.g. the
hash id level and then the source id level).

``` r
tar_target(components, 
           compile_links(
             preds,
             fixed,
             data = data, 
             id_col = 'clean_hash',
             cutpoint = cutme$cutpoint,
             output_folder = outdir
           ), format = 'file')
#> Establish _targets.R and _targets_r/targets/compile-components.R.
```

The second item in the output of the `components` target is a summary
file, that reports the density (# of connects/# of total possible
connections) and size (number of nodes within the cluster). Columns may
be prefixed with `s#`, where the number refers to the level (each
increasing level represents a nested subcluster).

| s1_comp_id | s1_density | s1_size | s2_comp_id | s2_density | s2_size | final_comp_id | final_density | final_size |
|:---|---:|---:|:---|---:|---:|:---|---:|---:|
| 1 | 0 | 5914 | 1_1 | 0.031 | 94 | 1_1 | 0.031 | 94 |
| 1 | 0 | 5914 | 1_3 | 0.032 | 95 | 1_3 | 0.032 | 95 |
| 1 | 0 | 5914 | 1_4 | 0.035 | 69 | 1_4 | 0.035 | 69 |
| 1 | 0 | 5914 | 1_6 | 0.030 | 75 | 1_6 | 0.030 | 75 |
| 1 | 0 | 5914 | 1_9 | 0.037 | 62 | 1_9 | 0.037 | 62 |
| 1 | 0 | 5914 | 1_10 | 0.037 | 105 | 1_10 | 0.037 | 105 |

### Applying constraints

While this example does not have any network based constraints, certain
uses cases may require the implementation of deterministic rules. For
example, when linking death records to other types of administrative
information, users may want to enforce a rule that only one death record
may within a network/cluster of linkages (otherwise, it would imply the
“person” represented by the collection of records died more than once).
The implementation of those sorts of rules is probably best done as part
of the `compile_links` function (or as a new subsequent step).

### Identity Table

The first part of results stored in `components` target is a file path
to a parquet file containing the final results: a data frame that
crosswalks between `clean_hash`, `source_id` & `source_system`, and
`final_comp_id`. This latter variable is final entity identity. All
source ids with the same `final_comp_id` can be considered as
representing the same “person” (or equivalent).

As currently implemented, the `final_comp_id`s are not persistent
between model versions.

| clean_hash | final_comp_id | source_system | source_id | first_level_id |
|:---|:---|:---|:---|:---|
| 62fe05da67ded8f2bea61c5a2ae1d5b4 | 1_1 | System 1 | 0_100 | 1 |
| 35ee1cc1471040aa3a7188dc1d9e6fef | 1_3 | System 1 | 0_10029 | 1 |
| 3bccfb77c9dd360d8f4ebdf54b28f595 | 1_3 | System 2 | 0_10029 | 1 |
| 4a787e1dfee5fb2fbac0fd2c60408f39 | 1_4 | System 1 | 0_10030 | 1 |
| ae3f5920fcb592cc84f3c31b1b45f328 | 1_4 | System 2 | 0_10030 | 1 |
| 0f18f44ff69b0710ef001ea0ae69db6b | 1_5 | System 2 | 0_10031 | 1 |

# Final Pipeline

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
