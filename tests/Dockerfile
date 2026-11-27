FROM ubuntu:26.04
ARG CHEZMOI_VERSION=2.74.2
# Bump ARG and digest together from the release checksums file.
ARG CHEZMOI_SHA256=5f2024119a1860f18f2243b892dd43a79f0fefe2ebef9786ee143f4d5fd69ccb
RUN apt-get update \
  && apt-get install -y --no-install-recommends shellcheck python3 git curl ca-certificates \
  && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL -o /tmp/chezmoi.tar.gz \
    "https://github.com/twpayne/chezmoi/releases/download/v${CHEZMOI_VERSION}/chezmoi_${CHEZMOI_VERSION}_linux_amd64.tar.gz" \
  && echo "${CHEZMOI_SHA256}  /tmp/chezmoi.tar.gz" | sha256sum -c - \
  && tar -xzf /tmp/chezmoi.tar.gz -C /usr/local/bin chezmoi \
  && rm -f /tmp/chezmoi.tar.gz \
  && chezmoi --version
WORKDIR /work
CMD ["./tests/test.sh"]
