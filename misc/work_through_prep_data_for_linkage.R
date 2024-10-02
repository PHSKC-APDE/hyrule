library('hyrule')
library('duckdb')
library('DBI')
library('dplyr')
library('dbplyr')
first_name = 'first_name'
middle_name = 'middle_initial'
last_name = 'last_name'
dob = 'date_of_birth'
ssn = NULL
sex = 'sex'
id = 'id1'

 d = hyrule::fake_one
 ddb = DBI::dbConnect(duckdb::duckdb())
 dbWriteTable(ddb, 'df', d)

 dbt = tbl(ddb, 'df')

 a = data.frame(old = 'Black', new = 'b')

b =  dbt |> left_join(a, by = join_by(race_ethnicity == old), copy = T) |>
   collect()
