FROM ubuntu:26.04
RUN apt-get update \
 && apt-get install -y --no-install-recommends shellcheck python3 git \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /work
CMD ["./tests/test.sh"]
