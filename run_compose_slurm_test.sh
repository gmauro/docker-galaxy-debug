#!/usr/bin/env bash

export COMPOSE_SLURM=True

./wip/ci.sh > compose_slurm.log
