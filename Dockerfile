ARG LEAN_VERSION=v4.28.0-rc1

FROM ubuntu:22.04 AS builder

ARG LEAN_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl git ca-certificates && \
    rm -rf /var/lib/apt/lists/*

RUN curl -sSf https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh \
    | bash -s -- -y --default-toolchain none
ENV PATH="/root/.elan/bin:${PATH}"

COPY . /opt/probe-lean
WORKDIR /opt/probe-lean

RUN ./tools/bash/install.sh --lean-version "${LEAN_VERSION}"

FROM ubuntu:22.04

ARG LEAN_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /root/.local/bin/probe-lean-${LEAN_VERSION} /usr/local/bin/probe-lean
COPY --from=builder /root/.local/lib/probe-lean-${LEAN_VERSION}/ /usr/local/lib/probe-lean/

RUN curl -sSf https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh \
    | bash -s -- -y --default-toolchain none
ENV PATH="/root/.elan/bin:${PATH}"

ENTRYPOINT ["probe-lean"]
