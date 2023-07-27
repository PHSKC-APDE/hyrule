#' Compute address/location related metrics for record linkage
#' @param pairs data.frame/data.table of record pairs to generate variables for. Must include two id columns (specified by `id1` and `id2` arguments) for `d1` and `d2`
#' @param xy1 sf. Coordinates per record for `d1` for those rows that have them. Must be in the same CRS as `xy2` and have an `id1` column.
#' @param id1 character. Column name identifying a ID column in `id1`. Also must exist in `pairs` and `xy1` and `xy1`, if using.
#' @param xy2 sf. Coordinates per record for  `d2` for those rows that have them. Must be in the same CRS as `xy1` and have an `id2` column.
#' @param id2 character. Column name identifying a ID column in `id2`. Also must exist in `pairs` and `xy2` and `xy2`, if using.
#' @details
#' Given record pairs and location histories, this function returns a data.table(id1, id2, exact_location, min_loc_distance).
#' `exact_location` is a binary flag indicating that the pair has at least one geocoded location within 3 meters.
#' `min_loc_distance` is the minimum distance observed between a record pair in meters
#'
#' @importFrom sf st_geometry_type
process_location_history(pairs, xy1, id1, xy2, id2){
  pairs = unique(pairs[, .SD, .SDcols = c(id1, id2)])
  # most checks for xy1 and xy2 should have occured already

  # double check input geogs are points
  stopifnot(all(sf::st_geometry_type(xy1) %in% 'POINT'))
  stopifnot(all(sf::st_geometry_type(xy2) %in% 'POINT'))

  # subset xy1 and xy2 so that they are only containing rows in pairs
  xy1 = xy1[xy1[[id1]] %in% pairs[[id1]],]
  xy2 = xy2[xy2[[id2]] %in% pairs[[id2]],]

  # compute distance
  dist = st_distance(xy1, xy2)
  dist = data.table::data.table(dist)
  setnames(dist, xy2[[id2]])
  dist[, (id1) := xy1[[id2]]]
  dist = melt(dist, id.vars = id1, variable.name = id2, variable.factor = FALSE)

  # for each pair, find the minimum distance between geocoded addresses
  # subset by pairs we care about
  dist = merge(dist, pairs, by = c(id1, id2))
  dist = dist[, .(min_loc_distance = min(value)), c(id1, id2)]
  dist[, min_loc_distance := as.numeric(units::set_units(min_loc_distance, 'm'))]
  dist[, exact_location := as.integer(min_loc_distance < 3)]

  pairs = merge(pairs, dist, all.x = T, by = c(id1,id2))
  pairs[is.na(exact_location), exact_location := 0L]

  return(pairs)


}
