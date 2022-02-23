# Overview

A NixOS service that forwards a local socket over TLS using TLS client authentication. This means a Unix domain socket on the server can be written to by a client that is in posession of the client private key and can connect to the given TCP port on the server.

# Running

The example below will expose the socket file `/home/socket-forward/forward.socket` on the server over TLS. On the client machine we will use `socat` to create a local client socket which, when written to or read from, will be equivalent to writing to or reading from the server socket file.

## On the server

On the NixOS server

1. Clone this repo to `/etc/nixos/socket-over-tls-service`:

```
cd /etc/nixos
git clone https://github.com/obsidiansystems/socket-over-tls-service.git
```

2. Generate the client and server certificates inside `socket-over-tls-service/cert`:

```
cd socket-over-tls-service
mkdir cert
cd cert
bash ../test_gen_certs.sh
```

3. Modify `/etc/nixos/configuration.nix` by first adding `./socket-over-tls-service/service.nix` to `imports`:

```
  imports =
    [ <...existing imports...>
      ./socket-over-tls-service/service.nix
    ];
```

and then by adding the attributes below:

```
  # Add user and group
  users.users.socket-forward = {
    isNormalUser = true;
    home = "/home/socket-forward";
    group = "socket-forward";
  };

  # Forward socket file over TLS
  services.socket-over-tls = {
    enable = true;
    user = "socket-forward";
    serverSecretPemFile = ./socket-over-tls-service/cert/server.pem;
    clientPublicCrtFile = ./socket-over-tls-service/cert/client.crt;
    socketFile = "/home/socket-forward/forward.socket";
    listenPort = 9186;
  };
```

and run `nixos-rebuild switch` to start the service.

4. Create a socket file using *netcat* to test the service as the *socket-forward* user: `sudo -H -u socket-forward nc -lkU /home/socket-forward/forward.socket`

## On the client

1. Copy over the files `client.pem` and `server.crt` from the server to the current directory and run the following command, modifying `SERVER_HOST` as needed:

```
SERVER_HOST=localhost socat UNIX-LISTEN:client.sock,reuseaddr,fork openssl:$SERVER_HOST:9186,cert=client.pem,cafile=server.crt,openssl-min-proto-version=TLS1.3
```

2. Finally, write to the local `client.sock` socket using *netcat*: `echo "test 123" |nc -U client.sock`
   * The string `test 123` should be printed by the `nc` instance from step 4 above.

## Debugging

Run the following command to print the service logs:

```
journalctl --unit socket-over-tls.service --follow
```
