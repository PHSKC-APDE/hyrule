blocking_rules = c(
  'l.last_name_noblank = r.last_name_noblank',
  'l.dob_clean = r.dob_clean',
  "jaro_winkler_similarity(l.first_name_noblank, r.first_name_noblank) >.7
   and datepart('year', l.dob_clean) = datepart('year', r.dob_clean)"
  )

list(
  tarchetypes::tar_group_by(qgrid, 
                            command = make_block_rules(rules = blocking_rules),
                            qid)
)

