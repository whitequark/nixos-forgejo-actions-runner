{ config, lib, pkgs, ... }:

let
  serverName = builtins.getEnv "HOST";
  siteConfig = lib.importTOML (./. + "/site/${serverName}.toml");

  cacheProxyPort = 42000;
in
{
  imports = [
    ./hardware.nix
    ./network.nix
  ];

  nix = {
    gc = {
      automatic = true;
      options = "--delete-older-than 30d";
    };

    settings = {
      experimental-features = "flakes nix-command";
    };
  };

  nixpkgs = {
    flake.source = (import ./npins).nixos;

    hostPlatform = siteConfig.host.platform;
  };

  # Ensure we can build for most major architectures.
  boot.binfmt = {
    emulatedSystems = lib.remove siteConfig.host.platform [
      "aarch64-linux"
      "x86_64-linux"
    ];

    preferStaticEmulators = true;
  };

  # SSH
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;
  };

  users.users.root.openssh.authorizedKeys.keys = siteConfig.ssh.pubkeys;

  # Actions Runner
  services.gitea-actions-runner = {
    package = pkgs.forgejo-runner;

    instances = (lib.attrsets.foldlAttrs (accum: name: runnerConfig: {
      config = accum.config // {
        ${name} = {
          enable = true;
          name = "${name}@${serverName}";
          url = "https://${runnerConfig.forge}";
          tokenFile = pkgs.writeText "token" ''
            TOKEN=${runnerConfig.token}
          '';
          labels = runnerConfig.labels;

          settings = {
            # While the Forgejo Actions administrator manual suggests disabling the cache for
            # slow disks, in practice many actions (like `actions/setup-go`) will assume it exists
            # and time out for a rather long time if it actually doesn't. Thus, we enable the cache
            # unconditionally.
            cache = {
              enable = true;
              host = "host.containers.internal";
              proxy_port = accum.port;
            };
          };
        };
      };

      port = accum.port + 1;
    })
    { config = { }; port = cacheProxyPort; }
    siteConfig.runners).config;
  };

  virtualisation.podman = {
    enable = true;
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];

    # Required for Forgejo Actions Cache to work properly.
    interfaces."podman+" = {
      # There is (to my knowledge) no way to get the size of an attrset. I love Nix.
      allowedTCPPorts = lib.attrsets.mapAttrsToList
        (_: inst: inst.settings.cache.proxy_port)
        config.services.gitea-actions-runner.instances;
    };
  };

  environment.systemPackages = with pkgs; [
    htop
    iftop
    iotop
    iputils
    net-tools
    tcpdump
  ];

  system.stateVersion = "25.11";
}
