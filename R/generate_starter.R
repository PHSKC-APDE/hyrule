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

  # Make the cross join
  pairs = CJ(id1 = d1[, simulant_id], id2 = d2[, simulant_id])
  pairs[, pid := .I]

  nomatch = pairs[id1 !=id2, sample(pid, round(1000*(1 - match_prop)))]
  match = pairs[id1 == id2, sample(pid, round(1000 * match_prop))]

  pairs = pairs[pid %in% c(nomatch, match)]

  # clean the data
  d1 = cbind(d1[, .(id1 = simulant_id)],
             hyrule::prep_data_for_linkage(d1, 'first_name', 'last_name', 'date_of_birth', 'middle_initial',zip = 'zip', sex = 'sex'))

  d2 = cbind(d2[, .(id2 = simulant_id)],
             hyrule::prep_data_for_linkage(d2, 'first_name', 'last_name', 'date_of_birth', 'middle_initial',zip = 'zip', sex = 'sex'))

  fake_zip = sf::read_sf(system.file("shape/nc.shp", package="sf"))
  fake_zip$zip = fake_zip$CNTY_ID+10000


  train = compute_variables(pairs, d1, 'id1', d2, 'id2',
                            location_history_one, location_history_two,
                            ph1, ph2,
                            geom_zip = fake_zip)

}





# Make a dataset that is 30 match,
pairs
