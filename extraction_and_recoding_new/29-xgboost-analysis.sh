#!/bin/bash
#PBS -q v1_medium72a
#PBS -l walltime=24:00:00
#PBS -l select=1:ncpus=16:ompthreads=16:mem=64gb
#PBS -N xgb_analysis
#PBS -o logs/29-xgb.out
#PBS -e logs/29-xgb.err

cd $PBS_O_WORKDIR/scripts

eval "$($HOME/anaconda3/bin/conda shell.bash hook)"
conda activate r45

Rscript 29-xgboost-analysis.R
