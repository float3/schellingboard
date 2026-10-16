# Nix entry points: a NixOS service for hosting SchellingBoard, and a shell
# with the tools the project is developed with. Neither is required to use or
# to work on it — Docker and `make install` remain the documented paths, and
# this file adds a third for people whose machines are already Nix.
{
  description = "SchellingBoard, a scheduling app for participant-driven events";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    systems = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    # services.schellingboard — see docs/public/self-hosting/nixos.md
    nixosModules.schellingboard = ./nix/schellingboard.nix;
    nixosModules.default = self.nixosModules.schellingboard;

    devShells = forAllSystems (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        default = pkgs.mkShell {
          packages = [
            pkgs.bun
            pkgs.nodejs_22
            pkgs.gnumake
            # better-sqlite3 is compiled against Node's ABI on install.
            pkgs.python3
            pkgs.pkg-config
            # For reading the database directly, as the backup guide does.
            pkgs.sqlite
          ];

          shellHook = ''
            echo "make install · make dev · make precommit"
          '';
        };
      }
    );

    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);
  };
}
