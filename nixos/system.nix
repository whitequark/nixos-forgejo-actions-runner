let
  sources = import ./npins;
  pkgs = sources.nixos;
  lib = import "${pkgs}/lib";
in
  import "${pkgs}/nixos" {
    configuration = ./configuration.nix;

    specialArgs = rec {
      serverName = builtins.getEnv "HOST";
      siteConfig = lib.importTOML (./. + "/site/${serverName}.toml");
    };
  }
