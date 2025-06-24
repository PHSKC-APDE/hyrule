#' Create phone number related variables for linkage
#' @param pairs data.frame/data.table of record pairs to generate variables for. Must include two id columns (specified by `id1` and `id2` arguments) for `d1` and `d2`
#' @param id1 character. Column name identifying a ID column in `id1`. Also must exist in `pairs` and `xy1` and `xy1`, if using.
#' @param id2 character. Column name identifying a ID column in `id2`. Also must exist in `pairs` and `xy2` and `xy2`, if using.
#' @param ph1 data.frame/data.table with (at least) two columns: `id1` and phone_number. A given id can have multiple numbers associated with it. Ideally, includes the whole phone history and not just those limited to `pairs`
#' @param ph2 data.frame/data.table with (at least) two columns: `id2` and phone_number. A given id can have multiple numbers associated with it. Ideally, includes the whole phone history and not just those limited to `pairs`
#' @param default_phone_dist numeric. Default dl (see stringdist::stringdist) distance when one of a pair of numbers is missing
#' @param default_mxn numeric. Default max N at number value when missing. Represent number of people associated with phone number. Default value of 1.5 is chosen arbitrarily
#'
#' @keywords internal
#'
#' @importFrom data.table setnames
#' @importFrom stringr str_replace_all
#' @importFrom stringdist stringdist
#' @importFrom stats median na.omit
process_phone_history = function(pairs, ph1, id1, ph2, id2, default_phone_dist = 6, default_mxn = 1.5){
  pairs = unique(pairs[, .SD, .SDcols = c(id1, id2)])

  # clean phone numbers
  setDT(ph1); setDT(ph2);
  ph1[, phone_number := stringr::str_replace_all(phone_number, "[^0-9]", "")]
  ph2[, phone_number := stringr::str_replace_all(phone_number, "[^0-9]", "")]

  # limit to those numbers within the pair set
  numbers = unique(c(ph1[['phone_number']][ph1[[id1]] %in% pairs[[id1]]],
                     ph2[['phone_number']][ph2[[id2]] %in% pairs[[id2]]]))
  numbers = na.omit(numbers)
  numbers = numbers[numbers != '']

  ph1 = unique(ph1[phone_number %in% numbers, .SD, .SDcols = c(id1, 'phone_number')])
  ph2 = unique(ph2[phone_number %in% numbers, .SD, .SDcols = c(id2, 'phone_number')])

  # compute the number of people at each phone number per dataset
  # Max at 10, just for fun
  mxN = rbind(ph1[, .N, phone_number], ph2[, .N, phone_number])
  mxN = mxN[, .(max_N_at_number = max(N)), phone_number]
  mxN[max_N_at_number>10, max_N_at_number := 10]

  # For each phone number for a person, find the median max number of people
  ph1 = merge(ph1, mxN, all.x = T, by = 'phone_number')
  ph2 = merge(ph2, mxN, all.x = T, by = 'phone_number')
  mnn1 = ph1[, .(max_N_at_number = median(max_N_at_number)), c(id1)]
  mnn2 = ph2[, .(max_N_at_number = median(max_N_at_number)), c(id2)]

  # compute phone distance
  pairs = merge(pairs, ph1, all.x = T, by = id1, allow.cartesian = T)
  pairs = merge(pairs, ph2, all.x = T, by = id2, allow.cartesian = T)
  pairs[, phone_dist := stringdist::stringdist(phone_number.x, phone_number.y, method = 'dl')]
  pairs[phone_dist>10, phone_dist := NA]
  pairs[, phone_mis := as.integer(is.na(phone_dist))]

  pairs[is.na(phone_dist), phone_dist := default_phone_dist]

  # keep only the minimum among pairs
  i = pairs[, .I[which.min(phone_dist)], c(id1, id2)]$V1
  pairs = pairs[i, .SD, .SDcols = c(id1, id2, 'phone_number.x', 'phone_number.y', 'phone_dist', 'phone_mis')]

  # Add on the median n at number stuff
  pairs = merge(pairs, mnn1, all.x = T, by = id1)
  pairs = merge(pairs, mnn2, all.x = T, by = id2)
  pairs[, max_N_at_number := (max_N_at_number.x + max_N_at_number.y)/2 ]

  pairs[is.na(max_N_at_number), max_N_at_number := default_mxn]
  pairs[, paste0('max_N_at_number.', c('x','y')) := NULL]
  data.table::setnames(pairs, paste0('phone_number', c('.x','.y')), paste0('phone_number', 1:2))

  return(pairs[, .SD, .SDcols =
                 c(id1, id2, 'phone_dist',
                   'phone_mis', 'max_N_at_number',
                   'phone_number1', 'phone_number2')])

}
