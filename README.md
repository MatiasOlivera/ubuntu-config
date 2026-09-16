# ubuntu-config
Set-up a fresh Ubuntu installation installing apps and some configs

Installation scripts are grouped by purpose:

- `desktop-apps/` contains final user applications (not for development)
- `development/` contains development tools such as Git and Docker
- `essentials/` contains common Linux utilities.

Each application script exposes an install function that is sourced and called
by `install.sh`.

Install Ubuntu packages and configure Git with flags:

```sh
./install.sh --name "Your Name" --email "you@example.com"
```

Git can also be configured independently:

```sh
./development/git/git-config.sh "Your Name" "you@example.com"
```

## Testing

Its run on a `ubuntu:26.04` Docker image.

```sh
docker build -t ubuntu-config-test .

docker run --rm -v "$PWD:/work" -w /work ubuntu-config-test ./test.sh              # static + source-only (fast, zero-dep, default)
docker run --rm -v "$PWD:/work" -w /work ubuntu-config-test ./test.sh --vm         # same, then Multipass fresh-Ubuntu e2e
docker run --rm -v "$PWD:/work" -w /work ubuntu-config-test ./test.sh --vm --keep  # same, but leave VM running on failure for inspection
```
