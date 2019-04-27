DEBUG_CONTAINER_NAME = dg_debug
GALAXY_CONTAINER_NAME = galaxy
CONTAINER_NETWORK_NAME = debug
BASE_IMAGE_NAME = docker_galaxy_debug-base
IMAGE_NAME = docker_galaxy_debug
HOST_DIR = /home/gmauro/version/gmauro/docker-galaxy-debug/wip
CONTAINER_DIR = /home/user/from_host
TARGETS=help clean 

.PHONY: "${TARGETS}"

help:
	@echo "Please use \`make <target>\` where <target> is one of"
	@echo "  clean        to stop and remove debug container"
	@echo "  build_base   to build Docker base image"
	@echo "  build_debug  to build Docker debug image"
	@echo "  exec         to exec a command in the running container"
	@echo "  prune        to remove unused data"
	@echo "  run          to run Docker base container"

clean: stop remove restart_docker_service
	echo "A bit of cleaning..."

build_base:
	docker build -t  "${BASE_IMAGE_NAME}" -f Dockerfile_base .

build_debug:
	docker build -t  "${IMAGE_NAME}" .

exec:
	docker exec -it "${DEBUG_CONTAINER_NAME}" bash -l

prune:
	docker system prune -f
	docker volume prune

run:
	docker run --rm \
		-e "DCKR_HOST=$(shell ip -4 addr show docker0 | grep -Po 'inet \K[\d.]+')" \
		--name "${DEBUG_CONTAINER_NAME}" \
		-v "/var/run/docker.sock:/var/run/docker.sock" \
		-v "${HOST_DIR}:${CONTAINER_DIR}" \
		-dit  "${IMAGE_NAME}"

	docker ps

stop:
	-docker stop "${DEBUG_CONTAINER_NAME}"
	-docker stop "${GALAXY_CONTAINER_NAME}"

restart_docker_service:
	sudo service docker restart

remove:
	-docker rm "${DEBUG_CONTAINER_NAME}"
	-docker rm "${GALAXY_CONTAINER_NAME}"

