#!/usr/bin/env bash

TRAVIS_BUILD_DIR="/home/user/build_dir"
FORCE_BUILD=false

source config.sh

docker info
docker --version
python --version
pip --version
git --version
echo "PATH=$PATH"
echo "DOCKER_HOST=$DCKR_HOST"
sleep 10

set -e
export GALAXY_HOME=/home/galaxy
export GALAXY_USER=admin@galaxy.org
export GALAXY_USER_EMAIL=admin@galaxy.org
export GALAXY_USER_PASSWD=admin
export BIOBLEND_GALAXY_API_KEY=admin
export BIOBLEND_GALAXY_URL="http://${DCKR_HOST}:8080"
export COMPOSE_DIR="${TRAVIS_BUILD_DIR}/compose"

# Build a k8s cluster
if [ "${KUBE}" ]
then
    # setup k8s, we will do this before building Galaxy because it takes some time and hopefully we can do both in prallel
    gimme 1.11.1
    source ~/.gimme/envs/go1.11.1.env
    sudo ln -s /home/travis/.gimme/versions/go1.11.1.linux.amd64/bin/gofmt /usr/bin/gofmt
    sudo ln -s /home/travis/.gimme/versions/go1.11.1.linux.amd64/bin/go /usr/bin/go
    go version
    mkdir ../kubernetes
    wget -q -O - https://github.com/kubernetes/kubernetes/archive/master.tar.gz | tar xzf - --strip-components=1 -C ../kubernetes
    cd ../kubernetes
    # k8s API port is running by default on 8080 as Galaxy, can this to 8000
    export API_PORT=8000
    ./hack/install-etcd.sh
    sudo ln -s `pwd`/third_party/etcd/etcd /usr/bin/etcd
    sudo ln -s `pwd`/third_party/etcd/etcdctl /usr/bin/etcdctl
    # this needs to run in backgroud later, for now try to see the output
    ./hack/local-up-cluster.sh &
    cd ../docker-galaxy-stable
fi

# load all configurations needed for SLURM testing
if [ "${COMPOSE_SLURM}" ]
then
    # The compose file recognises ENV vars to change the defaul behavior
    cd ${COMPOSE_DIR}
    ln -sf .env_slurm .env
fi

# load all configurations needed for Condor and Docker
if [ "${COMPOSE_CONDOR_DOCKER}" ]
then
    # The compose file recognises ENV vars to change the defaul behavior
    cd ${COMPOSE_DIR}
    ln -sf .env_htcondor_docker .env
    # Galaxy needs to a full path for the the jobs, in- and outputs.
    # Do we want to run each job in it's own container and this container uses the host
    # container engine (not Docker in Docker) then the path to all files inside and outside
    # of the container needs to be the same.
    sudo mkdir /export
    sudo chmod 777 /export
    sudo chown 1450:1450 /export
fi

# Installing kompose to convert the docker-compose YAML file
if [ "${KUBE}" ]
then
    # The compose file recognises ENV vars to change the defaul behavior
    cd ${COMPOSE_DIR}
    ln -sf .env_k8_native .env
    curl -L https://github.com/kubernetes-incubator/kompose/releases/download/v1.17.1/kompose-linux-amd64 -o kompose
    chmod +x kompose
    sudo mv ./kompose /usr/bin/kompose
fi

# start building this repo
##%
cd "${TRAVIS_BUILD_DIR}"
git submodule update --init --recursive
sudo chown 1450 /tmp && sudo chmod a=rwx /tmp

if [ "${COMPOSE_SLURM}" ] || [ "${COMPOSE_CONDOR_DOCKER}" ] || [ "${KUBE}" ] || [ "${COMPOSE_SLURM_SINGULARITY}" ]
then
    pip install docker-compose galaxy-parsec
    export WORKING_DIR="$TRAVIS_BUILD_DIR/compose"
    export DOCKER_RUN_CONTAINER="galaxy-web"
    INSTALL_REPO_ARG="--galaxy-url http://${DCKR_HOST}:80"
    SAMPLE_TOOLS=/export/config/sample_tool_list.yaml
    cd "$WORKING_DIR"
    # For build script
    export CONTAINER_REGISTRY=quay.io/
    export CONTAINER_USER=bgruening
    ./build-orchestration-images.sh --no-push --condor --grafana --slurm --k8s
    source ./tags-for-compose-to-source.sh
    export COMPOSE_PROJECT_NAME=galaxy_compose
    docker-compose up -d
    until docker-compose exec galaxy-web ps -fC uwsgi
    do
        echo "sleeping for 20 seconds"
        sleep 20
        docker-compose logs --tail 10
    done
    if [ "${COMPOSE_CONDOR_DOCKER}" ]
    then
        # turn down the slurm service
        echo "Stopping SLURM container"
        docker-compose stop galaxy-slurm
        sleep 30
    fi
    if [ "${COMPOSE_SLURM}" ] || [ "${COMPOSE_SLURM_SINGULARITY}" ]
    then
        # turn down the htcondor services
        echo "Stopping HT-Condor containers"
        docker-compose stop galaxy-htcondor galaxy-htcondor-executor galaxy-htcondor-executor-big
        sleep 30
    fi
    if [ "${COMPOSE_SLURM_SINGULARITY}" ]
    then
        # docker-compose is already started and has pre-populated the /export dir
        # we now turn it down again and copy in an example tool with tool_conf.xml and
        # a test singularity image. If we copy this from the beginning, the magic Docker Galax startup
        # script will not work as it detects something in /export/
        docker-compose down
        sleep 20
        echo "Downloading Singularity test files and images."
        sudo mkdir -p /export/database/container_images/singularity/mulled/
        sudo curl -L -o /export/database/container_images/singularity/mulled/samtools:1.4.1--0 https://github.com/bgruening/singularity-galaxy-tests/raw/master/samtools:1.4.1--0
        sudo curl -L -o /export/cat_tool_conf.xml https://github.com/bgruening/singularity-galaxy-tests/raw/master/cat_tool_conf.xml
        sudo curl -L -o /export/cat.xml https://github.com/bgruening/singularity-galaxy-tests/raw/master/cat.xml
        rm .env
        ln -sf .env_slurm_singularity2 .env
        docker-compose up -d
        until docker-compose exec galaxy-web ps -fC uwsgi
        do
            echo "Starting up Singularity test container: sleeping for 40 seconds"
            sleep 40
            docker-compose logs
        done
        echo "waiting until Galaxy is up"
        galaxy-wait -g $BIOBLEND_GALAXY_URL --timeout 300
        echo "parsec init"
        parsec init --api_key admin --url $BIOBLEND_GALAXY_URL
        HISTORY_ID=$(parsec histories create_history | jq .id -r)
        DATASET_ID=$(parsec tools paste_content 'asdf' $HISTORY_ID | jq '.outputs[0].id' -r)
        OUTPUT_ID=$(parsec tools run_tool $HISTORY_ID cat '{"input1": {"src": "hda", "id": "'$DATASET_ID'"}}' | jq '.outputs | .[0].id' -r)
        sleep 10
        echo "run parsec jobs show_job"
        parsec jobs show_job --full_details $OUTPUT_ID
        # TODO: find a way to get a log trace that this tool actually was running with singularity
        #parsec jobs show_job --full_details $OUTPUT_ID | jq .stderr | grep singularity
    fi
    docker-compose logs --tail 50
    # Define start functions
    docker_exec() {
        cd $WORKING_DIR
        docker-compose exec galaxy-web "$@"
    }
    docker_exec_run() {
        cd $WORKING_DIR
        docker-compose exec galaxy-web "$@"
    }
    docker_run() {
        cd $WORKING_DIR
        docker-compose run "$@"
    }
else
    export WORKING_DIR="$TRAVIS_BUILD_DIR"
    export DOCKER_RUN_CONTAINER="quay.io/bgruening/galaxy"
    INSTALL_REPO_ARG=""
    SAMPLE_TOOLS=$GALAXY_HOME/ephemeris/sample_tool_list.yaml
    cd "$WORKING_DIR"
    if [[ "$(docker images -q quay.io/bgruening/galaxy 2> /dev/null)" == "" ]];
    then
	docker build -t quay.io/bgruening/galaxy galaxy/
    fi
    mkdir -p local_folder
    docker run -d -p 8080:80 -p 8021:21 -p 8022:22 \
           --name galaxy \
           --privileged=true \
           -v `pwd`/local_folder:/export/ \
           -e GALAXY_CONFIG_ALLOW_USER_DATASET_PURGE=True \
           -e GALAXY_CONFIG_ALLOW_LIBRARY_PATH_PASTE=True \
           -e GALAXY_CONFIG_ENABLE_USER_DELETION=True \
           -e GALAXY_CONFIG_ENABLE_BETA_WORKFLOW_MODULES=True \
           -v /tmp/:/tmp/ \
           quay.io/bgruening/galaxy
    sleep 30
    docker logs galaxy
    # Define start functions
    docker_exec() {
        cd $WORKING_DIR
        docker exec -t -i galaxy "$@"
    }
    docker_exec_run() {
        cd $WORKING_DIR
        docker run quay.io/bgruening/galaxy "$@"
    }
    docker_run() {
        cd $WORKING_DIR
        docker run "$@"
    }
fi

docker ps

set -e

echo " "
echo "####"
echo "# Test submitting jobs to an external slurm cluster"
echo "####"
echo " "
if [ ! "${COMPOSE_SLURM}" ] && [ ! "${KUBE}" ] && [ ! "${COMPOSE_CONDOR_DOCKER}" ] && [ ! "${COMPOSE_SLURM_SINGULARITY}" ]
then
    # For compose slurm is already included and thus tested
    cd $TRAVIS_BUILD_DIR/test/slurm/ && bash test.sh && cd $WORKING_DIR
fi

echo " "
echo "####"
echo "# Test Web api"
echo "####"
echo " "
if [ "${COMPOSE_CONDOR_DOCKER}" ]
then
    docker-compose logs --tail 50
fi
echo "Waiting for Galaxy at ${BIOBLEND_GALAXY_URL} to come up."
# galaxy-wait -g $BIOBLEND_GALAXY_URL --timeout 300
curl -v \
     --connect-timeout 10 \
     --max-time 10 \
     --retry 10 \
     --retry-delay 0 \
     --retry-max-time 300 \
     --fail \
     $BIOBLEND_GALAXY_URL/api/version

echo " "
echo "####"
echo "# Test self-signed HTTPS"
echo "####"
echo " "
docker_run -d --name httpstest -p 443:443 -e "USE_HTTPS=True" $DOCKER_RUN_CONTAINER
# TODO 19.05
# - sleep 90s && curl -v -k --fail https://127.0.0.1:443/api/version
#- echo | openssl s_client -connect 127.0.0.1:443 2>/dev/null | openssl x509 -issuer -noout| grep selfsigned
docker logs httpstest && docker stop httpstest && docker rm httpstest

echo " "
echo "####"
echo "# Test FTP Server upload"
echo "####"
echo " "
#date > time.txt && \
#curl -v \
#     --connect-timeout 10 \
#     --max-time 5 \
#     --retry 10 \
#     --retry-delay 0 \
#     --retry-max-time 100 \
#     --fail \
#     -T time.txt \
#     ftp://$DCKR_HOST:8021 --user $GALAXY_USER:$GALAXY_USER_PASSWD || true

# Test FTP Server get
#curl -v \
#     --connect-timeout 10 \
#     --max-time 5 \
#     --retry 10 \
#     --retry-delay 0 \
#     --retry-max-time 100 \
#     --fail \
#     ftp://$DCKR_HOST:8021 --user $GALAXY_USER:$GALAXY_USER_PASSWD

echo " "
echo "####"
echo "# Test CVMFS"
echo "####"
echo " "
docker_exec bash -c "service autofs start"
docker_exec bash -c "cvmfs_config chksetup"
docker_exec bash -c "ls /cvmfs/data.galaxyproject.org/byhand"

echo " "
echo "####"
echo "# Test SFTP Server"
echo "####"
echo " "
sshpass -p $GALAXY_USER_PASSWD sftp -v -P 8022 -o User=$GALAXY_USER -o "StrictHostKeyChecking no" $DCKR_HOST <<< $'put time.txt'

echo " "
echo "####"
echo "# Run a ton of BioBlend test against our servers."
echo "####"
echo " "
cd $TRAVIS_BUILD_DIR/test/bioblend/ && . ./test.sh && cd $WORKING_DIR/

echo " "
echo "####"
echo "# Test the 'new' tool installation script"
echo "####"
echo " "
if [ "${COMPOSE_SLURM}" ] || [ "${KUBE}" ] || [ "${COMPOSE_CONDOR_DOCKER}" ] || [ "${COMPOSE_SLURM_SINGULARITY}" ]
then
    # Compose uses the online installer (uses the running instance)
    sleep 10
    docker_exec_run shed-tools install -g "http://${DCKR_HOST}:80" -a admin -t "$SAMPLE_TOOLS"
else
    docker_exec_run install-tools "$SAMPLE_TOOLS"
fi

echo " "
echo "####"
echo "# Test the Conda installation"
echo "####"
echo " "
docker_exec_run bash -c 'export PATH=$GALAXY_CONFIG_TOOL_DEPENDENCY_DIR/_conda/bin/:$PATH && conda --version && conda install samtools -c bioconda --yes'
# Test Docker in Docker, used by Interactive Environments; This needs to be at the end as Docker takes some time to start.
#- docker_exec docker info
# Check if the database image matches the current galaxy version

if [ "${COMPOSE_SLURM}" ] || [ "${KUBE}" ] || [ "${COMPOSE_CONDOR_DOCKER}" ] || [ "${COMPOSE_SLURM_SINGULARITY}" ]
then
    cd $WORKING_DIR && bash ./dumpsql.sh
    git diff --exit-code $WORKING_DIR/galaxy-postgres/init-galaxy-db.sql.in || ( echo "Database dump does not equal dump in repository" && false )
fi

echo " "
echo "####"
echo "# The end"
echo "####"
echo " "
