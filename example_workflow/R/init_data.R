#' Initialize a dataset for linkage
#' @param input a file path to a parquet file or a function that returns a data frame
#' @param output_file file path to a .parquet file where the cleaned data will be saved. If NULL, the results are returned as a data frame
#' @param ... arguments passed to input (when input is a function)
#' @details
#' This function achieves a few things:
#' 1) Loads data from the source specified by input
#' 2) Cleans the data (most of the code)
#' 3) Hashes each row of data to create the unit of analysis (e.g. making an id)
#' 4) Saves the data as specified by output_file
#'
#' Depending on the structure of linkage, you may need two or more init data functions.
#'
#' Additionally, this function will likely need to be changed which each dataset/linkage due to different columns
#' and/or different linkage goals.
#'
init_data = function(input, output_file = NULL, ...){

  # Load data ----
  if(is.character(input) && all(file.exists(input))){
    ids = rbindlist(lapply(input, arrow::read_parquet))
  }else if (is.function(input)){
    ids = input(...)
  }else if(is.data.frame(input)){
    ids = data.table(input) # copy input -- that's probably ok
  }

  # Convert to data table for processing
  data.table::setDT(ids)

  # Clean data ----
  ## Start by cleaning the names ----
  ## hyrule::clean_names is an opinionated way to clean names for linking.
  ## It seems to work relatively well, but its not essential to the process.
  ## Other methods may work as well/better and can be slotted in
  ids[, c('first_name_clean', 'middle_name_clean', 'last_name_clean') := lapply(.SD, hyrule::clean_names), .SDcols = c('first_name', 'middle_initial', 'last_name')]

  ## Remove spaces ----
  ## Spaces are removed because at some point in the past it seemed like a good idea
  ## It probably cuts down on higher string distances between otherwise similar entries due to typos
  rs = hyrule::remove_spaces # shortening to make it easier to type
  ids[, c('first_name_noblank', 'middle_name_noblank', 'last_name_noblank') :=
        list(rs(first_name_clean), rs(middle_name_clean), rs(last_name_clean))]

  ## Custom John Doe Logic ----
  ## Depending on the data set/data entry methods, there may be John/Jane Doe type placeholders
  ## It is generally best to set those names to NA to prevent spurrious linkages

  ## Remove bad/garbage names ----
  ## Sometimes, invalid names are in the data (e.g. REFUSED)
  ## It is good to remove those. "Bad" names can often by found by tabulating the frequency
  ## of names and seeing which appear most often.

  ## clean date of birth ----
  ids[, dob_clean := as.Date(date_of_birth, format = '%m/%d/%Y')]
  ids[year(dob_clean) > data.table::year(Sys.Date()) | year(dob_clean) < 1901, `:=` (dob_clean = NA)]

  ## clean gender/sex ----
  ## This code (and the variables built off this) look for explicit match on recorded gender
  ## In most models, gender is probably best used as a soft variable -- something to push a match over the edge
  ## but not something that'll determine a match strongly/or not, lest certain groups be undercounted/undermatched
  ## The code below enforces a gender binary (since that is all that is available in the test data),
  ## that is likely not reflective of all (or even most) data systems.
  ids[sex %in% c('Male', 'Female'), sex_clean := substr(sex, 1,1)]


  ## Placeholder for other data cleaning routines ----
  ## Below is some sample code to clean social security numbers (for example)
  # ids[, ssn_clean := stringr::str_remove_all(ssn, '\\D+')]
  # ids[, ssn_num := as.numeric(ssn_clean)]
  # ids[ssn_num >= 900000000 | ssn_num == 0 | ssn == 555555555 | nchar(ssn)<4, ssn_clean := NA] # nchar(ssn) != 9
  # rssn = sapply(0:8, function(s) paste(rep(s, 9), collapse = ''))
  # ids[ssn_num %in% rssn, ssn_clean := NA]
  # ids[!is.na(ssn_clean) & nchar(ssn_clean)>=7, ssn_clean := stringr::str_pad(ssn_clean, 9, 'left', '0')]
  # ids[, ssn_num := NULL]

  ## Depending on the case, location data can be handled here or separately (usually when you have a history of them)


  ## Remove rows with too little data ----
  ## After cleaning, the data density of some rows may be too low. This removes those rows
  ids = ids[, numna := rowSums(is.na(.SD)), .SDcols = c('first_name_noblank', 'middle_name_noblank', 'last_name_noblank', 'sex_clean', 'dob_clean')]
  ids = ids[numna<5]

  ## Fill in blanks ----
  ## The base unit of analysis is the unique combination of identifiers within a source id
  ## For example, a Robert Bland may sometimes show up as Rob or Bob.
  ## By linking at a finer resolution than source id, certain naming differences (and/or name/value changes) can be accounted for
  ## That said, source id (in the test data, the "id" column) still provides some information.
  ## As such, the next step fills in missing data when everything but one value is NA
  nms = c('dob_clean', 'sex_clean', 'first_name_noblank', 'middle_name_noblank', 'last_name_noblank')
  data.table::setorder(ids, source_id, first_name_noblank, last_name_noblank)
  ids[, (nms) := lapply(.SD, hyrule::fillblanks), .SDcols = nms, by = c('source_system', 'source_id')]

  # Keep only the required columns for matching ----
  ids = ids[, .(source_system, source_id, first_name_noblank, middle_name_noblank, last_name_noblank, sex_clean, dob_clean)]
  ids = unique(ids)

  # Create a hash id ----
  # Hashing rows of data creates a new id column nested within source_system and source_id
  # This allows for persistence between versions and data cleaning routines (e.g. the same data will create the same hash)
  ids[, clean_hash := hyrule::make_hash(.SD), .SDcols = c('source_system', 'source_id', 'first_name_noblank', 'middle_name_noblank', 'last_name_noblank', 'dob_clean', 'sex_clean')]


  # Save the data ----
  if(!is.null(output_file)){
    arrow::write_parquet(ids, output_file)
    return(output_file)

  }else{
    return(ids)
  }

}
