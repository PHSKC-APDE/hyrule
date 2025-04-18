#' Load and standardize training pairs and compute training data
#' @param input file paths to training data. Must be csv or parquet file
#' @param output_file file path to a parquet file where the output will be saved
#' @param formula formula specifying the predictor variables
#' @param data file path to a parquet file containing the data
#' @param loc_history file path to location history file
#' @param zip_history file path to zip history parquet file
#' @param freq_tab_first_name file path to frequency table for first names parquet file
#' @param freq_tab_last_name file path to frequency table for last names parquet file
#' @param freq_tab_dob file path to frequency table for dob parquet file
compile_training_data = function(input,
                                 output_file,
                                 formula,
                                 data,
                                 loc_history, zip_history,
                                 freq_tab_first_name, freq_tab_last_name, freq_tab_dob){


  # Load the pairs
  train = lapply(input, function(f){
    fe = tools::file_ext(f)
    if(fe == 'rds'){
      return(readRDS(f))
    } else if (fe == 'csv'){
      return(data.table::fread(f))
    } else if (fe == 'parquet'){
      return(arrow::read_parquet(f))
    } else{
      stop(paste(fe, 'is an invalid file format'))
    }
  })

  # Standardize and deduplicate
  train = data.table::rbindlist(train, fill = T)[, .(id1, id2, pair)]
  train[id1>id2, c('id1', 'id2') := list(id2, id1)]
  train = train[, .(pair = last(pair)), .(id1,id2)]
  train <- train[pair %in% c(0,1),]
  stopifnot(!anyNA(train))
  train <- unique(train)
  train = train[id1 != id2]

  stopifnot(nrow(train) == nrow(unique(train[, .(id1, id2)])))

  # Create a semi-persistent duckdb at this level to store the training data an execute the query from make model frame
  ddb = DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(ddb, shutdown = TRUE))
  duckdb::duckdb_register(ddb, name = 'train', df = train, overwrite = T)
  loadspatial(ddb)

  # Generate model frame query
  mmf = make_model_frame(
    pairs = DBI::Id(table = 'train'),
    data = data,
    lh = loc_history,
    zh = zip_history,
    ft_first = freq_tab_first_name,
    ft_last = freq_tab_last_name,
    ft_dob = freq_tab_dob
  )

  # Compute model frame
  fitme = data.table::setDT(DBI::dbGetQuery(ddb, mmf))
  stopifnot(nrow(fitme) == nrow(unique(fitme[, .(id1, id2)])))

  # Find the number of training pairs that don't have a hash in r
  droppers = nrow(train) -  nrow(fitme)

  if((droppers)/nrow(train) >.25) stop(paste0(round((droppers)/nrow(train)*100),'% of labelled pairs have no corrosponding data'))

  # Drop rows with missing
  vvv = attr(terms(formula), 'term.labels')
  start = nrow(fitme)
  fitme = na.omit(fitme, cols = vvv)
  frac = nrow(fitme)/start
  if(nrow(fitme) != start) warning(paste(start - nrow(fitme), 'rows dropped'))
  if(frac<.75 || frac>1) stop(paste0(round(frac,2), ' is the proportion of final rows relative to starting rows'))

  fitme[, pair := factor(pair, 0:1, as.character(0:1))]
  setorder(fitme, id1, id2)
  if(!is.null(output_file)){
    arrow::write_parquet(fitme, output_file)
    return(output_file)
  }else{
    return(fitme)
  }


}

#' Split the data
#' @param hash hash of the training data
#' @param training_data file path to the training data parquet file
#' @param fraction proportion of the data to be held as a training dataset
#' @param train_of parquet file path to store the training data
#' @param test_of parquet file path to store the test data
split_tt = function(hash, training_data, fraction = .15, train_of, test_of){
  d = setDT(read_parquet(training_data))
  idx = sample(seq_len(nrow(d)),size = floor(nrow(d) * fraction))

  if(!is.null(train_of) && !is.null(test_of)){
    arrow::write_parquet(d[idx,], test_of)
    arrow::write_parquet(d[-idx,], train_of)
    return(c(test = test_of,train = train_of))

  }else{
    return(list(test = d[idx,], train = d[-idx]))
  }


}
