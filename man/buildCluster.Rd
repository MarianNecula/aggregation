% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/buildCluster.R
\name{buildCluster}
\alias{buildCluster}
\title{Builds a cluster of working nodes.}
\usage{
buildCluster(varlist, env)
}
\arguments{
\item{varlist}{A list of variables to be exported to every working node.}

\item{env}{An environment to be exported to every working node.}
}
\value{
A cluster object used to distribute the computations.
}
\description{
Builds a cluster of working nodes using the \code{parallel}
  package. On Unix-like operating systems it builds as "FORK" cluster while
  on Windows it builds a "SOCKET" cluster. The number of working nodes equals
  the number of available (logical) cores as it is detected by the call of
  \code{detectCores()} function. On Windows, it also exports a list of
  variables and an environment passed as arguments. This is an internal
  function of the package, and it is not available to be direclty called by
  users.
}
