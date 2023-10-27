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
#' @importFrom sf st_geometry_type st_centroid st_distance st_as_sf
#' @importFrom data.table set data.table as.data.table
#' @importFrom units set_units drop_units
process_location_history = function(pairs, xy1, id1, xy2, id2){
  pairs = unique(pairs[, .SD, .SDcols = c(id1, id2)])

  # double check input geogs are points
  stopifnot(all(sf::st_geometry_type(xy1) %in% 'POINT'))
  stopifnot(all(sf::st_geometry_type(xy2) %in% 'POINT'))

  # subset xy1 and xy2 so that they are only containing rows in pairs
  xy1 = xy1[xy1[[id1]] %in% pairs[[id1]],]
  xy2 = xy2[xy2[[id2]] %in% pairs[[id2]],]

  # most checks for xy1 and xy2 should have occured already
  if(nrow(xy1) == 0 | nrow(xy2) == 0){
    return(pairs[, exact_location := 0])
  }

  crs = st_crs(xy1)

  xy1 = data.table::as.data.table(sf::st_coordinates(xy1))[, (id1) := xy1[[id1]]]
  xy2 = data.table::as.data.table(sf::st_coordinates(xy2))[, (id2) := xy2[[id2]]]
  dist = merge(pairs[, .SD, .SDcols = c(id1, id2)],xy1, all.x = T, by = id1, allow.cartesian = T)
  dist = dist[!is.na(X)]
  dist = merge(dist, xy2, all.x = T, by = id2, allow.cartesian = T)
  dist = dist[!is.na(X.y)]

  # Keep only entries with non missing

  # compute distance
  dres = sf::st_distance(sf::st_as_sf(dist, coords = c('X.x', 'Y.x'), crs = crs), sf::st_as_sf(dist, coords = c('X.y', 'Y.y'), crs = crs), by_element = T)
  ut = attributes(dres)$units
  dist = dist[, .SD, .SDcols = c(id1,id2)][, value := as.numeric(dres)]

  # for each pair, find the minimum distance between geocoded addresses
  # subset by pairs we care about
  dist = merge(dist, pairs, by = c(id1, id2))
  dist = dist[, .(min_loc_distance = min(value)), c(id1, id2)]

  # Find the conversion from the input unit to the desired unit
  to_meter = units::set_units(units::as_units(1, ut$numerator), 'm')

  dist[, min_loc_distance := min_loc_distance * as.numeric(to_meter)]
  dist[, exact_location := as.integer(min_loc_distance < 3)]

  pairs = merge(pairs, dist, all.x = T, by = c(id1,id2))
  pairs[is.na(exact_location), exact_location := 0L]

  return(pairs)


}
