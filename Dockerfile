From docker_galaxy_debug-base

ENV DEBIAN_FRONTEND noninteractive

ARG _UID
ARG _GID

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
  addgroup --gid $_GID user && \
  adduser --quiet --shell /bin/bash --uid $_UID --gid $_GID user && \
  adduser user sudo && \
  adduser user docker && \
  echo "user ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/user && \
  chmod 0440 /etc/sudoers.d/user && \
  mkdir -p /home/user/build_dir && \
  mkdir -p /home/user/debug_dir && \
  chown -R user:user /home/user

USER user
WORKDIR /home/user/debug_dir

CMD ["tail", "-f", "/dev/null"]
