#'@title Generates random value according to a Poisson multinomial distribution
#'
#'
#'
#'
#'
#'
#'
#'
#'
#'
#'@import extraDistr
#'@import data.table
#'@import deduplication
#'@import parallel
#'
#'
#'@export
rNnetEventOD<-function(n, dupFileName, regsFileName, postLocJointPath, prefix) {
    
    if (!file.exists(dupFileName))
        stop(paste0(dupFileName, " does not exists!"))
    
    dupProbs <- fread(
        dupFileName,
        sep = ',',
        header = TRUE,
        stringsAsFactors = FALSE
    )
    devices<-as.numeric(dupProbs[,1][[1]])
    
    if (!file.exists(regsFileName))
        stop(paste0(regsFileName, " does not exists!"))
    
    regions <- fread(
        regsFileName,
        sep = ',',
        header = TRUE,
        stringsAsFactors = FALSE
    )
    
    ndevices <- nrow(dupProbs)
    postLocJoint<-NULL

    cl <- buildCluster(c('postLocJointPath', 'prefix', 'dupProbs', 'devices') , env=environment())
    ichunks <- clusterSplit(cl, 1:ndevices)
    res <-
        clusterApplyLB(
            cl,
            ichunks,
            doRead,
            postLocJointPath,
            prefix,
            dupProbs,
            devices
        )
    for(i in 1:length(res))
        res[[i]]<-as.data.table(as.matrix(res[[i]]))
    result <- rbindlist(res)
    
    # 
    # for( i in 1:ndevices) {
    #     l <- readPostLocProb(postLocJointPath, prefix, dupProbs[i,1])
    #     l <- cbind(rep(devices[i], times= nrow(l)), l )
    #     postLocJoint<-rbind(postLocJoint,l)
    # }
    # rm(l)
    # 
    # postLocJoint <- as.data.table(as.matrix(postLocJoint))
    
    postLocJoint <- as.data.table(as.matrix(result))
    setnames(postLocJoint, c('device', 'time_from', "time_to", "tile_from", "tile_to", "eventLoc"))
    
    times<-sort(unlist(unique(postLocJoint[,2])))
    time_increment <- times[2]-times[1]
    rm(times)
    
    postLocJointReg <- merge(
        postLocJoint,
        regions, 
        by.x = 'tile_from', by.y = 'tile')
    setnames(postLocJointReg, 'region', 'region_from')
    
    postLocJointReg <- merge(
        postLocJointReg,
        regions,
        by.x = 'tile_to', by.y = 'tile')
    setnames(postLocJointReg, 'region', 'region_to')
    
    postLocJointReg <- postLocJointReg[, list(eventLoc = sum(eventLoc)), by = .(device, time_from, time_to, region_from, region_to)]
    
    
    postLoc <- postLocJoint[ ,list(locProb = sum(eventLoc)), by = .(device, tile_from, time_from)]
    rm(postLocJoint)
    
    postLocReg <- merge(
        postLoc,
        regions,
        by.x = 'tile_from', by.y = 'tile')
    setnames(postLocReg, 'region', 'region_from')
    
    postLocReg <- postLocReg[ , list(locProb = sum(locProb)), by = .(device, time_from, region_from)]
    
    postCondLocReg <- postLocJointReg[
        postLocReg, on = .(device, region_from, time_from)][ , prob := eventLoc / locProb][, .(device, time_from, time_to, region_from, region_to, prob)]
    rm(postLocJointReg)
    
    dedupProbs2_1_Reg <- merge(
        postCondLocReg, dupProbs[, deviceID := as.numeric(deviceID)], 
        by.x = 'device', by.y = 'deviceID', all.x = TRUE)
    
    dedupProbs1_1_Reg <- copy(dedupProbs2_1_Reg)[
        , singleP := 1 - dupP][
            , dupP := NULL]
    
    dedupProbs2_1_Reg[
        , prob := prob * dupP][
            , devCount := 0.5][
                , dupP := NULL]
    
    dedupProbs1_1_Reg[
        , prob := prob * singleP][
            , devCount := 1][
                , singleP := NULL]
    
    dedupProbsReg <- rbindlist(
        list(dedupProbs1_1_Reg, dedupProbs2_1_Reg))
    rm(dedupProbs1_1_Reg, dedupProbs2_1_Reg)

    time_from <- unique(unlist(dedupProbsReg[,time_from]))
    ichunks <- clusterSplit(cl, time_from)
    cellNames<-sort(unlist(unique(regions[,2])))
    n<-n
    clusterExport(cl, c('cellNames', 'n', 'time_increment', 'dedupProbsReg'), envir = environment())
    res <-
        clusterApplyLB(
            cl,
            ichunks,
            doOD,
            n,
            cellNames,
            time_increment,
            dedupProbsReg
        )
    stopCluster(cl)
    result <- rbindlist(res)
    return(result)
}

doOD <- function(ichunks, n, cellNames, time_increment, dedupProbs){

    NnetReg <- dedupProbs[time_from %in% ichunks][
        , rNnetCond_Event(.SD, cellNames = cellNames, n=n ), by = 'time_from', .SDcols = names(dedupProbs)][
            , time_to := time_from + time_increment]
    
    setcolorder(NnetReg, c('time_from', 'time_to', 'region_from', 'region_to', 'Nnet'))
    return(NnetReg)
}

doRead <- function(ichunks, path, prefix, dupP, devices) {
    postLoc <- NULL
    for(i in ichunks) {
        l <- readPostLocProb(path, prefix, dupP[i,1])
        l <- cbind(rep(devices[i], times= nrow(l)), l )
        postLoc<-rbind(postLoc,l)
    }
    return(postLoc)    
}