#' Prepare a dataset for linkage
#' @param d data.frame
#' @param first_name character. Identifies the column in `d` with the first name
#' @param last_name character. Identifies the column in `d` with the last name
#' @param dob character. Identifies the column with date of birth
#' @param middle_name. character identifying the column with middle initial
#' @param zip character. Default is NULL. Column that includes ZIP code data
#' @param name_heuristics logical. Indicates whether common name cleaning heuristics should be implemented
#' @export
#' @importFrom data.table setDT tstrsplit year month mday
#'
prep_data_for_linkage = function(d, first_name, last_name, dob, middle_name = NULL, zip = NULL, name_heuristics = TRUE ){

  setDT(d)

  # make sure all variables are within d
  cols = list(first_name = first_name, last_name = last_name, dob = dob, zip = zip)
  cols = unlist(cols)
  mis = setdiff(cols, names(d))
  if(length(mis)>0) stop(paste0('Missing the following columns: ', paste(mis, collapse =',')))
  d = d[, .SD, .SDcols = cols]
  setnames(d, cols, names(cols))

  # Date of Birth
  ## clean date of birth
  stopifnot(is.Date(d[['dob']]))
  d[, paste0('dob_', c('year', 'month', 'day')) := list(year(dob), month(dob), mday(dob))]

  ## dob switch
  d[, dobswitch := as.Date(paste0(mday(dob), '-',month(dob), '-', year(dob)), '%m-%d-%Y')]
  d[, paste0('dobswitch_', c('year', 'month', 'day')) := list(year(dobswitch), month(dobswitch), mday(dobswitch))]

  # Names
  ## clean names
  d[, first_name := clean_names(first_name)]
  d[, last_name := clean_names(last_name)]

  ## Clean names
  if(name_heuristics){
    d[first_name %in% c('1', 'TRUE', 'true'), first_name := 'True']
    d[first_name %in% 'NULL', first_name := NA]
    d[last_name %in% 'NULL', last_name := NA]
  }

  ## split
  fns = d[, tstrsplit(first_name, split = ' ')]
  setnames(fns, paste0('fn_', seq_len(ncol(fns))))
  lns = d[, tstrsplit(last_name, split = ' ')]
  setnames(lns, paste0('ln_', seq_len(ncol(lns))))

  d = cbind(d, fns[, .SD, .SDcols = intersect(paste0('fn_', 1:8), names(fns))])
  d = cbind(d, lns[, .SD, .SDcols = intersect(paste0('ln_', 1:8), names(lns))])

  ## name, no splits
  d[, first_name_noblank := gsub(' ', '', first_name)]
  d[, last_name_noblank := gsub(' ', '', last_name)]

  ## first initial
  d[, first_initial := substr(first_name, 1,1)]

  ## TODO: Considered putting name frequency here

  # Middle initial
  if(!is.null(middle_name)){
    d[, middle_initial := substr(clean_names(middle_name),1,1)]
  }

  # ZIP
  ## first five digits
  if(!is.null(zip)){
    zzz = stringr::str_extract_all(d$zip, "[0-9]+")
    zzz = lapply(zzz, paste, collapse = "")
    zzz = substr(zzz, 1,5)
    d[, zip := zzz]
  }


  ## TODO: clean sex or other common columns

  return(d)

}
