#!/usr/bin/env bash

export COMPOSE_SLURM_SINGULARITY=True

./wip/ci.sh > compose_slurm_singularity.log
