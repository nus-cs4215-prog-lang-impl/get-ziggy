{
  description = "Development environment with Zig and ANTLR";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {inherit system;};

      devPackages = with pkgs; [
        antlr4
        python312
        python312Packages.antlr4-python3-runtime
        python312Packages.pip
        zig
      ];
    in {
      devShells.default = pkgs.mkShell {
        buildInputs = devPackages;
        shellHook = ''
          echo "Dev environment loaded with Zig and ANTLR"
          echo "Zig version: $(zig version)"
          echo "ANTLR version: $(antlr4 | head -n1)" # Show antlr version in shortform
        '';
      };

      packages.docker = pkgs.dockerTools.buildImage {
        name = "zig-antlr-shell";
        tag = "latest";
        copyToRoot = pkgs.buildEnv {
          name = "image-root";
          paths =
            devPackages
            ++ [
              pkgs.bash
              pkgs.busybox
            ];
          pathsToLink = ["/bin" "/lib" "/lib/python3.12/site-packages"];
        };
        runAsRoot = ''
          #!${pkgs.runtimeShell}
          mkdir -p /app
          cp -r ${./.}/* /app/

          # Ensure Python can find the ANTLR runtime
          export PYTHONPATH="${pkgs.python312Packages.antlr4-python3-runtime}/${pkgs.python312.sitePackages}:$PYTHONPATH"
        '';
        config = {
          Cmd = ["bash"];
          WorkingDir = "/app";
          Env = [
            "PYTHONPATH=${pkgs.python312Packages.antlr4-python3-runtime}/${pkgs.python312.sitePackages}"
          ];
        };
      };
    });
}
