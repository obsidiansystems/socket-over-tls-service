let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/archive/0f8f64b54ed07966b83db2f20c888d5e035012ef.tar.gz";
  pkgs = import nixpkgs {};

  serverCertFile = serverCert + "/server.crt";
  serverCert = pkgs.stdenv.mkDerivation {
    name = "server-cert";
    buildInputs = [ pkgs.openssl ];
    src = ./test/data/cert;
    installPhase =
      ''
        mkdir -p $out
        cp $src/server.crt $out/
      '';
  };
in {
  # Forward read/writes to the given socket file to a server over TLS
  cardano-socket-forward = pkgs.writeScriptBin "cardano-socket-forward" ''
    #!${pkgs.runtimeShell}

    # Script takes 4 arguments
    if [ -z "$4" ]; then
      echo "Usage: $0 <server_hostname> <server_port_number> <target_socket_file> <client_private_pem_file>"
      exit 1
    fi

    SERVER_HOST="$1"
    SERVER_PORT="$2"
    SOCKET_FILE="$3"
    CLIENT_PRIVATE_PEM_FILE="$4"

    SERVER_PUBLIC_CERT_FILE=${serverCertFile}

    echo "Forwarding $SOCKET_FILE to $SERVER_HOST:$SERVER_PORT..." >&2
    ${pkgs.socat}/bin/socat UNIX-LISTEN:$SOCKET_FILE,reuseaddr,fork openssl:$SERVER_HOST:$SERVER_PORT,cert=$CLIENT_PRIVATE_PEM_FILE,cafile=$SERVER_PUBLIC_CERT_FILE,openssl-min-proto-version=TLS1.3
  '';
}
