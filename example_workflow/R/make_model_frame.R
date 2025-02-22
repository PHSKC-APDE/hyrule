#' Create a modelling ready dataframe
#' @param pairs file path to a parquet file (or existing table within ddb) containing the pairs to evaluate (e.g. id1, id2)
#' @param data parquet file with data
#' @param lh parquet file with location history
#' @param zh parquet file with zip code history
#' @param ft_first parquet file with the frequency tabulations for first name
#' @param ft_last parquet file with the frequency tabulations of last name
#' @param ft_dob parquet file with the dob frequency tabulation
#' @param meter_conversion numeric a scalar to convert distance calculations between entries in the location history to meters
make_model_frame = function(pairs, data, lh, zh, ft_first, ft_last, ft_dob){

  # Create a duckdb
  ddb = DBI::dbConnect(duckdb::duckdb())
  loadspatial(ddb)

  # Note -- it might be worth preloading things into duckdb depending on speed and storage needs

  # SQL to create the various variables
  # dob_year_exact: exact match of year of birth
  dob_year_exact = SQL('IF(year(l.dob_clean) = year(r.dob_clean), 1, 0) as dob_year_exact')

  # dob_mdham: hamming distance between month and day of birth
  dob_mdham = SQL('least(hamming(substr(cast(l.dob_clean as varchar), 6, 5), substr(cast(r.dob_clean as varchar), 6, 5))/4, 1) as dob_mdham')

  # gender_agree: gender explicitly matches
  gender_agree = SQL('IF(l.sex_clean = r.sex_clean, 1, 0) as gender_agree')

  # first_name_jw: jaro-winkler distance of first names
  first_name_jw = SQL('least(1-jaro_winkler_similarity(r.first_name_noblank, l.first_name_noblank),1) as first_name_jw')

  # last_name_jw: jaro-winkler distance of last names
  last_name_jw = SQL('least(1-jaro_winkler_similarity(r.last_name_noblank, l.last_name_noblank), 1) as last_name_jw')

  # name_swap_jw: jaro-winkler distance of names with first and last swapped
  name_swap_jw = SQL('
      least(
        1 - jaro_winkler_similarity(r.first_name_noblank, l.last_name_noblank),
        1 - jaro_winkler_similarity(r.last_name_noblank, l.first_name_noblank),
        1
      ) as name_swap_jw
                     ')
  # complete_name_dl: daimaru-levenstein distance between the full names. Full name is either first + last or first + middle + last. The minimum distance of the two versions is used.
  complete_name_dl = SQL('
    least(
        damerau_levenshtein(
          concat(l.first_name_noblank, l.middle_name_noblank, l.last_name_noblank),
          concat(r.first_name_noblank, r.middle_name_noblank, r.last_name_noblank)
        )/greatest(
          len(concat(l.first_name_noblank, l.middle_name_noblank, l.last_name_noblank)),
          len(concat(r.first_name_noblank, r.middle_name_noblank, r.last_name_noblank))
        ),
        damerau_levenshtein(
          concat(l.first_name_noblank, l.last_name_noblank),
          concat(r.first_name_noblank, r.last_name_noblank)
        )/greatest(
          len(concat(l.first_name_noblank, l.last_name_noblank)),
          len(concat(r.first_name_noblank, r.last_name_noblank))
        )
     ) as complete_name_dl
                         ')
  # middle_initial_agree: Explicit match of middle initial
  middle_initial_agree = SQL('
      IF(left(l.middle_name_noblank,1) = left(r.middle_name_noblank,1), 1, 0) as middle_initial_agree
                             ')
  # last_in_last: where either records whole last name is contained in the other one
  last_in_last = SQL('if(contains(l.last_name_noblank, r.last_name_noblank) OR contains(r.last_name_noblank, l.last_name_noblank), 1, 0) as last_in_last')

  # first_name_freq: Scaled frequency tabulation of first names
  first_name_freq = SQL('greatest(fnf1.first_name_noblank_freq, fnf2.first_name_noblank_freq, 0) AS first_name_freq')

  # last_name_freq: Scaled frequency tabulation of last names
  last_name_freq = SQL('greatest(lnf1.last_name_noblank_freq, lnf2.last_name_noblank_freq, 0) as last_name_freq')

  # basic variables cte
  vars = glue_sql_collapse(c(dob_year_exact, dob_mdham, gender_agree, first_name_jw, last_name_jw,
                             name_swap_jw, complete_name_dl, middle_initial_agree, last_in_last, first_name_freq, last_name_freq), sep = ',')
  dat_cte = glue_sql(.con = ddb,"
     select p.*,
     {vars}

     from {`pairs`} as p
     left join {`data`} as l on p.id1 = l.clean_hash
     left join {`data`} as r on p.id2 = r.clean_hash
     left join {`ft_first`} as fnf1 on l.first_name_noblank = fnf1.first_name_noblank
     left join {`ft_first`} as fnf2 on r.first_name_noblank = fnf2.first_name_noblank
     left join {`ft_last`} as lnf1 on l.last_name_noblank = lnf1.last_name_noblank
     left join {`ft_last`} as lnf2 on r.last_name_noblank = lnf2.last_name_noblank
     left join {`ft_dob`} as df1 on l.dob_clean = df1.dob_clean
     left join {`ft_dob`} as df2 on r.dob_clean = df2.dob_clean
     where l.clean_hash IS NOT NULL AND r.clean_hash is not null"
                     )


  # zip_overlap: whether the two zip code histories overlap
  zip_cte = glue::glue_sql("
      select
      p.id1
     ,p.id2
     ,max(case
          when a1.zip_code = a2.zip_code then 1
          when a1.zip_code IS NULL OR a1.zip_code = '' then -1
          when a2.zip_code IS NULL or a2.zip_code = '' then -1
          else 0 end) as zip_overlap
     from {`pairs`} as p
     left join {`data`} as h1 on p.id1 = h1.clean_hash
     left join {`data`} as h2 on p.id2 = h2.clean_hash
     left join {`zh`} as a1 on h1.source_id = a1.source_id AND h1.source_system = a1.source_system
     left join {`zh`} as a2 on h2.source_id = a2.source_id AND h2.source_system = a2.source_system
     group by p.id1, p.id2
                        ", .con = ddb)
  # exact_location: binary flag indicating address histories overlap within 3 meters (location only – not spatio-temporal).
  el_cte = glue::glue_sql("
    select
      p.id1
     ,p.id2
     ,min(st_distance(st_point(a1.X, a1.Y), st_point(a2.X, a2.Y))) as ah_min_distance -- to meter
     from {`pairs`} as p
     left join {`data`} as h1 on p.id1 = h1.clean_hash
     left join {`data`} as h2 on p.id2 = h2.clean_hash
     left join {`lh`} as a1 on h1.source_id = a1.source_id AND h1.source_system = a1.source_system
     left join {`lh`} as a2 on h2.source_id = a2.source_id AND h2.source_system = a2.source_system
     where a1.X IS NOT NULL and a2.X IS NOT NULL
     group by p.id1, p.id2
                       ", .con = ddb)


  # Pull main demographics

  q_ans = glue::glue_sql("
                 with demo as ({dat_cte})
                 ,zip as ({zip_cte})
                 ,ads as ({el_cte})
                 select
                 dt.*
                 ,least(zt.zip_overlap, 0) as zip_overlap
                 ,if(at.ah_min_distance <10, 1 , 0) as exact_location
                 ,if(zt.zip_overlap IS NULL OR zt.zip_overlap<0, 1, 0) as missing_zip
                 ,if(at.ah_min_distance IS NULL, 1, 0) as missing_ah
                 from demo as dt
                 left join zip as zt on dt.id1 = zt.id1 AND dt.id2 = zt.id2
                 left join ads as at on dt.id1 = at.id1 AND dt.id2 = at.id2

                ", .con = ddb)

}
#

