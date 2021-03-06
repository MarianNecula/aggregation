#' @title Generates random values according to a Poisson multinomial probability
#'   distribution.
#'
#' @description Generates random values according to a Poisson multinomial
#'   probability distribution. A point estimation derived from this distribution
#'   (mean, mode) represents an estimation of the number of individuals detected
#'   by the network in a region. Regions are composed as a number of adjacent
#'   tiles. This is the only one function of this package available to users to
#'   compute an estimation of the number of detected individuals.
#'
#' @param n The number of random values to be generated.
#'
#' @param gridFileName The name of the .csv file with the grid parameters.
#'
#' @param dupFileName The name of the .csv file with the duplicity probability
#'   for each device. This is an output of the \code{deduplication} package.
#'
#' @param regsFileName The name of the .csv file defining the regions. It has
#'   two columns: \code{ tile, region}. The first column contains the IDs of
#'   each tile in the grid while the second contains the number of a region.
#'   This file is defined by the user and it can be created with any text
#'   editor.
#'
#' @param postLocPath The path where the files with the posterior location
#'   probabilities for each device can be found. A file with the location
#'   probabilities should have the name \code{prefix_ID.csv} where \code{ID} is
#'   replaced with the device ID and \code{prefix} is given as a parameter to
#'   this function.
#'
#' @param prefix A prefix that is used to compose the file name with posterior
#'   location probabilities.
#'
#' @param times An optional vector with the time instants when the events were
#'   registered. If it is not provided, in the output, the succesive time
#'   instants will be represented by thier index (starting from 1).
#'
#' @return A data.table object with the following columns: \code{time, region,
#'   N, iter}. The last column contains the index of the random value (given in
#'   column \code{N}) generated for each time instant and region.
#'
#' @import data.table
#' @import deduplication
#' @import  parallel
#' @include doAggr.R
#' @export
rNnetEvent <- function(n, gridFileName, dupFileName, regsFileName, postLocPath, prefix, times = NULL) {
  # 1. read duplicity probs.

  if (!file.exists(gridFileName))
    stop(paste0(gridFileName, " does not exists!"))
  
  gridParams <- readGridParams(gridFileName)
  
  if (!file.exists(dupFileName))
    stop(paste0(dupFileName, " does not exists!"))
  
  dupProbs <- fread(
    dupFileName,
    sep = ',',
    header = TRUE,
    stringsAsFactors = FALSE
  )
  devices<-sort(as.numeric(dupProbs[,1][[1]]))
  
  # 2. read regions
  if (!file.exists(regsFileName))
    stop(paste0(regsFileName, " does not exists!"))
  
  regions <- fread(
    regsFileName,
    sep = ',',
    header = TRUE,
    stringsAsFactors = FALSE
  )
  
  # 3. read posterior location probabilities
  ndevices <- nrow(dupProbs)
  postLoc<-list(length = ndevices)
  for( i in 1:ndevices) {
    postLoc[[i]] <- readPostLocProb(postLocPath, prefix, dupProbs[i,1])
  }
  
  T <- ncol(postLoc[[1]])
  if(!is.null(times))
    if(T != length(times))
      stop("Inconsistent data provided: the length of times vector is not the same as the number of time instants computed from the posterior location probabilities files")

  nTiles <- nrow(postLoc[[1]])
  eq <- as.data.table(tileEquivalence(gridParams$nrow,gridParams$ncol))
  tiles<-eq[order(tile)]$rasterCell
  
  # 4. computation begins ...
  # build cluster
  cl <- buildCluster(c('postLoc', 'nTiles', 'tiles', 'dupProbs', 'regions') , env=environment())
  clusterSetRNGStream(cl, iseed=123)
  ichunks <- clusterSplit(cl, 1:T)
  res <-
    clusterApplyLB(
      cl,
      ichunks,
      doAggr,
      n,
      nTiles,
      tiles,
      postLoc,
      dupProbs,
      regions
    )
  stopCluster(cl)
  result <- rbindlist(res)
  if(!is.null(times)) {
    indices <- result$time 
    result$time <- times[indices]
  }
  return (result)
}



