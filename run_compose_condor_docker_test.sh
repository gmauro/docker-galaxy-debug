#!/usr/bin/env bash

export COMPOSE_CONDOR_DOCKER=True

./wip/ci.sh > compose_condor_docker.log
