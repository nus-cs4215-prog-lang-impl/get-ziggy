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
        jless
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

      packages.docker = pkgs.dockerTools.buildLayeredImage {
        name = "zig-antlr-shell";
        tag = "latest";
        contents =
          devPackages
          ++ [
            pkgs.bash
            pkgs.busybox
          ];

        # Create app directory and copy project files
        extraCommands = ''
          # Create app directory with proper permissions
          mkdir -m 0755 -p app
          cp -r ${./.}/* app/
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
