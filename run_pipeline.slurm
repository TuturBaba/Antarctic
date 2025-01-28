#!/bin/bash
#SBATCH -A tp_2501_m2_bim_166600
#SBATCH --job-name=assemblify
#SBATCH --cpus-per-task=1
#SBATCH --mem=10G
#SBATCH --time=12:00:00
#SBATCH --error=%x.sh.e%A
#SBATCH --output=%x.sh.o%A

# 1 - Loads modules needed to run Nextflow pipeline
module load nextflow/23.04.1 slurm-drmaa singularity graphviz/2.40.1

# 2 - Set working directory
#TODO: replace XX, in below path, by a number in the range 57 to 82 => YOUR personal account
#      (DO NOT remove 'assemblify-tmp')

WK_DIR=/jetstream2/scratch/main/jobs/64564846/working/jupyter/Antarctic-tmp

if [ ! -e "$WK_DIR" ]; then
  echo "ERROR: $WK_DIR does not exist" >&2
  exit 1
fi

# 2 - Set directory containing working data sets (sequencing raw data) 
export ASSEMBLIFY_DATA_PATH=/shared/ifbstor1/projects/tp_2501_m2_bim_166600/data
if [ ! -e "$ASSEMBLIFY_DATA_PATH" ]; then
  echo "ERROR: $ASSEMBLIFY_DATA_PATH does not exist" >&2
  exit 1
fi

export BUSCO_DB_PATH=$ASSEMBLIFY_DATA_PATH/busco-db/v5/odb_10

# 3  - Set directory containing singularity images 
export NXF_SINGULARITY_CACHEDIR=/shared/ifbstor1/projects/tp_2501_m2_bim_166600/containers
export NXF_TEMP=$WK_DIR/.nxf_temp_assemblify
mkdir -p $NXF_TEMP

export SCRATCH=$WK_DIR/scratch
mkdir -p $SCRATCH

# 4 - Run pipeline
nextflow run main.nf -profile custom,singularity -c ifb-core.config -resume &> assemblify.log 2>&1