FROM debian:bookworm
# FROM ubuntu:jammy

COPY  . /app
RUN cp /app/docker/entrypoint.sh /usr/local/bin/
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
