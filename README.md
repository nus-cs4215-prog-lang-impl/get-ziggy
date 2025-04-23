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
docker run -it ghcr.io/nus-cs4215-prog-lang-impl/get-ziggy
```

If you want to test your local changes in docker, do:

```bash
docker run -it -v $(pwd):/app ghcr.io/nus-cs4215-prog-lang-impl/get-ziggy
```

### Building the docker image from source

```bash

nix build .#docker
docker load < result
docker run -it zig-antlr-shell
```

### To build a zig executable of the compiler

```bash
zig build-exe main.zig --name my_compiler
```

To run the executable:

```bash
./my_compiler test.json
```

This should compile your rust code into a microcode
