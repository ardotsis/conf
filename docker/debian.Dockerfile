FROM debian:bookworm

ARG GUEST_APP_DIR
ARG GUEST_ENTRYPOINT_FILE

COPY . ${GUEST_APP_DIR}
RUN cp ${GUEST_ENTRYPOINT_FILE} /usr/local/bin/
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

ENTRYPOINT ["entrypoint.sh"]
