#!/bin/bash
#PBS -q v1_medium72a
#PBS -l walltime=48:00:00
#PBS -l select=1:ncpus=16:ompthreads=1:mem=128gb
#PBS -N model1_mediation_v2

# Go to scripts folder
cd $PBS_O_WORKDIR/scripts

# Activate conda environment
eval "$($HOME/anaconda3/bin/conda shell.bash hook)"
conda activate r45

# Run the R script
Rscript 18-final_analysis_mediation.R
