#!/bin/bash
#PBS -q v1_medium72a
#PBS -l walltime=04:00:00
#PBS -l select=1:ncpus=4:ompthreads=4:mem=32gb
#PBS -N PCA_analysis
#PBS -o logs/28-PCA.out
#PBS -e logs/28-PCA.err

# go to scripts folder
cd $PBS_O_WORKDIR/scripts

# activate conda
eval "$($HOME/anaconda3/bin/conda shell.bash hook)"
conda activate r45

# run script
Rscript 28-PCA.R
