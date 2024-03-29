Getting Started with Hyrule
================

## hyrule

`hyrule` is a package that contains a few routines to facilitate machine
learning record linkage (MLRL) via ensemble model approach (stacking).

# A sample linkage

This vignette will demonstrate the functions available through the
`hyrule` package to help conduct data linkages. We will be linking two
versions of “fake” data generated by the [psuedopeople
package](https://pseudopeople.readthedocs.io/en/latest/index.html) in
Python.

For some additional details, [review this
presentation](Ensemble%20machine%20learning%20for%20record%20linkage.pdf).
It provides an overview of using machine learning for record linkage as
well as a case study, comparisons to probabilistic methods, advice, and
more (some of which is duplicated here).

## Set up

### Load packages

``` r
library(hyrule)
library('data.table')
```

### Load data

The `hyrule` package comes with two datasets that we will be using to
demonstrate record linkage. Each dataset comes in three parts: (1)
common identifiers like name, date of birth, sex, ZIP; (2) phone number
history/list; and (3) location history (e.g. geocoded addresses). In
general, most linkage problems will have at least the first part of the
dataset (although certain columns are optional). \#2 and \#3 are useful,
but optional.

#### Common Identifiers

``` r

# Load the data
# keep only a the columns needed for this vignette
kcols = c('first_name', 'middle_initial', 'last_name', 'date_of_birth', 'sex', 'zip')
d1 = hyrule::fake_one[, .SD, .SDcols = c('id1', kcols)]
d2 = hyrule::fake_two[, .SD, .SDcols = c('id2', kcols)]
```

``` r
knitr::kable(head(d1))
```

<div class="cell-output-display">

| id1     | first_name | middle_initial | last_name | date_of_birth | sex    |   zip |
|:--------|:-----------|:---------------|:----------|:--------------|:-------|------:|
| 0_100   | Maureen    | M              | Thomas    | 1944-05-24    | Female | 11938 |
| 0_10000 | Jeremy     | J              | Diaz      | 1974-06-25    | Male   | 12068 |
| 0_10001 | Jessica    | S              | Diaz      | 1984-11-18    | Male   | 11825 |
| 0_10002 | Jacob      | J              | Diaz      | 2008-12-11    | Male   | 11841 |
| 0_10003 | Vanessa    | E              | Baker     | 1973-02-12    | Female | 12032 |
| 0_10004 | Sean       | C              | Baker     | 1975-05-08    | Male   | 12090 |

</div>

#### Phone Numbers

Phone numbers should be long on individual id (in this case, `id1` or
`id2`) and phone number entry. This way one id can be associated with
multiple numbers.

``` r
ph1 = hyrule::phone_history_one
ph2 = hyrule::phone_history_two
knitr::kable(head(ph1))
```

<div class="cell-output-display">

| id1    | variable | phone_number |
|:-------|:---------|-------------:|
| 0_2    | phone1   |   1000002869 |
| 0_3    | phone1   |   1000009473 |
| 0_923  | phone1   |   1000002920 |
| 0_2641 | phone1   |   1000004711 |
| 0_2801 | phone1   |   1000007099 |
| 0_6176 | phone1   |   1000006057 |

</div>

#### Location history

Location history should be an `sf` object long on the id variable and
location entry. That is, each id can be associated with more than one
address. If using location history type information, make sure that the
data are points and the CRSs have been synchronized ahead of time.

``` r
lh1 = hyrule::location_history_one
lh2 = hyrule::location_history_two
knitr::kable(head(lh1))
```

<div class="cell-output-display">

| id1     | time | geom                       |
|:--------|-----:|:---------------------------|
| 0_100   |    1 | POINT (-78.57067 35.9593)  |
| 0_10000 |    1 | POINT (-81.26805 35.34975) |
| 0_10001 |    1 | POINT (-81.68972 36.46129) |
| 0_10002 |    1 | POINT (-78.91767 36.45782) |
| 0_10003 |    1 | POINT (-81.67706 35.36557) |
| 0_10004 |    1 | POINT (-78.94941 35.20854) |

</div>

## Clean data

### Common Identifiers

The `prep_data_for_linkage` function provides data cleaning routines for
variables commonly used in data linkage. These include name, date of
birth, ZIP code, sex, and social security number.

``` r
d1 = prep_data_for_linkage(d1, 
                           first_name = 'first_name',
                           last_name = 'last_name',
                           dob = 'date_of_birth',
                           middle_name = 'middle_initial',
                           zip = 'zip',
                           sex = 'sex',
                           id = 'id1')
d2 = prep_data_for_linkage(d2,
                           first_name = 'first_name',
                           last_name = 'last_name',
                           dob = 'date_of_birth',
                           middle_name = 'middle_initial',
                           zip = 'zip',
                           sex = 'sex',
                           id = 'id2')

# Make a copy for a demonstration later one
# usually you won't need/want to do this
hd1 = copy(d1)
hd2 = copy(d2)
```

### Notes

Often location history and phone numbers will need to be cleaned (and/or
reformatted). At present that must be done using common data
manipulation tools (e.g. data.table and dplyr).

## The machine learning linkage loop

Machine learning record linkage works in three main steps as listed.

1.  A training dataset is created by manually labeling pairs of records
    as a match or not a match
2.  A set of models are fit on the training dataset
3.  The fit models are applied (e.g. prediction) to all of the potential
    pairs

Once a has been complete, you can review the results and figure out if
additional variables need to be added and/or if the training data needs
to be augmented.

## Blocking: generating possible pairs

Blocking is the process in which a-priori conditions are used to limit
the potential universe of possible pairs. For example, you might require
that a pair of records have the same year of birth before evaluating
whether or not they are a match based on the full set of available
information. Blocking turns a large problem (everyone compared to
everyone else) into a set of slightly smaller ones (compare everyone
born in 1990 with everyone else born in 1990). We can block on multiple
things sequentially (e.g. year of birth and then sex) and/or jointly
(sex AND year of birth). Sequential blocking schemes require some
reconciliation process at the end to remove duplicates and do other
clean up (beyond the scope of this vignette). This might also occur if
you have missingness in our blocking variable and you allow those rows
to be assessed in multiple blocks.

### Example

In this example, we block on date of birth year. For simplicity, we are
only going to work with records between 1900 and 2022.

``` r

posyears = unique(c(d1[, dob_year], d2[, dob_year]))
posyears = na.omit(posyears)
posyears = sort(posyears[posyears>=1900 & posyears<=2022])

# Create a list of lists
# Each entry is the ids from each dataset belonging to the block
# as determined by DOB year
blocks = lapply(posyears, function(x){
  list(a = d1[dob_year == x, id1], b = d2[dob_year == x, id2])
})
```

## Making a training dataset

In general, I recommend starting with a pre-trained model and using that
model to make an initial pass at your data. If you are lucky, the
previously trained model is good enough and your job is done. More
likely, you’ll want to use these initial predictions to inform how you
select pairs to manually identify as a match or not. It is probably
better to use a a model fit on “real” data (ask Daniel for more), but if
that is not available, you can use `hyrule::generate_starter()` to
create a model fit on fake data. See `?hyrule::generate_starter()` for
more details about the various arguments.

Under the hood, `generate_starter` uses `hyrule::prep_data_for_linkage`
and `hyrule::compute_variables`. If you use those functions

Note: This example will be a little weird since we are fitting a model
on the same fake data that is standing in as the “real” data for this
vignette. Usually this won’t be a problem.

``` r
starter = hyrule::generate_starter(variables = c('first_name', 'last_name', 'date_of_birth'), match_prop = .5)
#>  Setting default kernel parameters
```

The resulting object (`starter`) is a `hyrule_link` class. Basically its
a list containing a screening/first stage logistic regression, the
ensemble model, and some bounds.

### Predictions

With the starter model providing some initial guidance, we predict on
the blocked pairs created above. The code displayed below is one way to
generate the predictions— but as your data gets bigger, you may need to
get more clever about how you process the predictions: parallelization
and/or saving intermediate objects may be your friend.

``` r
i = 0
preds = lapply(blocks, function(b){
  # print(i <<- i + 1)
  d = CJ(id1 = b[[1]], id2 = b[[2]])
  if(nrow(d) <1) return(data.table())
  
  # Generate pairs and their values
  d = hyrule::compute_variables(d, d1, 'id1', d2, 'id2')
  
  # make predictions
  p = predict(starter, d, members = FALSE)
  
  
  r = cbind(d, p)
  
  # if you need to save space, you can drop rows below a threshold here
  
  r
  
  
})

preds = rbindlist(preds)
```

### Generating an initial training dataset

One method for generating pairs to manually evaluate to create a
training dataset is sampling a set number of rows from each decile of
predictions. This is not the only way (or maybe even the best way) to do
it, but it works well enough. The number 25 below is selected
arbitrarily. A training dataset of 150 - 300 pairs seems like a decent
place to start though.

``` r
preds[, decile := cut(final,seq(0,1,.1))]

# Select 15 rows for each
preds[, pairid := .I]
trainme = preds[, sample(pairid, min(c(.N,25))), decile]
trainme = preds[trainme[, V1], .(id1, id2)]
knitr::kable(head(trainme))
```

<div class="cell-output-display">

| id1     | id2     |
|:--------|:--------|
| 0_5160  | 0_5160  |
| 0_10556 | 0_11011 |
| 0_14664 | 0_14580 |
| 0_18062 | 0_18062 |
| 0_4609  | 0_4609  |
| 0_73    | 0_16933 |

</div>

With the pairs to evaluate selected, you can use `hyrule::matchmaker` to
launch a shiny app that provides a gui to assist with creating a
training dataset. `matchmaker` requires loading a pairs file (like
`trainme` above) and both datasets (e.g. `fake_one` and `fake_two`). The
datasets should be long on individual (id). Columns (like address or
phone_number) that may have multiple entries per id should be cast wide.
You may need to create placeholder columns in one dataset if it has more
entries than the other (e.g. if dataset A has phone_number1 and
phone_number2, but dataset B only naturally has phone_number1 you should
create a blank (’’) phone_number2 column in B).

Review the format of `hyrule::pairs`, `hyrule::fake_one`, and
`hyrule::fake_two` for more hints on how you need to structure your
data.

You can also use `hyrule::compute_variables` to do some initial cleaning
for you:

``` r

matchprep = hyrule::compute_variables(trainme, hd1, 'id1', hd2, 'id2', 
                                      xy1 = location_history_one,
                                      xy2 = location_history_two, 
                                      ph1 = phone_history_one,
                                      ph2 = phone_history_two)
nms = names(matchprep)
cols1 = nms[substr(nms, nchar(nms), nchar(nms))==1]
cols2 = nms[substr(nms, nchar(nms), nchar(nms))==2]

data1 = matchprep[, .SD, .SDcols = c(cols1, 'exact_location')]
data2 = matchprep[, .SD, .SDcols = c(cols2, 'exact_location')]
setnames(data1, cols1, substr(cols1, 1, nchar(cols1)-1))
setnames(data2, cols2, substr(cols2, 1, nchar(cols2)-1))

# save pairs, data1, and data2
# and then load them into match maker
# you lose some of the address history stuff
# but you have to do less work
```

## Fittin’ and predictin’

### Loading training data

Once your training dataset is manually labeled, we need to fit the
ensemble on this new data. Because we are working with fake data, I get
to cheat and know the truth without manually labelling data:

``` r
#usually you will load the matchmaker results from disk
trainme[, ismatch := as.integer(id1 == id2)]
```

Once loaded we need to run `hyrule::compute_variables` and do other
variable creation. We’ve already done that above so we won’t duplicate
our work:

``` r
# doing this again, for fun.
matchprep[, ismatch := id1 == id2]
```

### Deciding on the formula

The variables created by `hyrule::compute_variables` (and others you
might add) are good candidates for predictors. We convey this
information to the ensemble model via a formula. The example below is a
simplified formula for demonstration purposes:

``` r
form = ismatch ~ dob_ham + full_name_cosine3
```

We pass this formula and the data to `hyrule::fit_link` to generate our
ensemble for us. We are using the default ensemble (random forest,
xgboost, and SVM) from `hyrule::default_ensemble()`, but any list of
`parsnip::` classification model specifications should work. Its
untested, but you might also be able to do parameter tuning from the
`tune` package– although if you are getting to that stage of complexity,
you should probably just write your own functions.

Note: The following code is not actually executed. The fake data used in
this example is good enough for demonstration purposes and maybe even
generating a starter model, but it kind of craps out through the next
few steps. “Real” data shouldn’t have this problem.

``` r
mods = fit_link(matchprep, formula = form, 
                ensemble = default_ensemble(),
                bounds = c(.001,.999))
```

After the model is fit, you can predict for your blocked observations
(see the section on blocking, above). With a new set of predictions you
can either call it good, or add more training data/variables and do
another iteration.
