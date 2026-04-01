#!/bin/bash
#PBS -q v1_medium72a
#PBS -l walltime=06:00:00
#PBS -l select=1:ncpus=2:mem=16gb
#PBS -N mediation_heatmap

# Go to scripts folder
cd $PBS_O_WORKDIR/scripts

# Activate conda environment
eval "$($HOME/anaconda3/bin/conda shell.bash hook)"
conda activate r45

# Run the R script
Rscript 20-mediation_figures_heatmaps.R