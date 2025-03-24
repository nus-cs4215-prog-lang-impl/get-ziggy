# Implementing Rust in Zig

## Getting Started

### Generating the parser

While there is a pre-generated parser, it may not work depending on versions of the tools used. To recreate the generation,
follow the following steps:

1. Go to `./parser`
3. Run `transformGrammars.py`
4. Run `antlr4 -Dlanguage=Python3 RustLexer.g4 RustParser.g4`
5. Test using `python3 testing_script.py`

### Running the parser tests

To check outputs of the parser, just run:

```bash
./scripts/run_tests.sh
```

## Development

### Buidling a development shell/docker

To build a development shell with the required dependencies, run:

```bash
nix develop .
```

Or, if you want a docker container, run:

```bash
nix build .#docker
docker load < result
docker run -it zig-antlr-shell
```

## TODO

- [ ] Build docker image and send to ghcr.io
