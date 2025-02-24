# ML Record Linkage


- [Overview](#overview)
  - [About this document](#about-this-document)
    - [Useful Concepts](#useful-concepts)
    - [Machines vs. probabilistic
      methods](#machines-vs-probabilistic-methods)
    - [Code Location](#code-location)
    - [Glossary](#glossary)
- [Workflow Summary](#workflow-summary)
- [Set up](#set-up)
  - [Pipeline setup](#pipeline-setup)
  - [Packages and functions](#packages-and-functions)
- [ML Record Linkage Pipeline](#ml-record-linkage-pipeline)
  - [Prepare Data](#prepare-data)
    - [An aside on types of
      identifiers](#an-aside-on-types-of-identifiers)
    - [Primary Identifiers](#primary-identifiers)
    - [Secondary identifiers](#secondary-identifiers)
    - [Contextual variables](#contextual-variables)
    - [Other data cleaning ideas](#other-data-cleaning-ideas)
  - [Training data](#training-data)
    - [Creating (new) training data](#creating-new-training-data)
    - [Prepping training data for this
      workflow](#prepping-training-data-for-this-workflow)
    - [Specifying a formula](#specifying-a-formula)
    - [Creating the variables](#creating-the-variables)
    - [Compile training data](#compile-training-data)
    - [Test/train split](#testtrain-split)
  - [Model specification](#model-specification)
    - [Screening model](#screening-model)
    - [Submodels](#submodels)
    - [Stacked ensemble model](#stacked-ensemble-model)
  - [Blocking](#blocking)
    - [Specifying blocking rules with
      SQL](#specifying-blocking-rules-with-sql)
    - [Computing and compiling pairs for
      evaluation](#computing-and-compiling-pairs-for-evaluation)
  - [Predicting match scores](#predicting-match-scores)
    - [Using the ensemble](#using-the-ensemble)
    - [Fixed links](#fixed-links)
  - [Evaluation and cutoffs](#evaluation-and-cutoffs)
    - [Identifying the cutpoint and OOS
      statistics](#identifying-the-cutpoint-and-oos-statistics)
  - [From 1:1 links to networks](#from-11-links-to-networks)
    - [Applying constraints](#applying-constraints)
    - [Identity Table](#identity-table)
  - [Did it work?](#did-it-work)
    - [Assessing the evaluation
      metrics](#assessing-the-evaluation-metrics)
    - [Manual evaluation heuristics](#manual-evaluation-heuristics)
- [Odds and ends](#odds-and-ends)
  - [Porting an old model into new
    data](#porting-an-old-model-into-new-data)
  - [Iterative development
    principles](#iterative-development-principles)
  - [Opportunities for future
    improvement](#opportunities-for-future-improvement)

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

### Machines vs. probabilistic methods

### Code Location

### Glossary

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

# Workflow Summary

# Set up

## Pipeline setup

These packages are required to set up the pipeline.

``` r
library(targets)
library('hyrule')
library(tarchetypes)
library(glue)
library('sf')
#> Linking to GEOS 3.12.2, GDAL 3.9.3, PROJ 9.4.1; sf_use_s2() is TRUE
library('data.table')
```

Remove the `_targets_r` directory previously written by non-interactive
runs of the report.

``` r
tar_unscript()
```

``` r
getwd()
#> [1] "C:/Users/DCASEY.KC/code/hyrule/example_workflow"
targets::tar_config_get("script")
#> [1] "_targets.R"
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

``` mermaid
graph LR
  style Legend fill:#FFFFFF00,stroke:#000000;
  style Graph fill:#FFFFFF00,stroke:#000000;
  subgraph Legend
    direction LR
    xf1522833a4d242c5([""Up to date""]):::uptodate --- x2db1ec7a48f65a9b([""Outdated""]):::outdated
    x2db1ec7a48f65a9b([""Outdated""]):::outdated --- xeb2d7cac8a1ce544>""Function""]:::none
    xeb2d7cac8a1ce544>""Function""]:::none --- xbecb13963f49e50b{{""Object""}}:::none
  end
  subgraph Graph
    direction LR
    xefefb3a3e737f452>"loadspatial"]:::uptodate --> xa2b6e5d53bc93497>"make_model_frame"]:::uptodate
    xefefb3a3e737f452>"loadspatial"]:::uptodate --> x2d0cf0660ee06fb9>"make_block"]:::uptodate
    xefefb3a3e737f452>"loadspatial"]:::uptodate --> xb4788c2528364ee2>"compile_training_data"]:::uptodate
    xefefb3a3e737f452>"loadspatial"]:::uptodate --> xb102830293ba05f9>"predict_links"]:::uptodate
    xefefb3a3e737f452>"loadspatial"]:::uptodate --> x2cb514632b6a0c33>"make_block_rules"]:::uptodate
    xa2b6e5d53bc93497>"make_model_frame"]:::uptodate --> xb4788c2528364ee2>"compile_training_data"]:::uptodate
    xa2b6e5d53bc93497>"make_model_frame"]:::uptodate --> xb102830293ba05f9>"predict_links"]:::uptodate
    x9ffbf33be4cd0190>"parquet_to_ddb"]:::uptodate --> x49e0f667ebf29789>"create_frequency_table"]:::uptodate
    x9ffbf33be4cd0190>"parquet_to_ddb"]:::uptodate --> x1d4398ab1c75a663>"load_parquet_to_ddb_table"]:::uptodate
    x8f4090117cf7071a>"clean_zip_code"]:::uptodate --> x84e54cf47c0d7f71>"format_zip_centers"]:::uptodate
    xcb14b35fff3b6271>"fit_submodel"]:::uptodate --> xcb14b35fff3b6271>"fit_submodel"]:::uptodate
    xd353de774e427124>"init_data"]:::uptodate --> xd353de774e427124>"init_data"]:::uptodate
    x11484f5aa61f9b0f>"create_history_variable"]:::uptodate --> x11484f5aa61f9b0f>"create_history_variable"]:::uptodate
    xd5255162a4cb3129>"identify_cutoff"]:::outdated --> xd5255162a4cb3129>"identify_cutoff"]:::outdated
    xf98f372e086e8f74>"split_tt"]:::uptodate --> xf98f372e086e8f74>"split_tt"]:::uptodate
    xe50dae2ee0b8ac19>"cv_refit"]:::uptodate --> xe50dae2ee0b8ac19>"cv_refit"]:::uptodate
    x6e35ee78ad6f95e7{{"outdir"}}:::uptodate --> x6e35ee78ad6f95e7{{"outdir"}}:::uptodate
    xb26acde22a0a3a7e>"make_folds"]:::uptodate --> xb26acde22a0a3a7e>"make_folds"]:::uptodate
    x157c37e3c6c668bf>"create_location_history"]:::uptodate --> x157c37e3c6c668bf>"create_location_history"]:::uptodate
    xc979446847d885b6{{"apply_screen"}}:::uptodate --> xc979446847d885b6{{"apply_screen"}}:::uptodate
    x6769762fae5ee540{{"bounds"}}:::uptodate --> x6769762fae5ee540{{"bounds"}}:::uptodate
    x7cf3bbbfdb3130e7>"fixed_links"]:::uptodate --> x7cf3bbbfdb3130e7>"fixed_links"]:::uptodate
    xfcf37a4bc87e3ace>"create_stacked_model"]:::uptodate --> xfcf37a4bc87e3ace>"create_stacked_model"]:::uptodate
    xb8ea961e8bb8a366>"combine_cutoffs"]:::outdated --> xb8ea961e8bb8a366>"combine_cutoffs"]:::outdated
    x83d813b5c4200594>"compile_links"]:::uptodate --> x83d813b5c4200594>"compile_links"]:::uptodate
    x6fa285a2c241fd66>"convert_sid_to_hid"]:::uptodate --> x6fa285a2c241fd66>"convert_sid_to_hid"]:::uptodate
    x4c238137f15a9020>"fit_screening_model"]:::uptodate --> x4c238137f15a9020>"fit_screening_model"]:::uptodate
    x19f80b1ec8be2dfb>"compile_blocks"]:::uptodate --> x19f80b1ec8be2dfb>"compile_blocks"]:::uptodate
  end
  classDef uptodate stroke:#000000,color:#ffffff,fill:#354823;
  classDef outdated stroke:#000000,color:#000000,fill:#78B7C5;
  classDef none stroke:#000000,color:#000000,fill:#94a4ac;
  linkStyle 0 stroke-width:0px;
  linkStyle 1 stroke-width:0px;
  linkStyle 2 stroke-width:0px;
  linkStyle 13 stroke-width:0px;
  linkStyle 14 stroke-width:0px;
  linkStyle 15 stroke-width:0px;
  linkStyle 16 stroke-width:0px;
  linkStyle 17 stroke-width:0px;
  linkStyle 18 stroke-width:0px;
  linkStyle 19 stroke-width:0px;
  linkStyle 20 stroke-width:0px;
  linkStyle 21 stroke-width:0px;
  linkStyle 22 stroke-width:0px;
  linkStyle 23 stroke-width:0px;
  linkStyle 24 stroke-width:0px;
  linkStyle 25 stroke-width:0px;
  linkStyle 26 stroke-width:0px;
  linkStyle 27 stroke-width:0px;
  linkStyle 28 stroke-width:0px;
  linkStyle 29 stroke-width:0px;
  linkStyle 30 stroke-width:0px;
```

## Prepare Data

This section loads, cleans, organizes, and stores data inputs.

There are two main approaches to record linkage:

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

``` r
before = setDT(arrow::read_parquet(tar_read(input_1)))
knitr::kable(head(before))
```

| street_number | street_name | source_id | first_name | middle_initial | last_name | sex | date_of_birth | unit_number | X | Y | zip_code | source_system |
|:---|:---|:---|:---|:---|:---|:---|:---|:---|---:|---:|:---|:---|
| NA | NA | 0_9431 | Denise | H | Rogers | NA | 09/28/1986 | NA | NA | NA | NA | System 1 |
| NA | NA | 0_5728 | Shaneka | T | Pullins | Female | 10/15/1977 | NA | NA | NA | NA | System 1 |
| NA | NA | 0_11287 | Laila | M | Garrett | Female | 01/01/1990 | NA | NA | NA | NA | System 1 |
| NA | 1st avenue south | 0_8875 | Tara | S | Lacroix | Female | 05/12/1991 | NA | NA | NA | NA | System 1 |
| NA | 1st avenue south | 0_11866 | Angela | S | Hampton | Female | 10/10/1993 | NA | NA | NA | NA | System 1 |
| NA | 25th st e | 0_11139 | Cassandra | C | Man Of The House | Female | 07/09/1957 | NA | NA | NA | NA | System 1 |

``` r

after = setDT(arrow::read_parquet(tar_read(data)))
knitr::kable(head(after))
```

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
as they can adjust/downweight common names. For example, John Smith and
John Smith likely is less informative than Unique Name and Unique Name
because John Smith is more common. Using the
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

1.  In real data, there are common “junk” names – e.g. John Doe. These
    should be removed

## Training data

### Creating (new) training data

Unlike probabilistic methods (e.g. splink), machine learning methods
require training data to operate. When beginning a new project, a few
options are available:

1.  Borrow from a previously fit ML model
2.  Borrow from a probabilistic model
3.  Use some deterministic rules
4.  Randomly sampled pairs, if you are mad

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

The models are tuned via [bayesian hyperparameter
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

The final cutoff point is averaged over each iteration of the cross
validation process (the `cv_co` set of products) via the
[`identify_cutoff`](R/identify_cutoff.R) function. This function also
computes the full out of sample (OOS) results.

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

### Applying constraints

While this example does not have any network based constraints, certain
uses cases may require the implementation of deterministic rules. For
example, when linking death records to other types of administrative
information, users may want to enforce a rule that only one death record
may within a network/cluster of linkages (otherwise, it would imply the
“person” represented by the collection of records died twice). The
implementation of those sorts of rules is probably best done as part of
the `complile_links` function (or as a new subsequent step).

### Identity Table

The first part of results stored in `components` target is a file path
to a parquet file containing the final results: a data frame that
crosswalks between `clean_hash`, `source_id` & `source_system`, and
`final_comp_id`. This latter variable is final entity identity. All
source ids with the same `final_comp_id` can be considered as
representing the same “person” (or equivalent).

As currently implemented, the `final_comp_id`s are not persistent
between model versions.

## Did it work?

### Assessing the evaluation metrics

### Manual evaluation heuristics

#### Large low density clusters

#### Twins

#### Multiple people within a source id

# Odds and ends

## Porting an old model into new data

## Iterative development principles

## Opportunities for future improvement
