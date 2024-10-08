#' Prepare a dataset for linkage
#' @param d a hyrule_data object
#' @param first_name character. Identifies the column in `d` with the first name
#' @param middle_name character identifying the column with middle name (or middle initial)
#' @param last_name character. Identifies the column in `d` with the last name
#' @param dob character. Identifies the column with date of birth
#' @param ssn character. column of social security number
#' @param id character. Column containing a unique row level id
#' @param pass_through character. Column names to include in the output object unaltered
#' @export
#' @importFrom data.table setDT tstrsplit year month mday setDF
#' @importFrom stringr str_extract_all
#'
#' @details This function cleans/formats commonly used variables (depending on if they were supplied or not).
#'
prep_data_for_linkage = function(d,
                                 first_name = NULL,
                                 middle_name = NULL,
                                 last_name = NULL,
                                 dob = NULL,
                                 ssn = NULL,
                                 sex = NULL,
                                 id = NULL,
                                 pass_through = NULL){
  stopifnot(inherits(d, 'hyrule_data'))

  # make sure all variables are within d
  cols = list(first_name = first_name, middle_name = middle_name, last_name = last_name, dob = dob, ssn = ssn, id = id)
  cols = unlist(cols)
  mis = setdiff(c(cols, pass_through), colnames(d))
  if(length(mis)>0) stop(paste0('Missing the following columns: ', paste(mis, collapse =',')))

  d = d |> dplyr::rename(all_of(cols))

  if('id' %in% names(cols)){
    id_dupechk = d |> dplyr::group_by(id) |> dplyr::filter(n()>1) |> nrow()
    if(id_dupechk>0) stop('Dataset `d` has duplicate ids. Please make sure there is only one row per id.
                          If you have variables with multiple entries per id, please use the `make_variable_history` function.')
  }

  # sex
  if('sex' %in% names(cols)){
  }

  # First Name
  if('first_name' %in% names(cols)){
    d[, first_name := clean_names(first_name)]
    ## Clean names
    if(name_heuristics){
      d[first_name %in% c('1', 'TRUE', 'true'), first_name := 'True']
      d[first_name %in% 'NULL', first_name := NA]
    }
    d[, first_name_noblank := gsub(' ', '', first_name)]

  }
  # Last Name
  if('last_name' %in% names(cols)){
    d[, last_name := clean_names(last_name)]
    if(name_heuristics) d[last_name %in% 'NULL', last_name := NA]
    d[, last_name_noblank := gsub(' ', '', last_name)]
  }

  # dob
  if('dob' %in% names(cols)){
    stopifnot('`dob` variable must be of type Date' = is.Date(d[['dob']]))
    d[, paste0('dob_', c('year', 'month', 'day')) := list(data.table::year(dob), data.table::month(dob), data.table::mday(dob))]

    ## dob switch
    d[, dobswitch := as.Date(paste0(mday(dob), '-',month(dob), '-', year(dob)), '%m-%d-%Y')]
    d[, paste0('dobswitch_', c('year', 'month', 'day')) := list(year(dobswitch), month(dobswitch), mday(dobswitch))]


  }
  # middle name
  # Middle name
  if('middle_name' %in% names(cols)){
    d[, middle_name := clean_names(middle_name)]
    d[, middle_initial := substr(middle_name,1,1)]
    d[, middle_name_noblank := gsub(' ', '', middle_name)]
  }

  # zip: First five numbers
  if('zip' %in% names(cols)){
    zzz = stringr::str_extract_all(d$zip, "[0-9]+")
    zzz = lapply(zzz, paste, collapse = "")
    zzz = substr(zzz, 1,5)
    d[, zip := zzz]
  }

  # ssn: First nine numbers
  if('ssn' %in% names(cols)){
    sss = stringr::str_extract_all(d$ssn, "[0-9]+")
    sss = lapply(sss, paste, collapse = "")
    sss = substr(sss, 1,9)
    d[, ssn := as.integer(sss)]
  }

  if(!wasDT) data.table::setDF(d)

  return(d)

}
