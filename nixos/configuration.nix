{ config, lib, pkgs, serverName, siteConfig, ... }:

let
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

  # Tailscale
  services.tailscale = (if siteConfig.net ? tailscale then siteConfig.net.tailscale else {});

  # Actions Runner
  virtualisation.podman.enable = true;

  systemd.services.forgejo-runner = let
    configFile = (pkgs.formats.yaml {}).generate "config.yaml" {
      runner = {
        capacity = siteConfig.runner.capacity;
      };
      server = {
        connections = (builtins.mapAttrs (name: connConfig: {
          url = "https://${connConfig.forge}";
          uuid = "_uuid_${name}_";    # replaced in ExecStartPre
          token = "_token_${name}_";  # replaced in ExecStartPre
          labels = connConfig.labels;
        }) siteConfig.connections);
      };
      # While the Forgejo Actions administrator manual suggests disabling the cache for
      # slow disks, in practice many actions (like `actions/setup-go`) will assume it exists
      # and time out for a rather long time if it actually doesn't. Thus, we enable the cache
      # unconditionally.
      cache = {
        enable = true;
        host = "host.containers.internal";
        proxy_port = cacheProxyPort;
      };
    };
  in {
    enable = true;
    description = "Forgejo Actions runner";
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "podman.service"
    ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      HOME = "/var/lib/forgejo-runner";
      DOCKER_HOST = "unix:///run/podman/podman.sock";
    };
    path = [ pkgs.coreutils pkgs.jq ];
    serviceConfig = {
      DynamicUser = true;
      User = "forgejo-runner";
      StateDirectory = "forgejo-runner";
      WorkingDirectory = "-/var/lib/forgejo-runner";
      Restart = "on-failure";
      RestartSec = 2;
      ExecStartPre = [
        (pkgs.writeShellScript "forgejo-runner-initialize" ''
          cat ${configFile} >$STATE_DIRECTORY/config.yaml
        '')
      ] ++ (lib.mapAttrsToList (name: connConfig:
        let configHash = builtins.hashString "md5" (builtins.toJSON connConfig); in
        pkgs.writeShellScript "forgejo-runner-register-${name}" ''
          set -e
          # make sure to re-register the runner if the configuration changes
          uuidFile=$STATE_DIRECTORY/${name}:${configHash}.uuid
          tokenFile=$STATE_DIRECTORY/${name}:${configHash}.token
          if ! [[ -f $uuidFile && -f $tokenFile ]]; then
            # remove credentials from old generations
            rm -f $STATE_DIRECTORY/${name}:*.uuid
            rm -f $STATE_DIRECTORY/${name}:*.token
            ${pkgs.forgejo-runner}/bin/act_runner register \
              --no-interactive \
              --name '${name}@${serverName}' \
              --instance 'https://${connConfig.forge}' \
              --token '${connConfig.token}'
            jq -r .uuid .runner >$uuidFile
            jq -r .token .runner >$tokenFile
            rm .runner
          fi
          sed -i $STATE_DIRECTORY/config.yaml \
            -e s/_uuid_${name}_/$(cat $uuidFile)/ \
            -e s/_token_${name}_/$(cat $tokenFile)/
        '') siteConfig.connections);
      ExecStart = "${pkgs.forgejo-runner}/bin/act_runner daemon --config config.yaml";
      SupplementaryGroups = [ "podman" ];
    };
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];

    # Required for Forgejo Actions Cache to work properly.
    interfaces."podman+" = {
      # There is (to my knowledge) no way to get the size of an attrset. I love Nix.
      allowedTCPPorts = [ cacheProxyPort ];
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
