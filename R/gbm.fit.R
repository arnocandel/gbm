#' @describeIn gbm Core fitting code, for experts only
#' @export gbm.fit
gbm.fit <- function(x,y,
                    offset = NULL,
                    misc = NULL,
                    distribution = "bernoulli",
                    w = NULL,
                    var.monotone = NULL,
                    n.trees = 100,
                    interaction.depth = 1,
                    n.minobsinnode = 10,
                    shrinkage = 0.001,
                    bag.fraction = 0.5,
                    nTrain = NULL,
                    train.fraction = NULL,
                    mFeatures = NULL,
                    keep.data = TRUE,
                    verbose = TRUE,
                    var.names = NULL,
                    response.name = "y",
                    group = NULL,
                    prior.node.coeff.var = 1000,
                    strata = NULL,
                    patient.id = 1:nrow(x),
                    par.details=getOption("gbm.parallel")){

   if(is.character(distribution)) { distribution <- list(name=distribution) }
  
   cRows <- nrow(x)
   cCols <- ncol(x)

   # Get size of Response frame
   cRowsY <- nrow(y)
   cColsY <- ncol(y)
   if(is.null(cRowsY))
   {
     cRowsY <- length(y)
     cColsY <- 1
   }
   
   checkSanity(x, y)
   ch <- checkMissing(x, y)
   checkVarType(x, y)
   
   oldy <- y
   y <- checkY(oldy)
   
   # Only strata, ties and sorted vecs for CoxPh
   StrataVec <- NA
   sortedVec <- NA

   # the preferred way to specify the number of training instances is via parameter 'nTrain'.
   # parameter 'train.fraction' is only maintained for backward compatibility.

   if(!is.null(nTrain) && !is.null(train.fraction)) {
      stop("Parameters 'nTrain' and 'train.fraction' cannot both be specified")
   
   } else if(!is.null(train.fraction)) {
      warning("Parameter 'train.fraction' of gbm.fit is deprecated, please specify 'nTrain' instead")
      nTrain <- floor(train.fraction*length(unique(patient.id)))
   
   } else if(is.null(nTrain)) {
     # both undefined, use all training data
     nTrain <- length(unique(patient.id))
   }
  
   if(!is.double(prior.node.coeff.var))
   {
     stop("Prior on coefficient of variation must be a double")
   }
   
   if (is.null(train.fraction)){
      train.fraction <- nTrain / length(unique(patient.id))
   }
   
   if (is.null(mFeatures)) {
     mFeatures <- cCols
   }

   if(is.null(var.names)) {
       var.names <- getVarNames(x)
   }

   # Order X, Y according to the patient id
   if(is.data.frame(y)) 
   {
     y <- y[order(patient.id), , drop=FALSE]
   }
   else
   {
     y <- y[order(patient.id)]
   }
   x <- x[order(patient.id), , drop=FALSE]
   num_rows_each_pat <- table(patient.id[order(patient.id)])
   
   # Calculate the number of rows in training set
   nTrainRows <- sum(num_rows_each_pat[1:nTrain])
   
#   if(is.null(response.name)) { response.name <- "y" }

   # check dataset size
   if(nTrainRows * bag.fraction <= 2*n.minobsinnode+1) {
      stop("The dataset size is too small or subsampling rate is too large: nTrainRows*bag.fraction <= n.minobsinnode")
   }

   if (distribution$name != "pairwise") {
      w <- w*length(w)/sum(w) # normalize to N
   }

   # Do sanity checks
   interaction.depth <- checkID(interaction.depth)
   w <- checkWeights(w, length(y))
   offset <- checkOffset(offset, y, distribution)

   Misc <- NA

   # setup variable types
   var.type <- rep(0, cCols)
   var.levels <- vector("list", cCols)
   
   
   for(i in 1:length(var.type)) {
     
      if(is.ordered(x[,i])) {
        
         var.levels[[i]] <- levels(factor(x[,i]))
         x[,i] <- as.numeric(factor(x[,i]))-1
         var.type[i] <- 0
         
      }
     
      else if(is.factor(x[,i])) {
      
         var.levels[[i]] <- levels(factor(x[,i]))
         x[,i] <- as.numeric(factor(x[,i]))-1
         var.type[i] <- max(x[,i],na.rm=TRUE)+1
         
      }
      else if(is.numeric(x[,i])) {
        
        var.levels[[i]] <- quantile(x[,i],prob=(0:10)/10,na.rm=TRUE)
        
      }

      # check for some variation in each variable
      warnNoVariation(x[,i], i, var.names[[i]])
   }
   
   
   if(!("name" %in% names(distribution))) {
      stop("The distribution is missing a 'name' component, for example list(name=\"gaussian\")")
   }
   supported.distributions <-
   c("bernoulli","gaussian","poisson","adaboost","laplace","coxph","quantile",
     "tdist", "huberized", "pairwise","gamma","tweedie")

   distribution.call.name <- distribution$name

   # check potential problems with the distributions
   if(!is.element(distribution$name,supported.distributions))
   {
      stop("Distribution ",distribution$name," is not supported")
   }
   if((distribution$name == "bernoulli") && !all(is.element(y,0:1)))
   {
      stop("Bernoulli requires the response to be in {0,1}")
   }
   if((distribution$name == "huberized") && !all(is.element(y,0:1)))
   {
      stop("Huberized square hinged loss requires the response to be in {0,1}")
   }
   if((distribution$name == "poisson") && any(y<0))
   {
      stop("Poisson requires the response to be positive")
   }
   if((distribution$name == "gamma") && any(y<0))
   {
      stop("Gamma requires the response to be positive")
   }
   if(distribution$name == "tweedie")
   {
      if(any(y<0))
      {
         stop("Tweedie requires the response to be positive")
      }
      if(is.null(distribution$power))
      {
         distribution$power = 1.5
      }
     # Bind power to second column of response
      Misc <- c(power=distribution$power)
   }
   if((distribution$name == "poisson") && any(y != trunc(y)))
   {
      stop("Poisson requires the response to be a positive integer")
   }
   if((distribution$name == "adaboost") && !all(is.element(y,0:1)))
   {
      stop("This version of AdaBoost requires the response to be in {0,1}")
   }
   if(distribution$name == "quantile")
   {
      if(is.null(distribution$alpha))
      {
         stop("For quantile regression, the distribution parameter must be a list with a parameter 'alpha' indicating the quantile, for example list(name=\"quantile\",alpha=0.95).")
      } else
      if((distribution$alpha<0) || (distribution$alpha>1))
      {
         stop("alpha must be between 0 and 1.")
      }
     Misc <- c(alpha=distribution$alpha)
   }
   if(distribution$name == "coxph")
   {
      if(class(y)!="Surv")
      {
         stop("Outcome must be a survival object Surv(time1, failure) or Surv(time1, time2, failure)")
      }

     
      # Patients are split into train and test, and are ordered by
      # strata
       # Define number of tests
       n.test <- cRows - nTrainRows
       
       
       # Set up strata 
       if(!is.null(strata))
       {
         # Sort strata according to patient ID
         strata <- strata[order(patient.id)]
         
         # Order strata and split into train/test
         strataVecTrain <- strata[1:nTrainRows]
         strataVecTest <- strata[(nTrainRows+1): cRows]
         
         # Cum sum the number in each stratum and pad with NAs
         # between train and test strata
         strataVecTrain <- as.vector(cumsum(table(strataVecTrain)))
         strataVecTest <- as.vector(cumsum(table(strataVecTest)))
         
         strataVecTrain <- c(strataVecTrain, rep(NA, nTrainRows-length(strataVecTrain)))
         strataVecTest <- c(strataVecTest, rep(NA, n.test-length(strataVecTest)))
         
         # Recreate Strata Vec to Pass In
         nstrat <- c(strataVecTrain, strataVecTest)
         
       }
       else
       {
         # Put all the train and test data in a single stratum
         strata <- rep(1, cRows)
         trainStrat <- c(nTrainRows, rep(NA, nTrainRows-1))
         testStrat <- c(n.test, rep(NA, n.test-1))
         nstrat <- c(trainStrat, testStrat)
       }
       
       # Sort response according to strata
       # i.order sets order of outputs
       if (attr(y, "type") == "right")
       {
         sorted <- c(order(strata[1:nTrainRows], -y[1:nTrainRows, 1]), order(strata[(nTrainRows+1):cRows], -y[(nTrainRows+1):cRows, 1])) 
         i.order <- c(order(strata[1:nTrainRows], -y[1:nTrainRows, 1]), order(strata[(nTrainRows+1):cRows], -y[(nTrainRows+1):cRows, 1]) + nTrainRows)
       }
       else if (attr(y, "type") == "counting") 
       {
         sorted <- cbind(c(order(strata[1:nTrainRows], -y[1:nTrainRows, 1]), order(strata[(nTrainRows+1):cRows], -y[(nTrainRows+1):cRows, 1])),
                         c(order(strata[1:nTrainRows], -y[1:nTrainRows, 2]), order(strata[(nTrainRows+1):cRows], -y[(nTrainRows+1):cRows, 2])))
         i.order <- c(order(strata[1:nTrainRows], -y[1:nTrainRows, 1]), order(strata[(nTrainRows+1):cRows], -y[(nTrainRows+1):cRows, 1]) + nTrainRows)
       }
       else
       {
         stop("Survival object must be either right or counting type.")
       }

      # Add in sorted column and strata
      StrataVec <-  nstrat
      sortedVec <- sorted-1L

      # Set ties here for the moment
      if(is.null(misc))
      {
        Misc <- list("ties" = "efron")
      }
      else if(  !((misc == "efron") || (misc == "breslow")) && (dim(y)[2] > 2))
      {
        message("Require tie breaking method for counting survival object - set to Efron")
        Misc <- list("ties" = "efron")
      }
      else
      {
        Misc <- list("ties"= misc)
      }

   }
   if(distribution$name == "tdist")
   {
     
      if (is.null(distribution$df) || !is.numeric(distribution$df))
      {
        Misc <- 4
      }
      else
      {
        Misc <- distribution$df[1]
      }
   }
   if(distribution$name == "pairwise")
   {
      distribution.metric <- distribution[["metric"]]
      if (!is.null(distribution.metric))
      {
         distribution.metric <- tolower(distribution.metric)
         supported.metrics <- c("conc", "ndcg", "map", "mrr")
         if (!is.element(distribution.metric, supported.metrics))
         {
            stop("Metric '", distribution.metric, "' is not supported, use either 'conc', 'ndcg', 'map', or 'mrr'")
         }
         metric <- distribution.metric
      }
      else
      {
         warning("No metric specified, using 'ndcg'")
         metric <- "ndcg" # default
         distribution[["metric"]] <- metric
      }

      if (any(y<0))
      {
         stop("targets for 'pairwise' should be non-negative")
      }

      if (is.element(metric, c("mrr", "map")) && (!all(is.element(y, 0:1))))
      {
         stop("Metrics 'map' and 'mrr' require the response to be in {0,1}")
      }

      # Cut-off rank for metrics
      # Default of 0 means no cutoff

      max.rank <- 0
      if (!is.null(distribution[["max.rank"]]) && distribution[["max.rank"]] > 0)
      {
         if (is.element(metric, c("ndcg", "mrr")))
         {
            max.rank <- distribution[["max.rank"]]
         }
         else
         {
            stop("Parameter 'max.rank' cannot be specified for metric '", distribution.metric, "', only supported for 'ndcg' and 'mrr'")
         }
      }

      # We pass the cut-off rank to the C function as the last element in the Misc vector
      Misc <- list("GroupsAndRanks"=c(group, max.rank))
      distribution.call.name <- sprintf("pairwise_%s", metric)
   } # close if (dist... == "pairwise"

   # create index upfront... subtract one for 0 based order
   x.order <- apply(x[1:nTrainRows,,drop=FALSE],2,order,na.last=FALSE)-1

   x <- as.vector(data.matrix(x))

   if(is.null(var.monotone)) var.monotone <- rep(0,cCols)
   else if(length(var.monotone)!=cCols)
   {
      stop("Length of var.monotone != number of predictors")
   }
   else if(!all(is.element(var.monotone,-1:1)))
   {
      stop("var.monotone must be -1, 0, or 1")
   }
   
   # Make sorted vec into a matrix
   if(cColsY > 2)
   {
     cRowsSort <- dim(sortedVec)[1]
     cColsSort <- dim(sortedVec)[2]
   }
   else
   {
     cRowsSort <- length(sortedVec)
     cColsSort <- 1
   }
   
   # Call GBM fit from C++
   gbm.obj <- .Call("gbm",
                    Y=matrix(y, cRowsY, cColsY),
                    Offset=as.double(offset),
                    X=matrix(x, cRows, cCols),
                    X.order=as.integer(x.order),
                    sorted=matrix(sortedVec, cRowsSort, cColsSort),
                    Strata = as.integer(StrataVec),
                    weights=as.double(w),
                    Misc=as.list(Misc),
                    prior.node.coeff.var = as.double(prior.node.coeff.var),
                    patient.id = as.integer(patient.id),
                    var.type=as.integer(var.type),
                    var.monotone=as.integer(var.monotone),
                    distribution=as.character(distribution.call.name),
                    n.trees=as.integer(n.trees),
                    interaction.depth=as.integer(interaction.depth),
                    n.minobsinnode=as.integer(n.minobsinnode),
                    shrinkage=as.double(shrinkage),
                    bag.fraction=as.double(bag.fraction),
                    nTrain=as.integer(nTrainRows),
                    nTrainPats = as.integer(nTrain),
                    mFeatures=as.integer(mFeatures),
                    fit.old=as.double(NA),
                    n.cat.splits.old=as.integer(0),
                    n.trees.old=as.integer(0),
                    par.details,
                    verbose=as.integer(verbose),
                    PACKAGE = "gbm")

   gbm.obj$bag.fraction <- bag.fraction
   gbm.obj$distribution <- distribution
   gbm.obj$interaction.depth <- interaction.depth
   gbm.obj$n.minobsinnode <- n.minobsinnode
   gbm.obj$n.trees <- length(gbm.obj$trees)
   gbm.obj$nTrain <- nTrainRows
   gbm.obj$nTrainPats <- nTrain
   gbm.obj$patient.id <- patient.id
   gbm.obj$mFeatures <- mFeatures
   gbm.obj$train.fraction <- train.fraction
   gbm.obj$response.name <- response.name
   gbm.obj$shrinkage <- shrinkage
   gbm.obj$var.levels <- var.levels
   gbm.obj$var.monotone <- var.monotone
   gbm.obj$var.names <- var.names
   gbm.obj$var.type <- var.type
   gbm.obj$verbose <- verbose
   gbm.obj$Terms <- NULL
   gbm.obj$strata <- StrataVec
   gbm.obj$sorted <- sortedVec
   gbm.obj$prior.node.coeff.var <- prior.node.coeff.var

   if(distribution$name == "coxph")
   {
      gbm.obj$fit[i.order] <- gbm.obj$fit
   }
   

   if(keep.data)
   {
      if(distribution$name == "coxph")
      {
         # put the observations back in order
         gbm.obj$data <- list(y=oldy,x=x,x.order=x.order,offset=offset,Misc=Misc,w=w,
                              i.order=i.order)
     } else
      {
         gbm.obj$data <- list(y=oldy,x=x,x.order=x.order,offset=offset,Misc=Misc,w=w)
      }
   }
   else
   {
      gbm.obj$data <- NULL
   }

   class(gbm.obj) <- "gbm"
   return(gbm.obj)
}
