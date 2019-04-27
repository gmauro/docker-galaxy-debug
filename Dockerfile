From docker_galaxy_debug-base

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update \
 && apt-get install -q --no-install-recommends -y \
    sudo \
    sshpass \
    openssh-client \
    uuid-runtime \
 && apt-get autoremove \
 && apt-get clean \
 && pip install ephemeris \
 && git clone https://github.com/gmauro/ansible-docker \
 && cd ansible-docker \
 && ansible-playbook -i localhost, local.yml -e "@defaults/main.yml" \
 && cd .. \
 && rm -rf ansible-docker

RUN \
  adduser --quiet --shell /bin/bash user && \
  adduser user sudo && \
  adduser user docker && \
  echo "user ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/user && \
  chmod 0440 /etc/sudoers.d/user && \
  mkdir -p /home/user/build_dir && \
  git clone https://github.com/gmauro/docker-galaxy-stable.git /home/user/build_dir && \
  chown -R user:user /home/user

USER user
WORKDIR /home/user

CMD ["tail", "-f", "/dev/null"]
