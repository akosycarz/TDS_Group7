#!/bin/bash
#PBS -q v1_medium72a
#PBS -l walltime=04:00:00
#PBS -l select=1:ncpus=2:mem=8gb
#PBS -N mediation_dag

# Go to scripts folder
cd $PBS_O_WORKDIR/scripts

# Activate conda environment
eval "$($HOME/anaconda3/bin/conda shell.bash hook)"
conda activate r45

# Run the R script
Rscript 19-mediation_dag_figures.R