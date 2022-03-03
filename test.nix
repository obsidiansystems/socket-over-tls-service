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
  serverSocketFile = "/home/socket-forward/forward.socket";
  socketUser = "socket-forward";
  message = "test 123";
  clientSocketFile = "client.sock";

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

      services.socket-over-tls = {
        enable = true;
        user = "socket-forward";
        serverSecretPemFile = certs + "/server.pem";
        clientPublicCrtFile = certs + "/client.crt";
        socketFile = serverSocketFile;
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
    };

    client = {
      imports = [ sharedModule ];
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
    server.execute("sudo -u socket-forward ${pkgs.netcat}/bin/nc -lU ${serverSocketFile} 2> netcat.log >&2 &")
    server.succeed("echo $! > netcat.pid")
    server.wait_for_file("${serverSocketFile}")
    server.wait_for_open_port(${toString port})

    print("Running socat...")
    client.execute("${pkgs.socat}/bin/socat UNIX-LISTEN:${clientSocketFile},reuseaddr,fork openssl:server:${toString port},cert=${certs + "/client.pem"},cafile=${certs + "/server.crt"},openssl-min-proto-version=TLS1.3 2> socat.log >&2 &")

    print("Running nc...")
    client.wait_for_file("${clientSocketFile}")
    client.succeed("echo '${message}' |${pkgs.netcat}/bin/nc -U ${clientSocketFile}")
    server.succeed("wait $(cat netcat.pid)")
    stdout = server.succeed("cat netcat.log")

    print("Running assertions...")
    expect(stdout, "${message}", "server receives correct message")
  '';
})