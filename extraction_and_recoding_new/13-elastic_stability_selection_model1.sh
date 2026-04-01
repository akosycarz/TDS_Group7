#!/bin/bash
#PBS -q v1_medium72a
#PBS -l walltime=08:00:00
#PBS -l select=1:ncpus=32:mem=64gb
#PBS -N model1_lasso_selection

# Go to scripts folder
cd $PBS_O_WORKDIR/scripts

# Activate conda environment
eval "$(~/anaconda3/bin/conda shell.bash hook)"
conda activate r45

# Run the R script
R CMD BATCH 13-elastic_net_stability_selection_model1.R 

