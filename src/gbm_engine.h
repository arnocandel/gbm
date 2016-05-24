//------------------------------------------------------------------------------
//
//  File:       gbm_engine.h
//
//  Description:   Header file for Gradient Boosting Engine.
//
//  Owner:      gregr@rand.org
//
//  History:    3/26/2001   gregr created
//              2/14/2003   gregr: adapted for R implementation
//
//------------------------------------------------------------------------------

#ifndef GBMENGINE_H
#define GBMENGINE_H

//------------------------------
// Includes
//------------------------------
#include "buildinfo.h"
#include "config_structs.h"
#include "gbm_datacontainer.h"
#include "gbm_treecomponents.h"
#include <memory>
#include <Rcpp.h>
#include <vector>

//------------------------------
// Class definition
//------------------------------
class CGBM
{
public:
	//----------------------
	// Public Constructors
	//----------------------
    CGBM(ConfigStructs& GBMParams);

	//---------------------
	// Public destructor
	//---------------------
    ~CGBM();

	//---------------------
	// Public Functions
	//---------------------
    void FitLearner(double *adF,
		 double &dTrainError,
		 double &dValidError,
		 double &dOOBagImprove);

    void GBMTransferTreeToRList(int *aiSplitVar,
			     double *adSplitPoint,
			     int *aiLeftNode,
			     int *aiRightNode,
			     int *aiMissingNode,
			     double *adErrorReduction,
			     double *adWeight,
			     double *adPred,
			     VEC_VEC_CATEGORIES &vecSplitCodes,
			     int cCatSplitsOld);

    const long size_of_fitted_tree() const{ return treecomponents_.size_of_tree(); }
    double initial_function_estimate() { return datacontainer_.InitialFunctionEstimate(); };

private:
	//-------------------
	// Private Variables
	//-------------------
    CGBMDataContainer datacontainer_;
    CTreeComps treecomponents_;
    
    // Residuals and adjustments to function estimate
    std::vector<double> residuals_;

};

#endif // GBMENGINE_H



