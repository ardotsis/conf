FROM debian:bookworm

ARG GUEST_APP_DIR
ARG GUEST_DOCKER_DIR

# Install source code
COPY . "${GUEST_APP_DIR}"
RUN cp "${GUEST_DOCKER_DIR}/entrypoint.sh" /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y \
    openssh-server \
    ca-certificates \
    sudo \
    curl \
    git \
    man \
    zsh \
    tree \
    fzf

RUN chmod +x "${GUEST_DOCKER_DIR}/pre_install.sh"
RUN ".${GUEST_DOCKER_DIR}/pre_install.sh" "${GUEST_APP_DIR}"


ENTRYPOINT ["entrypoint.sh"]
