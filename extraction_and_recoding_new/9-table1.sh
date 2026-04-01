#!/bin/bash
#PBS -q v1_medium72a
#PBS -l walltime=02:00:00
#PBS -l select=1:ncpus=2:mem=8gb
#PBS -N table1

cd /rds/general/project/hda_25-26/live/TDS/TDS_Group7/extraction_and_recoding_new/scripts

eval "$($HOME/anaconda3/bin/conda shell.bash hook)"
conda activate r45

Rscript 9-table1.R
