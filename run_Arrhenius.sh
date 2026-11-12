#!/usr/bin/env bash
#SBATCH --job-name=test_00
#SBATCH --account=naiss2026-3-667-gpu    # or naiss2026-1-3-gpu (Bolin)     
#SBATCH --time=00:45:00                  # or naiss2025-3-39-gpu (KTH)
#SBATCH --partition=gpu
#SBATCH --nodes=2                        # n. of nodes = ntasks/4. Modify only this for bigger runs
#SBATCH --ntasks-per-node=4              # don't change this, it must be == --gpus-per-node
#SBATCH --gpus-per-node=4                # don't change this, it must be == --ntasks-per-node
#SBATCH --cpus-per-task=72               # 72 for GH200, must be >= OMP_NUM_THREADS
#SBATCH -o %x_%j.o
#SBATCH -e %x_%j.e

casename="vreman"
mesh="n_16"                             

CASE_FILE="${casename}.case"

MESH_FILE="/nobackup/proj/disk/abl-simulations/personal/ldl/meshes/${mesh}.nmsh"
OUTPUT_DIR="/nobackup/proj/disk/abl-simulations/personal/ldl/SIM_DIR/output/${mesh}/${casename}/"
LOG_DIR="/nobackup/proj/disk/abl-simulations/personal/ldl/SIM_DIR/output/${mesh}/logfiles/"
CLEAN_SCRIPT="/home/ldl/scripts/clean_csv.sh"                         

# Executable: use ONE of the two.
NEKO_EXEC="neko_${casename}"             # user executable built with makeneko, in the submit directory
# NEKO_EXEC="/home/ldl/neko_gpu/bin/neko"  #ref build

SBATCH_TIME=$(grep -m1 "^#SBATCH --time=" "$0" | cut -d'=' -f2 | awk '{print $1}')

echo "Running Neko with the following settings:"
echo "  Job Name: $SLURM_JOB_NAME"
echo "  Account: $SLURM_JOB_ACCOUNT"
echo "  Time Limit: $SBATCH_TIME"
echo "  Partition: $SLURM_JOB_PARTITION"
echo "  Nodes: $SLURM_NNODES"
echo "  Tasks per Node: $SLURM_NTASKS_PER_NODE"
echo "  GPUs per Node: $SLURM_GPUS_PER_NODE"
echo "  CPUs per Task: $SLURM_CPUS_PER_TASK"
echo "  "
echo "  Case File: $CASE_FILE"
echo "  Neko Executable: $NEKO_EXEC"
echo "  Output Directory: $OUTPUT_DIR"

# Modules: must match the environment the executable was built with
ml GPU/buildenv-gcccuda/2026.03-cu13.0
# load JSON-Fortran
source /nobackup/proj/disk/kthmech/shared/software/json-fortran/install/GPU_buildenv-gcccuda_2026.03-cu13.0/env.sh

export MPIR_CVAR_GPU_SMI=1
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK     # as in the reference script (LUMI used 2 because of an OpenMP bug)
export OMP_PLACES=cores
export OMP_PROC_BIND=close

if [ "$SLURM_NTASKS_PER_NODE" -ne "$SLURM_GPUS_PER_NODE" ]; then
    echo "Error: Rank-to-GPU mismatch. Tasks: $SLURM_NTASKS_PER_NODE, GPUs: $SLURM_GPUS_PER_NODE"
    echo "--ntasks-per-node must be == to --gpus-per-node"
    exit 1
fi

if [ "$OMP_NUM_THREADS" -gt "$SLURM_CPUS_PER_TASK" ]; then
    echo "Error: OMP_NUM_THREADS ($OMP_NUM_THREADS) exceeds CPUs per task ($SLURM_CPUS_PER_TASK)."
    exit 1
fi

mkdir -p "${LOG_DIR}" "${OUTPUT_DIR}"

ml list 2>&1   # log the loaded modules

cat << EOF > ./select_gpu
#!/bin/bash
export CUDA_VISIBLE_DEVICES=\$SLURM_LOCALID
exec \$*
EOF

chmod +x ./select_gpu

# Update the case file (same as on LUMI)
sed -i "s|\"output_directory\":.*|\"output_directory\": \"$OUTPUT_DIR\",|g" "$CASE_FILE"
sed -i "s|\"mesh_file\":.*|\"mesh_file\": \"$MESH_FILE\",|g" "$CASE_FILE"
sed -i "s|\"job_timelimit\":.*|\"job_timelimit\": \"$SBATCH_TIME\",|g" "$CASE_FILE"

srun --unbuffered ./select_gpu ${NEKO_EXEC} ${CASE_FILE} > "${LOG_DIR}/log.run_${casename}" 2>&1

rm -f ./select_gpu
mv *0.* "${OUTPUT_DIR}"
if [ -n "$CLEAN_SCRIPT" ] && [ -x "$CLEAN_SCRIPT" ]; then
    "$CLEAN_SCRIPT" "${OUTPUT_DIR}"
fi
