{
  description = "Development environment with Zig and ANTLR";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            zig
            antlr4
            jdk # Required for ANTLR
            python312
            python312Packages.antlr4-python3-runtime
          ];

          shellHook = ''
            echo "Dev environment loaded with Zig and ANTLR"
            echo "Zig version: $(zig version)"
            echo "ANTLR version: $(antlr4)"
          '';
        };
      });
}
