#' Create phone number related variables for linkage
#' @param pairs data.frame/data.table of record pairs to generate variables for. Must include two id columns (specified by `id1` and `id2` arguments) for `d1` and `d2`
#' @param id1 character. Column name identifying a ID column in `id1`. Also must exist in `pairs` and `xy1` and `xy1`, if using.
#' @param id2 character. Column name identifying a ID column in `id2`. Also must exist in `pairs` and `xy2` and `xy2`, if using.
#' @param ph1 data.frame/data.table with (at least) two columns: `id1` and phone_number. A given id can have multiple numbers associated with it. Ideally, includes the whole phone history and not just those limited to `pairs`
#' @param ph2 data.frame/data.table with (at least) two columns: `id2` and phone_number. A given id can have multiple numbers associated with it. Ideally, includes the whole phone history and not just those limited to `pairs`
process_phone_history = function(pairs, ph1, id1, ph2, id2){
  pairs = unique(pairs[, .SD, .SDcols = c(id1, id2)])

  # clean phone numbers
  setDT(ph1); setDT(ph2);
  ph1[, phone_number := stringr::str_replace_all(value, "[^0-9]", "")]
  ph2[, phone_number := stringr::str_replace_all(value, "[^0-9]", "")]

  # limit to those numbers within the pair set
  numbers = unique(ph1[get(id1) %in% pairs[, get(id1)], phone_number],
                   ph2[get(id2) %in% pairs[, get(id2)], phone_number])
  numbers = na.omit(numbers)
  numbers = numbers[numbers != '']

  ph1 = unique(ph1[phone_number %in% numbers, .SD, .SDcols = c(id1, 'phone_number')])
  ph2 = unique(ph2[phone_number %in% numbers, .SD, .SDcols = c(id2, 'phone_number')])

  # compute the number of people at each phone number per dataset
  # Max at 10, just for fun
  mxN = rbind(ph1[, .N, phone_number], ph2[ .N, phone_number])
  mxN = mx_N_at_number[, .(max_N_at_number = max(N)), phone_number]
  mxN[N>10, max_N_at_number := 10]

  # For each phone number for a person, find the median max number of people
  ph1 = merge(ph1, mxN, all.x = T, by = 'phone_number')
  ph2 = merge(ph2, mxN, all.x = T, by = 'phone_number')
  mnn1 = ph1[, .(median_n_at_number = median(max_n_at_number)), c(id1)]
  mnn2 = ph2[, .(median_n_at_number = median(max_n_at_number)), c(id2)]

  # compute phone distance
  pairs = merge(pairs, ph1, all.x = T, by = id1, allow.cartesian = T)
  pairs = merge(pairs, ph2, all.x = T, by = id2, allow.cartesian = T)
  pairs[, phone_dist := stringdist(phone_number.x, phone_number.y, method = 'dl')]
  pairs[phone_dist>10, phone_dist := NA]
  pairs[, phone_mis := as.integer(is.na(phone_dist))]
  pairs[is.na(phone_dist), phone_dist := mean(pairs[,phone_dist], na.rm = T)]

  # keep only the minimum among pairs
  pairs = pairs[pairs[, .I[which.min(phone_dist)], c(id1, id2)]$V1, ]

  # Add on the median n at number stuff
  pairs = merge(pairs, mnn1, all.x = T, by = id1)
  pairs = merge(pairs, mnn2, all.x = T, by = id2)
  pairs[, median_n_at_number := (median_n_at_number.x + median_n_at_number.y)/2 ]
  pairs[, paste0('median_n_at_number.', c('x','y')) := NULL]
  data.table::setnames(pairs, paste0('phone_number', c('.x','.y')), paste0('phone_number', 1:2))

  return(pairs[, .SD, .SDcols =
                 c(id1, id2, 'phone_dist',
                   'phone_mis', 'median_n_at_number',
                   'phone_number1', 'phone_number2')])

}
