#' Generate an ensemble based on fake data to use as training dataset creation helper
#' @param variables Character. One or more of 'first_name', 'last_name', 'date_of_birth', 'sex', 'middle_initial', 'zip', 'phone', and 'location.'
#'  Indicates whether these variables (as prepped by prep_data_for_linkage and compute_variables) should inform the resulting linkage ensemble
#' @param match_prop numeric (0,1). The proportion of the training dataset that is made up of matches
#' @export
#' @importFrom sf read_sf
generate_starter = function(variables = c('first_name', 'last_name', 'date_of_birth'), match_prop = .3){
  # Load data
  d1 = hyrule::fake_one
  d2 = hyrule::fake_two
  pos_vars = c('first_name', 'last_name', 'date_of_birth', 'sex', 'middle_initial', 'zip', 'phone', 'location')
  bad = setdiff(variables, pos_vars)
  if(length(bad)>0) paste(paste(bad, collapse = ', '), ' are not valid options for argument `variables`')
  stopifnot(data.table::between(match_prop, 0, 1, F))

  # Identify some no matchs
  nomatch = CJ(id1 = d1[, sample(id1,1000)], id2 = d2[, sample(id2, 1000)])
  nomatch = nomatch[id1 != id2]
  nomatch = nomatch[nomatch[, sample(.I, round(1000*(1 - match_prop)))]]
  match = sample(intersect(d1[, id1], d2[, id2]), round(match_prop * 1000))

  pairs = rbind(nomatch, data.table(id1 = match, id2 = match))
  pairs[, pair := as.integer(id1 == id2)]

  # clean the data
  d1 = cbind(d1[, .(id1 = id1)],
             hyrule::prep_data_for_linkage(d1, 'first_name', 'last_name', 'date_of_birth', 'middle_initial',zip = 'zip', sex = 'sex'))

  d2 = cbind(d2[, .(id2 = id2)],
             hyrule::prep_data_for_linkage(d2, 'first_name', 'last_name', 'date_of_birth', 'middle_initial',zip = 'zip', sex = 'sex'))

  fake_zip = sf::read_sf(system.file("shape/nc.shp", package="sf"))
  fake_zip$zip = fake_zip$CNTY_ID+10000

  train = compute_variables(pairs, d1, 'id1', d2, 'id2',
                            location_history_one, location_history_two,
                            phone_history_one, phone_history_two,
                            geom_zip = fake_zip)

}





# Make a dataset that is 30 match,
pairs
