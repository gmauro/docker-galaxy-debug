DEBUG_CONTAINER_NAME = dg_debug
GALAXY_CONTAINER_NAME = galaxy
CONTAINER_NETWORK_NAME = debug
BASE_IMAGE_NAME = docker_galaxy_debug-base
IMAGE_NAME = docker_galaxy_debug
TARGETS=help clean
TMP_BUILD_DIR := $(shell mktemp -d)

.PHONY: "${TARGETS}"

define docker_build
	docker build --no-cache -t "$(1)" -f $(2) $(3)
endef

help:
	@echo "Please use \`make <target>\` where <target> is one of"
	@echo "  clean                    to stop and remove debug container"
	@echo "  build_base               to build Docker base image"
	@echo "  build_debug              to build Docker debug image"
	@echo "  build_monolithic_galaxy  to build monolithic Docker  image"
	@echo "  exec                     to exec a command in the running container"
	@echo "  prune                    to remove unused data"
	@echo "  run                      to run Docker base container"

clean: stop remove restart_docker_service
	echo "A bit of cleaning..."

build_base:
	$(call docker_build,${BASE_IMAGE_NAME},Dockerfile_base,.)

build_debug:
	$(call docker_build,${IMAGE_NAME},Dockerfile,.)

build_monolithic_galaxy: clone_monolithic_galaxy
	$(call docker_build,quay.io/bgruening/galaxy:pg11,Dockerfile,$(TMP_BUILD_DIR)/galaxy/)

clone_monolithic_galaxy:
	git clone --recursive -b pg11 --single-branch https://github.com/gmauro/docker-galaxy-stable.git '$(TMP_BUILD_DIR)'
	chmod -R +rx "$(TMP_BUILD_DIR)"

exec:
	docker exec -it "${DEBUG_CONTAINER_NAME}" bash -l

prune:
	docker system prune -f
	docker volume prune -f

run:
	docker run --rm \
		-e "DCKR_HOST=$(shell ip -4 addr show docker0 | grep -Po 'inet \K[\d.]+')" \
		--name "${DEBUG_CONTAINER_NAME}" \
		-v "/var/run/docker.sock:/var/run/docker.sock" \
		-v "$(TMP_BUILD_DIR):/home/user/build_dir" \
		-dit  "${IMAGE_NAME}"

	docker ps

start_debug_env: clone_monolithic_galaxy run exec


stop:
	-docker stop "${DEBUG_CONTAINER_NAME}"
	-docker stop "${GALAXY_CONTAINER_NAME}"

test-mono:
	docker exec -ti "${DEBUG_CONTAINER_NAME}" bash run_test.sh

restart_docker_service:
	sudo service docker restart

remove:
	-docker rm "${DEBUG_CONTAINER_NAME}"
	-docker rm "${GALAXY_CONTAINER_NAME}"

