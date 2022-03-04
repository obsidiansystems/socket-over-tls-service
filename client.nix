{ pkgs ? import ./dep/nixpkgs {}
, serverCertFile ? ./test/data/cert/server.crt
}:
{
  # Client script for connecting to the NixOS service defined in 'service.nix'
  socket-forward-client = pkgs.writeScriptBin "socket-forward-client" ''
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
    ${pkgs.socat}/bin/socat UNIX-LISTEN:$SOCKET_FILE,reuseaddr,fork openssl:$SERVER_HOST:$SERVER_PORT,cert="$CLIENT_PRIVATE_PEM_FILE",cafile="$SERVER_PUBLIC_CERT_FILE",openssl-min-proto-version=TLS1.3
  '';
}
