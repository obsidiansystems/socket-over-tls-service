# Based on: https://nix.dev/tutorials/integration-testing-using-virtual-machines
let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/archive/0f8f64b54ed07966b83db2f20c888d5e035012ef.tar.gz";
  pkgs = import nixpkgs {};
  client = import ./client.nix {pkgs = pkgs; serverCertFile = serverCertFile;};

  port = 9186;
  serverSocketFile = "/home/socket-forward/forward.socket";
  socketUser = "socket-forward";
  message = "test 123";
  clientHome = "/home/socket-client";
  clientSocketFile = clientHome + "/client.sock";
  clientSocketUser = "socket-client";

  serverCertFile = certs + "/server.crt";
  # TODO: generate certificates using 'test_gen_certs.sh' as part of 'buildPhase'
  certs = pkgs.stdenv.mkDerivation {
    name = "test-certs";
    buildInputs = [ pkgs.openssl ];
    src = ./test/data/cert;
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

      # Enable and configure 'socket-over-tls' NixOS service
      services.socket-over-tls = {
        enable = true;
        user = "socket-forward";
        serverSecretPemFile = certs + "/server.pem";
        clientPublicCrtFile = certs + "/client.crt";
        socketFile = serverSocketFile;
        listenPort = 9186;
      };

      # Write to the socket whatever is read from it
      systemd.services.echo-socket = {
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        restartIfChanged = true;
        script = ''
          #!${pkgs.runtimeShell}

          ${pkgs.socat}/bin/socat UNIX-LISTEN:${serverSocketFile},reuseaddr,fork exec:'cat'
        '';
        serviceConfig = {
          User = "socket-forward";
          Restart = "always";
          RestartSec = 1;
        };
      };

      users = {
        mutableUsers = false;
        users = {
          # For ease of debugging the VM as the `root` user
          root.password = "";

          # The user who runs the 'socket-over-tls' service
          socket-forward = {
            isNormalUser = true;
            home = "/home/socket-forward";
            group = "socket-forward";
          };
        };
      };
    };

    client = {
      imports = [
        sharedModule
      ];

      users = {
        mutableUsers = false;
        users = {
          # For ease of debugging the VM as the `root` user
          root.password = "";

          # The user who runs the 'socket-over-tls' service
          socket-client = {
            isNormalUser = true;
            home = clientHome;
            group = "socket-client";
          };
        };
      };

      systemd.services.socket-client = {
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        restartIfChanged = true;
        script = ''
          #!${pkgs.runtimeShell}

          ${client.socket-forward-client}/bin/socket-forward-client server ${toString port} ${clientSocketFile} ${certs + "/client.pem"}
        '';
        serviceConfig = {
          User = clientSocketUser;
          WorkingDirectory = clientHome;
          Restart = "always";
          RestartSec = 1;
        };
      };

    };
  };

  # Disable linting for simpler debugging of the testScript
  skipLint = true;

  testScript = ''
    import subprocess

    def expect(actual, expected, message):
      msg='{} (actual: {}, expected: {})'.format(message, actual, expected)
      assert actual == expected, msg

    start_all()
    server.wait_for_file("${serverSocketFile}")
    server.wait_for_open_port(${toString port})

    print("Running nc...")
    client.wait_for_file("${clientSocketFile}")
    stdout = client.succeed("echo '${message}' |sudo -u ${clientSocketUser} ${pkgs.netcat}/bin/nc -U ${clientSocketFile}")

    print("Running assertions...")
    expect(stdout, "${message}", "server receives correct message")
  '';
})