## Use the psuedo people package to generate some test data
library('reticulate')
library('data.table')
psp = import('pseudopeople')

# Load the config file for the decennial census
config <-psp$get_config('decennial_census')
def_config = config
# get the default dataset
default = psp$generate_decennial_census(seed = 1L)

# change how the error is

config$row_noise$omit_row$row_probability <- .04
config$column_noise$first_name$make_typos$cell_probability <- .1
config$column_noise$last_name$make_typos$cell_probability <- .1
config$column_noise$last_name$use_fake_name = 0L


con3 = list(decennial_census =
              list(row_noise = list(omit_row = list(row_probability = .04)),
                   column_noise = list(first_name = list(make_typos = list(cell_probability = .1)),
                                       last_name = list(make_typos = list(cell_probability = .1)))))

uno = psp$generate_decennial_census(seed = 1L, config = con3) # file.path(getwd(), 'data-raw/psp_config.yml')
dos = psp$generate_decennial_census(seed = 100L, config = con3)
setDT(uno); setDT(dos);
uno = uno[, lapply(uno, unlist)]
dos = dos[, lapply(dos, unlist)]

# fix NaNs
for(col in names(uno)){
  if(inherits(uno[[col]], 'character')){
    uno[get(col) == 'NaN', (col) := NA_character_]
  }
}
# fix NaNs
for(col in names(dos)){
  if(inherits(dos[[col]], 'character')){
    dos[get(col) == 'NaN', (col) := NA_character_]
  }
}

fake_one = uno
fake_two = dos

fake_one[, date_of_birth := as.Date(date_of_birth, '%m/%d/%Y')]
fake_two[, date_of_birth := as.Date(date_of_birth, '%m/%d/%Y')]

usethis::use_data(fake_one, overwrite = TRUE)
usethis::use_data(fake_two, overwrite = TRUE)
