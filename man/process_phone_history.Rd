% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/process_phone_history.R
\name{process_phone_history}
\alias{process_phone_history}
\title{Create phone number related variables for linkage}
\usage{
process_phone_history(
  pairs,
  ph1,
  id1,
  ph2,
  id2,
  default_phone_dist = 6,
  default_mxn = 1.5
)
}
\arguments{
\item{pairs}{data.frame/data.table of record pairs to generate variables for. Must include two id columns (specified by `id1` and `id2` arguments) for `d1` and `d2`}

\item{ph1}{data.frame/data.table with (at least) two columns: `id1` and phone_number. A given id can have multiple numbers associated with it. Ideally, includes the whole phone history and not just those limited to `pairs`}

\item{id1}{character. Column name identifying a ID column in `id1`. Also must exist in `pairs` and `xy1` and `xy1`, if using.}

\item{ph2}{data.frame/data.table with (at least) two columns: `id2` and phone_number. A given id can have multiple numbers associated with it. Ideally, includes the whole phone history and not just those limited to `pairs`}

\item{id2}{character. Column name identifying a ID column in `id2`. Also must exist in `pairs` and `xy2` and `xy2`, if using.}

\item{default_phone_dist}{numeric. Default dl (see stringdist::stringdist) distance when one of a pair of numbers is missing}

\item{default_mxn}{numeric. Default max N at number value when missing. Represent number of people associated with phone number. Default value of 1.5 is chosen arbitrarily}
}
\description{
Create phone number related variables for linkage
}
