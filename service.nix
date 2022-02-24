{ config
, ...
}:
let
  pkgs = import ./dep/nixpkgs {};
  cfg = config.services.socket-over-tls;
in
with pkgs.lib;
{
  options.services.socket-over-tls = {
    enable = mkEnableOption "Unix domain socket over TLS";

    # Run the servie as this user
    user = mkOption {
      type = types.str;
    };

    # NB: Contains private key! Must be kept secret.
    #     The file owner should be `cfg.user`
    #     with `chmod 600` permissions.
    serverSecretPemFile = mkOption {
      type = types.path;
    };

    # Client certificate including client public key.
    clientPublicCrtFile = mkOption {
      type = types.path;
    };

    # The Unix domain socket file to forward
    socketFile = mkOption {
      type = types.str;
    };

    # The TCP port to on which the server will accept incoming TLS connections
    listenPort = mkOption {
      type = types.int;
    };
  };

  config = mkIf cfg.enable {
    systemd.services.socket-over-tls = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      restartIfChanged = true;
      script = ''
        ${pkgs.socat}/bin/socat openssl-listen:${toString cfg.listenPort},reuseaddr,fork,cert=${toString cfg.serverSecretPemFile},cafile=${toString cfg.clientPublicCrtFile},verify=1,openssl-min-proto-version=TLS1.3 UNIX-CONNECT:${cfg.socketFile}
      '';
      serviceConfig = {
        User = cfg.user;
        WorkingDirectory = dirOf cfg.socketFile;
        Restart = "always";
        RestartSec = 1;
      };
    };
  };
}