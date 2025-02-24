#' Create a grid of blocking rules
#' @param rules character. A set of sql statements defining the blocking rules
make_block_rules = function(rules){
  ddb = DBI::dbConnect(duckdb::duckdb())
  loadspatial(ddb)

  # Validate the rules
  stopifnot(is.character(rules))


  # Identify the complex rules
  cplex_funcs = c('contains', 'jaccard', 'jaro', 'st_distance')
  cplex = lapply(cplex_funcs, function(r){
    grep(r, tolower((rules)), fixed = T)
  })
  cplex = unique(unlist(cplex))
  simple = rules[-cplex]

  rules = data.frame(rrr = c(simple, rules[cplex]), type = 'base')

  simple = paste0('coalesce((', simple, '), false)')
  subsetter = paste(simple, collapse = ' OR ')
  subsetter =  paste0('AND NOT (', subsetter, ')')

  match_rules = list(rules)

  grids = lapply(match_rules, function(y) setnames(y, setdiff(names(y), 'type'), letters[seq_len(ncol(y)-1)]))
  grids = rbindlist(grids, fill = T)

  grids[, qid := .I]
  grids = melt(grids, c('qid', 'type'))
  grids = grids[!is.na(value)]

  qgrid = grids[, glue::glue_sql_collapse(value, sep = ' AND '), .(qid,type)]
  qgrid[, V1:= glue_sql('({V1})', .con = con)]

  qgrid[, where := SQL('')]
  for(cp in cplex_funcs){
    qgrid[grep(cp, tolower(V1)), where := DBI::SQL(subsetter)]

  }


  qgrid
}

#' Identify rows fufilling a blocking condition
#' @param q a single row data.frame produced by make_block_rules
#' @param data file.path to the parquet file with the data (must have columns specified in the block rules)
#' @param id_col character. id column in data
#' @param deduplicate logical. Whether within source_system matches should be evaluated
#' @param output_folder file path to the folder where outputs should be saved
make_block = function(q, data, id_col, deduplicate = TRUE, output_folder){
  stopifnot(file.exists(data))
  stopifnot(tools::file_ext(data) == 'parquet')
  ddb = DBI::dbConnect(duckdb::duckdb())

  qry = q$V1
  i = q$qid
  whr = q$where

  if(grepl('st_', qry,fixed = T)) loadspatial(ddb)
  if(!deduplicate){
    dedup = SQL('and l.source_system != r.source_system')
  }else{
    dedup = SQL('')
  }
  stopifnot(length(i) == 1)

  # load identities
  # a = load_parquet_to_ddb_table(ddb, identities, DBI::Id(table = 'ems'))
  #
  ltab = data
  rtab = data
  lid = DBI::Id(schema = 'l', column = paste0(id_col))
  rid = DBI::Id(schema = 'r', column = paste0(id_col))

  output = file.path(output_folder, paste0('qry_',i,'.parquet'))
  r <- glue::glue_sql("
    copy (
      select
      {`lid`} as id1,
      l.source_system as ss1,
      {`rid`} as id2,
      r.source_system as ss2,
      {i} as qid
      from {`ltab`} as l
      inner join {`rtab`} as r
      on {qry}
      where
      1 = 1
      and (concat(l.source_system, l.source_id) != concat(r.source_system, r.source_id))
      and {`lid`} < {`rid`}
      {dedup}
      {whr}
      order by 1
    ) TO {output} (FORMAT 'parquet');

  ", .con = ddb)

  e = dbExecute(ddb, r)

  return(output)


}
#' Compile the rows to evaluate for matchiness
#' @param blocks
compile_blocks = function(blocks, output_folder, chk_size = 1000000){
  ddb = DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(ddb, shutdown = TRUE))

  target = DBI::Id(table = paste0('blocks'))

  # Add the rows
  p_files = glue_sql_collapse(paste0("'", blocks,"'"), sep = ', ')
  pq = glue::glue_sql('create or replace table {`target`} as
                      select distinct id1, id2, ss1, ss2 from read_parquet([{p_files}])
                      ', .con = ddb)
  DBI::dbExecute(ddb, pq)

  # overall row ID for blocks
  dbExecute(
    ddb,
    glue::glue_sql(
      "
       DROP SEQUENCE if exists bid_seq CASCADE;
       CREATE SEQUENCE if not exists bid_seq START 1;
       alter table {`target`} add column bid bigint default nextval('bid_seq');
       ",
      .con = ddb
    )
  )

  minmax = dbGetQuery(ddb, 'select max(bid) as mx, min(bid) as mn from blocks')
  sss = seq(minmax$mn, minmax$mx, chk_size)
  outfiles = c()
  for(i in seq_along(sss)){
    output_file = file.path(output_folder, paste0('blk_', i, '.parquet'))
    outfiles[i] <- output_file
    dbExecute(ddb,
              glue::glue_sql("
                           copy(
                           select * from {`target`} where bid >= {sss[i]} and bid < {sss[i] + chk_size}
                           ) TO {output_file} (FORMAT 'parquet');
                           ",.con = ddb))
  }

  outfiles
}
