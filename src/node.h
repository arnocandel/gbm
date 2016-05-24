//------------------------------------------------------------------------------
//  GBM by Greg Ridgeway  Copyright (C) 2003
//
//  File:       node.h
//
//  License:    GNU GPL (version 2 or later)
//
//  Contents:   a node in the tree
//
//  Owner:      gregr@rand.org
//
//  History:    3/26/2001   gregr created
//              2/14/2003   gregr: adapted for R implementation
//			   16/03/2016   James Hickey: updated to remove terminal and non-terminal nodes
//			   30/03/2016   James Hickey: state pattern to deal with continuous and categorical splits.
//------------------------------------------------------------------------------

#ifndef NODE_H
#define NODE_H
//------------------------------
// Includes
//------------------------------
#include <vector>
#include "dataset.h"
#include "node_parameters.h"
#include "buildinfo.h"

//------------------------------
// Class Forwards and Enums
//------------------------------
class GenericNodeStrategy;
enum SplitType {categorical, continuous, none};

using namespace std;
typedef vector<int> VEC_CATEGORIES;
typedef vector<VEC_CATEGORIES> VEC_VEC_CATEGORIES;

//------------------------------
// Class definition
//------------------------------
class CNode
{
public:
	//----------------------
	// Public Constructors
	//----------------------
  CNode(const NodeDef& defn);

	//---------------------
	// Public destructor
	//---------------------
    virtual ~CNode();

	//---------------------
	// Public Functions
	//---------------------
    void Adjust(unsigned long cMinObsInNode);
    void Predict(const CDataset &data,
			 unsigned long iRow,
			 double &dFadj);

    void GetVarRelativeInfluence(double *adRelInf);
    void SplitNode(NodeParams& childrenParams);
    void PrintSubtree(unsigned long cIndent);
    void TransferTreeToRList(int &iNodeID,
				     const CDataset &data,
				     int *aiSplitVar,
				     double *adSplitPoint,
				     int *aiLeftNode,
				     int *aiRightNode,
				     int *aiMissingNode,
				     double *adErrorReduction,
				     double *adWeight,
				     double *adPred,
				     VEC_VEC_CATEGORIES &vecSplitCodes,
				     int cCatSplitsOld,
				     double dShrinkage);
	signed char WhichNode(const CDataset &data,
							unsigned long iObs);

	//---------------------
	// Public Variables
	//---------------------
	// Pointers to the Node's children
	CNode* left_node_ptr;
	CNode* right_node_ptr;
	CNode* missing_node_ptr;

	//TODO: Currently most useful in printing out tree
	// This nodes parameters
	unsigned long split_var;
	double improvement;

	// Properties defining the node
	double prediction;
	double totalweight;   // total training weight in node
	unsigned long numobs; // number of training observations in node

	// ENUM FOR strategy
	SplitType splittype;

	// VARIABLES USED IN NODE SPLITTING
	std::vector<unsigned long> leftcategory;
    double splitvalue;

private:
	//---------------------
	// Private Functions
	//---------------------
    void SetStrategy();

	//---------------------
	// Private Variables
	//---------------------
    GenericNodeStrategy* node_strategy_;

};

#endif // NODE_H

