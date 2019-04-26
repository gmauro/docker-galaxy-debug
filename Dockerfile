From docker_galaxy_debug-base

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update \
 && apt-get install -q -y \
    sudo

RUN git clone https://github.com/gmauro/ansible-docker \
 && cd ansible-docker \
 && ansible-playbook -i localhost, local.yml -e "@defaults/main.yml"

RUN \
  adduser --quiet --shell /bin/bash user && \
  adduser user sudo && \
  adduser user docker && \
  chown -R user:user /home/user

RUN echo "user ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/user && \
    chmod 0440 /etc/sudoers.d/user

USER user
WORKDIR /home/user

CMD ["tail", "-f", "/dev/null"]
