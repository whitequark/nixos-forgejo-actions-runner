{ lib, ... }:

let
  serverName = builtins.getEnv "HOST";
  siteConfig = lib.importTOML (./. + "/site/${serverName}.toml");

  host = let
    fqdnParts = builtins.match "([a-z0-9-]+)\\.([a-z.]+)" serverName;
  in {
    name = builtins.elemAt fqdnParts 0;
    domain = builtins.elemAt fqdnParts 1;
  };
in
{
  networking = {
    useNetworkd = true;
    usePredictableInterfaceNames = true;
    hostName = host.name;
    domain = host.domain;
  };

  systemd.network = let
    mkAddresses = builtins.map (route: {
      Address = route.address;
      Peer = route.peer;
    });
  in (if siteConfig.net.ipv6 ? ether && siteConfig.net.ipv4 ? ether then {
    enable = true;
    networks."40-wan6" = {
      matchConfig.Name = "enx${builtins.replaceStrings [":"] [""] siteConfig.net.ipv6.ether}";
      address = [siteConfig.net.ipv6.address];
      gateway = [siteConfig.net.ipv6.gateway];
      addresses = if siteConfig.net.ipv6 ? routes then mkAddresses siteConfig.net.ipv6.routes else [];
      dns = siteConfig.dns.servers;
    };
    networks."40-wan4" = {
      matchConfig.Name = "enx${builtins.replaceStrings [":"] [""] siteConfig.net.ipv4.ether}";
      address = [siteConfig.net.ipv4.address];
      gateway = [siteConfig.net.ipv4.gateway];
      addresses = if siteConfig.net.ipv4 ? routes then mkAddresses siteConfig.net.ipv4.routes else [];
      dns = siteConfig.dns.servers;
    };
  } else {
    enable = true;
    networks."40-wan" = {
      matchConfig.Name = (if siteConfig.net ? ether
        then "enx${builtins.replaceStrings [":"] [""] siteConfig.net.ether}"
        else "en*");
      address =
        (lib.optional (siteConfig.net ? ipv4) siteConfig.net.ipv4.address) ++
        (lib.optional (siteConfig.net ? ipv6) siteConfig.net.ipv6.address);
      gateway =
        (lib.optional (siteConfig.net ? ipv4) siteConfig.net.ipv4.gateway) ++
        (lib.optional (siteConfig.net ? ipv6) siteConfig.net.ipv6.gateway);
      addresses =
        (if siteConfig.net.ipv6 ? routes then mkAddresses siteConfig.net.ipv6.routes else []) ++
        (if siteConfig.net.ipv4 ? routes then mkAddresses siteConfig.net.ipv4.routes else []);
      dns = siteConfig.dns.servers;
    };
  });
}
