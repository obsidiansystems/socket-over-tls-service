let
  # Pin nixpkgs, see pinning tutorial for more details
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/archive/0f8f64b54ed07966b83db2f20c888d5e035012ef.tar.gz";
  pkgs = import nixpkgs {};

  # Single source of truth for all tutorial constants
  database      = "postgres";
  schema        = "api";
  table         = "todos";
  username      = "authenticator";
  password      = "mysecretpassword";
  webRole       = "web_anon";

  port = 9186;
  socketFile = "/home/socket-forward/forward.socket";
  socketUser = "socket-forward";

  certs = pkgs.stdenv.mkDerivation {
    name = "test-certs";

    buildInputs = [ pkgs.openssl ];

    src = ./cert;

    installPhase =
      ''
        mkdir -p $out
        cp -r $src/* $out/
      '';
  };

  # NixOS module shared between server and client
  sharedModule = {
    # Since it's common for CI not to have $DISPLAY available, we have to explicitly tell the tests "please don't expect any screen available"
    virtualisation.graphics = false;
  };

in pkgs.nixosTest ({
  # NixOS tests are run inside a virtual machine, and here we specify system of the machine.
  system = "x86_64-linux";

  nodes = {
    server = { config, pkgs, ... }: {
      imports = [
        sharedModule
        ./service.nix
      ];

      networking.firewall.allowedTCPPorts = [ port ];

      services.socket-over-tls = {
        enable = true;
        user = "socket-forward";
        serverSecretPemFile = certs/server.pem;
        clientPublicCrtFile = certs/client.crt;
        socketFile = socketFile;
        listenPort = 9186;
      };

      users = {
        mutableUsers = false;
        users = {
          # For ease of debugging the VM as the `root` user
          root.password = "";

          # Create a system user that matches the database user so that we
          # can use peer authentication.  The tutorial defines a password,
          # but it's not necessary.
          "${username}".isSystemUser = true;

          socket-forward = {
            isNormalUser = true;
            home = "/home/socket-forward";
            group = "socket-forward";
          };
        };
      };

      systemd.services.netcat = {
        wantedBy = [ "multi-user.target" ];
        after = [ "socket-over-tls.service" ];
        script = "${pkgs.netcat}/bin/nc -lkU ${socketFile}";
        serviceConfig.User = socketUser;
      };

      systemd.services.socket-write = {
        wantedBy = [ "multi-user.target" ];
        after = [ "netcat.service" ];
        script = "echo 'test 123' |${pkgs.netcat}/bin/nc -U ${socketFile}";
        serviceConfig.User = socketUser;
      };
    };
  };

  # Disable linting for simpler debugging of the testScript
  skipLint = true;

  testScript = ''
    import subprocess

    print("Running socat...")
    subprocess.run(["${pkgs.socat}/bin/socat", "UNIX-LISTEN:client.sock,reuseaddr,fork", "openssl:server:${toString port},cert=${certs/client.pem},cafile=${certs/server.crt},openssl-min-proto-version=TLS1.3"])

    print("Running nc...")
    result = subprocess.run(["${pkgs.netcat}/bin/nc", "-lU", "${socketFile}"], capture_output=True, text=True)

    print("Running assertion...")
    assert result.stdout == "test 123", "what does this string do, I don't know"
  '';
})