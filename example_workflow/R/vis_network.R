#' Visualize a network
#' @param nodes a dataframe containing information on the nodes
#' @param edges a data frame containing info on the edges
#' @param tooltip_cols a vector of the columns in nodes to display in the resulting graph
#' @param labels either character vector of the column(s) in nodes to color by OR a (list) network clustering function
#' 
vis_network = function(nodes, edges, tooltip_cols = c('pname', 'dob_clean', 'clean_hash', 'source_system', 'source_id'), labels = 'nest_id', title = '', return_data = F){
  stopifnot(all(nodes$clean_hash %in% unique(c(edges$id1, edges$id2))))
  # augment links
  graph = igraph::graph_from_data_frame(edges[, .(id1, id2, weight = final)], F, vertices = nodes[, .(name = clean_hash)])
  
  gdf = intergraph::asDF(graph)
  gdf$vertexes$intergraph_id = as.numeric(gdf$vertexes$intergraph_id)
  gnet = network::as.network(gdf$edges, directed = F, vertices = gdf$vertexes)
  
  # convert to ggnet
  # Mostly for the vertex locations
  g = GGally::ggnet2(gnet)
  
  # make node tooltips
  ntt = lapply(labels, function(l){
    nodes[, .(name = as.character(clean_hash), 
             lab = get(l), 
             lab_col = l, 
             text = apply(.SD, 1, function(t) paste(unlist(t), collapse = '<br>'))), .SDcols = tooltip_cols]
  })
  
  ntt = rbindlist(ntt)
  
  # Extract the data frames
  vdat = setDT(g$data)
  vdat = merge(vdat, gdf$vertexes, all.x = T, by.x = 'label', by.y ='intergraph_id')
  vdat = merge(vdat, ntt, all.x = T, by = 'name')
  
  edat = merge(gdf$edges, unique(vdat[, .(V1 = label, X1 = x, Y1 = y)]), all.x = T, by = 'V1')
  setDT(edat)
  edat = merge(edat, unique(vdat[, .(V2 = label, X2 = x, Y2 = y)]), all.x = T, by = 'V2')
  edat[, midX := (X1 + X2)/2]
  edat[, midY := (Y1 + Y2)/2]
  
  g2 = ggplot(vdat) +
    geom_segment(data = edat, aes(x = X1, xend = X2, y = Y1, yend = Y2, color = weight), linewidth = 1) +
    geom_point(aes(x = x, y = y, text = text, fill = factor(lab)), color = 'transparent', shape = 21, size = 9) +
    geom_point(data = edat, aes(x = midX, y = midY, text = weight, color = weight), size = 3) + 
    theme_void() +
    scale_color_distiller(palette = 'YlOrRd', direction = 1, name = 'Weight', limits = c(.3,1)) +
    scale_fill_brewer(name = 'Cluster', type = 'qual') +
    theme(panel.background = element_rect(fill = 'gray10')) +
    ggtitle(title)
    facet_wrap(~lab_col)
  
  
  if(return_data){
    return(list(g2, list(vdat, edat)))
  }
  
  plotly::ggplotly(g2, tooltip = 'text')

  
  
}

#' Retrieve network info
#' @param net_id_val id of the network to pull
#' @param net_id_col id column in net_tab
#' @param net_id_tab table listing the id <-> net id relationship
#' @param cutpoint value to limit links by
#' @param result_tab table with the 1:1 links
#' @param identifier_tab table containing identifiers
retrieve_network_info = function(net_id_val, net_id_col, net_tab, result_tab, cutpoint, identifier_tab){
  
  # a duckdb to execute the sql through
  ddb = DBI::dbConnect(duckdb::duckdb())
  
  # For now, assuming result_tab and identifier tab are links to parquet files
  result_tab = parquet_to_ddb(unlist(result_tab))
  
  # Start by selecting the ids (e.g. hash ids or whatever) that make up network
  q1 = glue::glue_sql('Select * from
                      {`net_tab`} as nt
                      where {`net_id_col`} = {net_id_val}',.con = ddb)

  # Retrieve the relevant links
  q2 = glue::glue_sql('
                       select id1, id2, final from {`result_tab`} as r
                       left join (
                                  select distinct clean_hash from {`net_tab`}
                                  where {`net_id_col`} = {net_id_val}) as l1 on l1.clean_hash = r.id1
                       left join (
                                  select distinct clean_hash from {`net_tab`}
                                  where {`net_id_col`} = {net_id_val}) as l2 on l2.clean_hash = r.id2
                       where
                       l1.clean_hash IS NOT NULL and
                       l2.clean_hash IS NOT NULL AND
                       final >= {cutpoint}
                       
                       ',.con = ddb)
  
  node_start = setDT(dbGetQuery(ddb, q1))
  
  edge_start = setDT(dbGetQuery(ddb, q2))
  
  # add some relevant columns to the node df
  duckdb::duckdb_register(ddb, 'ns', node_start)
  on.exit(duckdb::duckdb_unregister(ddb, 'ns'))
  
  node_end = dbGetQuery(ddb, glue::glue_sql('select l.*, r.first_name_noblank, r.middle_name_noblank, r.last_name_noblank, r.dob_clean from ns as l
                                            left join {`identifier_tab`} as r on l.clean_hash = r.clean_hash
                                            ',.con = ddb))
  setDT(node_end)
  
  node_end[, c('first_name_noblank', 'middle_name_noblank', 'last_name_noblank') := lapply(.SD, function(x){
    x[is.na(x)] <- ''
    x
  }), .SDcols = c('first_name_noblank', 'middle_name_noblank', 'last_name_noblank')]
  node_end[, pname := paste(first_name_noblank, middle_name_noblank, last_name_noblank)]
  return(list(nodes = node_end, edges = edge_start))
  
  
}