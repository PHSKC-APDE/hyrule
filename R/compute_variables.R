#' Create variables for linkage
#' @param pairs data.frame/data.table of record pairs to generate variables for. Must include two id columns (specified by `id1` and `id2` arguments) for `d1` and `d2`
#' @param d1 data.frame/data.table of records prepped via `prep_data_for_linkage`
#' @param id1 character. Column name identifying a ID column in `id1`. Also must exist in `pairs` and `xy1` and `xy1`, if using.
#' @param d2 data.frame/data.table of records `prep_data_for_linkage`
#' @param id2 character. Column name identifying a ID column in `id2`. Also must exist in `pairs` and `xy2` and `xy2`, if using.
#' @param xy1 sf. Coordinates per record for `d1` for those rows that have them. Must be in the same CRS as `xy2` and have an `id1` column. Ideally, its best to pass things geocoded to a level finer than a ZIP code
#' @param xy2 sf. Coordinates per record for  `d2` for those rows that have them. Must be in the same CRS as `xy1` and have an `id2` column. Ideally, its best to pass things geocoded to a level finer than a ZIP code
#' @param ph1 data.frame/data.table with (at least) two columns: `id1` and phone_number. A given id can have multiple numbers associated with it. Ideally, includes the whole phone history and not just those limited to `pairs`
#' @param ph2 data.frame/data.table with (at least) two columns: `id2` and phone_number. A given id can have multiple numbers associated with it. Ideally, includes the whole phone history and not just those limited to `pairs`
#' @param geom_zip sf object of ZIP codes. Must have a column named `zip`. `tigris::zctas` is (with a bit of modification) a decent place to start. You may want to do custom coding if you have more than one ZIP per record to choose the minimum one.
#' @export
#' @details
#' `pairs`, `d1`, `d2`, `ph1`, and `ph2` will all be converted into data.tables internally.
#' There is a slight chance this change the objects in the parent environment
#'
#' @importFrom sf st_crs st_distance st_centroid
#' @importFrom data.table setnames data.table copy
#' @importFrom units set_units
#' @importFrom stringdist stringdist
compute_variables = function(pairs, d1, id1, d2, id2, xy1, xy2, ph1, ph2, geom_zip){

  # Hamming distance
  ham = function(x,y) stringdist::stringdist(as.character(x), as.character(y), 'hamming')

  # Validate inputs
  stopifnot(is.data.frame(pairs))
  stopifnot(!any(names(pairs) %in% '_rid'))
  stopifnot(is.data.frame(d1))
  stopifnot(is.data.frame(d2))
  stopifnot(missing(xy1) && missing(xy2) || (!missing(xy1) && !missing(xy2)))
  stopifnot(missing(ph1) && missing(ph2) || (!missing(ph1) && !missing(ph2)))
  stopifnot(length(id1) == 1 & id1 %in% names(d1))
  stopifnot(length(id2) == 1 & id2 %in% names(d2))
  stopifnot('`id1` and `id2` cannot be the same value' = id1 != id2)
  if(!missing(geom_zip)){
    stopifnot(inherits(geom_zip, 'sf'))
    stopifnot('zip' %in% names(geom_zip))
    stopifnot('Found duplicate rows/zips in geom_zip' = !anyDuplicated(geom_zip$zip))

  }
  if(!missing(xy1) && !missing(xy2)){
    stopifnot(inherits(xy1, 'sf'))
    stopifnot(inherits(xy2, 'sf'))
    stopifnot(sf::st_crs(xy1) == sf::st_crs(xy2))
  }
  if(!missing(ph1) && !missing(ph2)){
    stopifnot(c(id1, 'phone_number') %in% names(ph1))
    stopifnot(c(id2, 'phone_number') %in% names(ph2))
  }

  useDT = any(is.data.table(pairs) | is.data.table(d1) | is.data.table(d2))
  setDT(pairs); setDT(d1); setDT(d2)
  pairs = copy(pairs)[, `_rid` := .I]


  # make sure id1 and id2 are uniquely identifying
  stopifnot('id1 does not uniquely identify rows in d1' = d1[, .N, c(id1)][, all(N == 1)])
  stopifnot('id2 does not uniquely identify rows in d2' = d2[, .N, c(id2)][, all(N == 1)])


  # Identify variables to create
  # This should get updated as prep_data_for_linkage gets updated
  pos_vars = c('sex', 'first_name_noblank', 'last_name_noblank',
               'dob', 'middle_name_noblank', 'middle_initial',
               'zip', 'ssn')

  vardt = data.table::data.table(pv = pos_vars)
  vardt[, one := pv %in% names(d1)]
  vardt[, two := pv %in% names(d2)]
  vardt = vardt[one == TRUE & two == TRUE]
  v = vardt[, pv]

  # Fix dataset naming
  d1 = d1[, .SD, .SDcols = c(id1, v)]
  data.table::setnames(d1, v, paste0(v,'1'))

  d2 = d2[, .SD, .SDcols = c(id2, v)]
  data.table::setnames(d2, v, paste0(v,'2'))

  input = merge(pairs, d1, all.x = T, by = id1)
  input = merge(input, d2, all.x = T, by = id2)

  # Date of birth metrics
  if('dob' %in% v){
    # Hamming distance of DOB
    input[, dob_ham := ham(dob1, dob2)]
    input[, mis_dob := as.integer(is.na(dob_ham))]
    input[, mean_dob_ham := mean(dob_ham, na.rm= T)]
    input[mis_dob == 1, dob_ham := mean_dob_ham]

  }

  # Sex metrics
  if('sex' %in% v){
    input[, sex_disagree := as.integer(sex1 != sex2)]
    input[is.na(sex_disagree), sex_disagree := 0]
  }

  # first name metrics
  if('first_name_noblank' %in% v){
    input[!is.na(first_name_noblank1) & !is.na(first_name_noblank2),
          c('first_name_cos2', 'first_name_jw') :=list(
            stringdist::stringdist(first_name_noblank1,
                                   first_name_noblank2,
                                   'cosine',
                                   q = ifelse(nchar(first_name_noblank1) <2 | nchar(first_name_noblank2) <2,1,2)),
            stringdist::stringdist(first_name_noblank1,
                                   first_name_noblank2,
                                   'jw',
                                   p = .1)
          )]

    input[is.na(first_name_cos2), first_name_cos2 := 1]
    input[is.na(first_name_jw), first_name_jw := 1]

  }

  # last name metrics
  if('last_name_noblank' %in% v){
    input[!is.na(last_name_noblank1) & !is.na(last_name_noblank2),
          c('last_name_cos2', 'last_name_jw') :=list(
            stringdist::stringdist(last_name_noblank1,
                                   last_name_noblank2,
                                   'cosine',
                                   q = ifelse(nchar(last_name_noblank1) <2 | nchar(last_name_noblank2) <2,1,2)),
            stringdist::stringdist(last_name_noblank1,
                                   last_name_noblank2,
                                   'jw',
                                   p = .1)
          )]

    input[is.na(last_name_cos2), last_name_cos2 := 1]
    input[is.na(last_name_jw), last_name_jw := 1]

  }

  # combined name
  if(all(c('first_name_noblank', 'last_name_noblank') %in% v)){
    input[, firstlast_noblank1 := paste0(first_name_noblank1, last_name_noblank1)]
    input[, firstlast_noblank2 := paste0(first_name_noblank2, last_name_noblank2)]



    input[!is.na(first_name_noblank1) & !is.na(last_name_noblank1) & !is.na(first_name_noblank2) & !is.na(last_name_noblank2),
          full_name_cosine3 := stringdist::stringdist(paste0(first_name_noblank1, last_name_noblank1),
                                 paste0(first_name_noblank2, first_name_noblank2),
                                 'cosine', q = 3)]
    input[is.na(full_name_cosine3), full_name_cosine3 := 1]

  }

  # middle name
  if('middle_initial' %in% v){
    input[, middle_initial_agree := as.integer(middle_initial1 == middle_initial2)]
    input[is.na(middle_initial_agree), middle_initial_agree := 0]
    input[, middle_initial_na := as.integer(middle_initial1 == '' | middle_initial2 == '')]
    input[is.na(middle_initial_na), middle_initial_na := 1]
  }

  # Updated combined name
  if(all(c('first_name_noblank', 'last_name_noblank', 'middle_name_noblank') %in% v)){

    input[, complete_name_noblank1 := pastenm(first_name_noblank1,ifelse(nchar(middle_name_noblank1)>1, middle_name_noblank1, ''), last_name_noblank1)]
    input[, complete_name_noblank2 := pastenm(first_name_noblank2,ifelse(nchar(middle_name_noblank2)>1, middle_name_noblank2, ''), last_name_noblank2)]

    input[!is.na(complete_name_noblank1) & !is.na(complete_name_noblank2),
          full_name_cosine3_mid := stringdist::stringdist(complete_name_noblank1,
                                                         complete_name_noblank2,
                                                         'cosine', q = 3)]
    input[is.na(full_name_cosine3_mid), full_name_cosine3_mid := 1]
    input[, full_name_cosine3_nomid := full_name_cosine3]

    input[full_name_cosine3 > full_name_cosine3_mid, full_name_cosine3 := full_name_cosine3_mid]
  }


  # ZIP code
  # same, NA, and mega meter
  if('zip' %in% v){
    input[, zip_agree := as.integer(zip1 == zip2)]
    input[is.na(zip_agree), zip_agree := 0]
    input[, zip_na := is.na(zip1) | is.na(zip2)]

    if(!missing(geom_zip)){
      geom_zip = subset(geom_zip, zip %in% unique(c(input[, zip1], input[,zip2])))
      geom_zip = sf::st_centroid(geom_zip)
      dist = data.table::data.table(st_distance(geom_zip, geom_zip))
      data.table::setnames(dist, as.character(geom_zip$zip))
      dist[, zip1 := geom_zip$zip]
      dist = melt(dist, id.var = 'zip1', variable.factor = F, variable.name = 'zip2')
      dist[, zip_Mm := as.numeric(units::set_units(value, '1e6*m'))]
      dist[, c('zip1', 'zip2') := list(as.character(zip1), as.character(zip2))]

      input = merge(input, dist, all.x = T, by = c('zip1', 'zip2'))

      # For missing ZIPs, use average
      input[is.na(zip_Mm), zip_Mm := input[, mean(zip_Mm, na.rm = T)]]

    }

  }
  # location
  if(!missing(xy1) && !missing(xy2)){
    locs = process_location_history(pairs, xy1, id1, xy2, id2)
    input = merge(input, locs, all.x = T, by = c(id1, id2))
  }

  # phone
  if(!missing(ph1) && !missing(ph2)){
    ph = process_phone_history(pairs, ph1, id1, ph2, id2)
    input = merge(input, ph, all.x = T, by = c(id1, id2))
  }

  setorder(input, '_rid')
  input[, `_rid` := NULL]



  return(input)
}

