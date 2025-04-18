compile_links = function(..., data, id_col = 'clean_hash', cutpoint, output_folder, method = 'leiden', min_N = 15, max_density = .4, recursive = FALSE){
  dots = list(...)

  if(!is.data.frame(dots[[1]]) && !inherits(dots[[1]], 'Id')){
    dots = unlist(dots)
    links = lapply(dots, function(x){
      if(is.character(x) && tools::file_ext(x) == 'rds'){
        r = readRDS(x)
      }
      if(is.character(x) && tools::file_ext(x) == 'parquet'){
        r = arrow::read_parquet(x)
      }
      data.table::setDT(r)
      r = r[final >= cutpoint]
      r
    })
    links = rbindlist(links)[, .(id1, id2, weight = final)]
  }else if(inherits(dots[[1]], 'Id')){
    con = hhsaw()
    on.exit(dbDisconnect(con))

    links = setDT(dbGetQuery(con, glue::glue_sql('select id1, id2, final as weight from {`dots[[1]]`} where final>= {cutpoint}', .con = con)))

  }else{
    links = dots[[1]][final >= cutpoint, .(id1, id2, weight = final)]
  }

  # Add source id and source system to the links
  ddb = DBI::dbConnect(duckdb::duckdb())
  duckdb::duckdb_register(ddb, 'links', links, overwrite = T)
  dat_tab = data
  lid = DBI::Id(schema = 'd1', table = id_col)
  rid = DBI::Id(schema = 'd2', table = id_col)
  links = dbGetQuery(ddb, glue::glue_sql(.con = ddb,
                     "
                     select l.id1, l.id2, l.weight,
                     concat(d1.source_system, '|', d1.source_id) as bid1,
                     concat(d2.source_system, '|', d2.source_id) as bid2
                     from links as l
                     left join {`dat_tab`} as d1 on l.id1 = {`lid`}
                     left join {`dat_tab`} as d2 on l.id2 = {`rid`}

                     "))
  setDT(links)

  # Collapse to source_system, source_id level
  clinks = links[, .(weight = max(weight)), .(bid1, bid2)]
  clinks[bid1>bid2, c('bid1', 'bid2') := list(bid2, bid1)]
  rm(links)

  # Step 1, find initial (raw) clusters
  g = igraph::graph_from_data_frame(clinks[, .(bid1, bid2, weight)], directed = F)
  g = igraph::simplify(g)

  s1_comp = components(g)
  s1_comp = data.table(id = names(s1_comp$membership), s1_comp_id = as.character(s1_comp$membership))

  # step 1.5, compute some initial statistics
  decomp = igraph::decompose(g)

  # decomp = lapply(seq_along(decomp), function(x) graph_attr(decomp[[x]], 's1_id') = x )
  s1_density = vapply(decomp, edge_density, .1)
  s1_len = vapply(decomp, length, 1)
  s1_sum = data.table(s1_comp_id = as.character(seq_along(s1_density)), s1_density = round(s1_density, 3), s1_size = s1_len)

  # Step 2, do some light clustering
  clusterer = function(graph, recursive = FALSE, method = 'leiden'){ #min_V = 4, min_density = .3
    # if(length(V(graph))<= min_V || edge_density(graph)<=min_density) return(graph)
    d = edge_density(graph)
    len = length(graph)

    if(!(len>=4 & d <= .8)) return(graph)

    # cg = match.fun(method)(g)
    cg = igraph::cluster_leiden(graph, objective_function = 'modularity', n_iterations = 10)

    if(length(cg)==1) return(graph)

    sgs = lapply(communities(cg), function(nm) subgraph(graph, V(graph)[name %in% nm]))

    if(recursive){
      return(lapply(sgs, clusterer, recursive = recursive))
    } else{
      return(sgs)
    }
  }

  clusme = which(s1_len>=min_N & s1_density <= max_density)

  reclus = lapply(decomp[clusme], clusterer, recursive = recursive)
  names(reclus) <- as.character(clusme)

  # flatten
  iter = 0
  while(!all(vapply(reclus, is.igraph, T)) & iter <10){
    reclus = purrr::list_flatten(reclus)
    iter = iter + 1
  }

  # combine
  names(decomp) <- as.character(seq_along(decomp))
  decomp = decomp[-clusme]
  decomp = append(decomp, reclus)

  # Create the initial pass of component summaries as data frames
  cids = lapply(seq_along(decomp), function(i){
    r = as_data_frame(decomp[[i]], 'vertices')
    #setDT(r)
    r$id = names(decomp)[[i]]
    r
  })

  cids = rbindlist(cids)
  cids[, c('source_system', 'source_id') := tstrsplit(name, split = '|', fixed = T)]
  cids[, name := NULL]


  cids[, first_level_id := tstrsplit(id, split = '_', fixed = T, keep = 1)]

  # Compute metrics for the final clusters
  rm(decomp)
  recompute = cids[id!=first_level_id]
  recompute[, bid := paste0(source_system, '|', source_id)]

  # Note: this could explode, so we add a upper limit to ids
  # this could be "fixed" by converting BIDs to numeric to do the < as poart of the merge
  stopifnot(recompute[, length(unique(id))]<1000)
  posspairs = recompute[recompute, .(bid1 = i.bid, bid2 = x.bid, id), on = .(id=id), allow.cartesian = T]
  posspairs = posspairs[bid1<bid2]
  posspairs = merge(posspairs, clinks, by = c('bid1', 'bid2'))
  posspairs = split(posspairs, by = 'id')

  decomp = lapply(posspairs, function(x) igraph::graph_from_data_frame(x[, .(bid1, bid2, weight)], directed = F))

  # decomp = lapply(seq_along(decomp), function(x) graph_attr(decomp[[x]], 's1_id') = x )
  s2_density = vapply(decomp, edge_density, .1)
  s2_len = vapply(decomp, length, 1)
  s2_sum = data.table(s2_comp_id = names(posspairs), s2_density = round(s2_density, 3), s2_size = s2_len)
  s2_sum[, s1_comp_id := tstrsplit(s2_comp_id, split = '_', fixed = T, keep = 1)]
  ovr_sum = merge(s1_sum, s2_sum, all.x = T, by = 's1_comp_id')
  ovr_sum[, c('final_comp_id', 'final_density', 'final_size') := list(s2_comp_id, s2_density, s2_size)]
  ovr_sum[is.na(final_comp_id), c('final_comp_id', 'final_density', 'final_size') := list(s1_comp_id, s1_density, s1_size)]

  # add main id to cids
  duckdb::duckdb_register(ddb, 'cids', cids, overwrite = T)
  lid2 = DBI::Id(schema = 'l', column = id_col)
  cids = setDT(dbGetQuery(ddb,
                          glue_sql(.con = ddb,
                                   'select {`lid2`}, r.* from {`dat_tab`} as l
                                   inner join cids as r on l.source_system = r.source_system and l.source_id = r.source_id')))
  setnames(cids, 'id', 'final_comp_id')

  if(!is.null(output_folder)){
    arrow::write_parquet(cids, file.path(output_folder, 'cids.parquet'))
    arrow::write_parquet(ovr_sum, file.path(output_folder, 'ovr_sum.parquet'))
    return(c(file.path(output_folder, 'cids.parquet'), file.path(output_folder, 'ovr_sum.parquet')))
    return(output_file)

  }else{
    return(list(cids, ovr_sum))
  }




}
