library('hyrule')
library('duckdb')
library('DBI')
library('dbplyr')
 first_name = 'first_name'
 middle_name = 'middle_initial'
 last_name = 'last_name'
 dob = 'data_of_birth'
 ssn = NULL
 sex = 'sex'
 id = 'id1'

 d = hyrule::fake_one
 ddb = DBI::dbConnect(duckdb::duckdb())
 dbWriteTable(ddb, 'df', d)

 d = new_hyrule_data(ddb, 'df')
