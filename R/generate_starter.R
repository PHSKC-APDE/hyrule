#' Generate an ensemble based on fake data to use as training dataset creation helper
#' @param variables Character. One or more of 'first_name', 'last_name', 'date_of_birth', 'sex', 'middle_initial', 'zip', 'phone', and 'location.'
#'  Indicates whether these variables (as prepped by prep_data_for_linkage and compute_variables) should inform the resulting linkage ensemble
#' @param match_prop numeric (0,1). The proportion of the training dataset that is made up of matches
#' @export
#' @importFrom sf read_sf
#' @importFrom data.table CJ data.table between
generate_starter = function(variables = c('first_name', 'last_name', 'date_of_birth'), match_prop = .3){
  n = 9000

  # Load data
  d1 = hyrule::fake_one
  d2 = hyrule::fake_two
  pos_vars = c('first_name', 'last_name', 'date_of_birth', 'sex', 'middle_initial', 'zip', 'phone', 'location')
  bad = setdiff(variables, pos_vars)
  if(length(bad)>0) paste(paste(bad, collapse = ', '), ' are not valid options for argument `variables`')
  stopifnot(data.table::between(match_prop, 0, 1, F))

  # Identify some no matchs
  nomatch = data.table::CJ(id1 = d1[, sample(id1,n)], id2 = d2[, sample(id2, n)])
  nomatch = nomatch[id1 != id2]
  nomatch = nomatch[nomatch[, sample(.I, round(n*(1 - match_prop)))]]
  match = sample(intersect(d1[, id1], d2[, id2]), round(match_prop * n))

  pairs = rbind(nomatch, data.table::data.table(id1 = match, id2 = match))
  pairs[, pair := as.integer(id1 == id2)]

  # clean the data
  d1 = cbind(d1[, .(id1 = id1)],
             hyrule::prep_data_for_linkage(d1, 'first_name', 'last_name', 'date_of_birth', 'middle_initial',zip = 'zip', sex = 'sex'))

  d2 = cbind(d2[, .(id2 = id2)],
             hyrule::prep_data_for_linkage(d2, 'first_name', 'last_name', 'date_of_birth', 'middle_initial',zip = 'zip', sex = 'sex'))

  fake_zip = sf::read_sf(system.file("shape/nc.shp", package="sf"))
  fake_zip$zip = fake_zip$CNTY_ID+10000

  a = list(pairs = pairs,
           d1 = d1,
           id1 = 'id1',
           d2 = d2,
           id2 = 'id2',
           xy1 = if('location' %in% variables) location_history_one else NULL,
           xy2 = if('location' %in% variables) location_history_one else NULL,
           ph1 = if('phone' %in% variables) phone_history_one else NULL,
           ph2 = if('phone' %in% variables) phone_history_one else NULL,
           geom_zip = if('zip' %in% variables) fake_zip else NULL)
  a = a[!sapply(a, is.null)]

  train = do.call(compute_variables,
                  args = a)

  # make the formula
  form = list(first_name = c('first_name_cos2'), #'first_name_jw'
              last_name = c('last_name_cos2'), #'last_name_jw'
              middle_initial = c('middle_initial_agree'), #, 'middle_inital_na'
              date_of_birth = c('dob_ham'), #'mis_dob'
              sex = 'sex_disagree',
              zip = 'zip_Mm',
              location = c('exact_location'),
              phone = c('phone_dist', 'max_N_at_number')) #'phone_mis'
  form = form[variables]

  form = unlist(form)
  form = as.formula(paste('pair~', paste(form, collapse = '+')))

  # fit models
  fitz = fit_link(train, form, default_ensemble())

}

