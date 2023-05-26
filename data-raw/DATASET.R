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

# fake ZIP codes
peeps = rbind(fake_one, fake_two)[, .(simulant_id)]
peeps = unique(peeps)

# population fractions for KC zips
# kcz = structure(list(geo_id = c("98117", "98122", "98126", "98068",
#                                 "98199", "98134", "98118", "98034", "98005", "98039", "98059",
#                                 "98104", "98144", "98033", "98019", "98108", "98056", "98031",
#                                 "98024", "98014", "98224", "98101", "98028", "98010", "98177",
#                                 "98115", "98042", "98077", "98065", "98045", "98288", "98125",
#                                 "98102", "98178", "98011", "98051", "98075", "98105", "98195",
#                                 "98007", "98040", "98070", "98112", "98027", "98133", "98022",
#                                 "98116", "98058", "98002", "98047", "98155", "98107", "98052",
#                                 "98004", "98006", "98168", "98001", "98029", "98106", "98030",
#                                 "98092", "98003", "98023", "98050", "98119", "98109", "98121",
#                                 "98057", "98148", "98074", "98136", "98166", "98188", "98032",
#                                 "98103", "98146", "98072", "98008", "98055", "98198", "98038",
#                                 "98053"), pop = c(0.0149, 0.0174, 0.011, 2e-04, 0.0099, 8e-04,
#                                                   0.0206, 0.0223, 0.0089, 0.0013, 0.0175, 0.0074, 0.0144, 0.018,
#                                                   0.0053, 0.0112, 0.0168, 0.0194, 0.0024, 0.0033, 0, 0.0071, 0.0105,
#                                                   0.0024, 0.009, 0.0234, 0.0219, 0.0059, 0.0069, 0.0068, 1e-04,
#                                                   0.0187, 0.0112, 0.0108, 0.0122, 0.0017, 0.0109, 0.0209, 0.0016,
#                                                   0.0127, 0.0113, 0.0048, 0.0097, 0.013, 0.0223, 0.0101, 0.0118,
#                                                   0.0194, 0.0178, 0.0032, 0.0158, 0.0125, 0.0328, 0.0167, 0.0177,
#                                                   0.0167, 0.016, 0.0133, 0.0117, 0.0175, 0.0221, 0.0235, 0.0237,
#                                                   1e-04, 0.0119, 0.0142, 0.0093, 0.0069, 0.0048, 0.0131, 0.0069,
#                                                   0.0103, 0.0118, 0.0169, 0.0229, 0.0133, 0.0108, 0.0116, 0.0108,
#                                                   0.0173, 0.0162, 0.0097)), row.names = c(NA, -82L), class = "data.frame")
# setDT(kcz)
# z = kcz[, sample(geo_id, size = nrow(peeps), replace = T, prob = pop)]
# peeps[, zip := z]
# peeps[, zip2 := z]

usethis::use_data(fake_one, overwrite = TRUE)
usethis::use_data(fake_two, overwrite = TRUE)
