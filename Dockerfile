ARG LEAN_VERSION=v4.28.0-rc1

FROM ubuntu:22.04

ARG LEAN_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl git ca-certificates && \
    rm -rf /var/lib/apt/lists/*

RUN curl -sSf https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh \
    | bash -s -- -y --default-toolchain none
ENV PATH="/root/.elan/bin:/root/.local/bin:${PATH}"

RUN curl -sSfL https://raw.githubusercontent.com/Beneficial-AI-Foundation/probe-lean/main/tools/bash/install.sh \
    | bash -s -- --lean-version "${LEAN_VERSION}"

ENTRYPOINT ["probe-lean"]
