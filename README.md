# Overview

A NixOS service that forwards a local Unix domain socket over TLS using TLS client authentication. This means a Unix domain socket on the server can be written to, and read from, by a client that is in posession of the client private key and can connect to the given TCP port on the server.

# Running

The example below will expose the socket file `/home/socket-forward/forward.socket` on the server over TLS. On the client machine we will create a local client socket which, when written to or read from, will be equivalent to writing to or reading from the server socket file.

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

```nix
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

4. In order to test the service, create an "echo socket service" using *socat*. This reads a line from the server socket and writes it back: `sudo -H -u socket-forward socat UNIX-LISTEN:/home/socket-forward/forward.socket,reuseaddr,fork exec:'cat'`

## On the client

1. Copy over the files `client.pem` and `server.crt` from the server (generated under step 2 above) to the current directory and run `client.nix`  as follows:

```
$(nix-build --argstr serverCertFile server.crt ./client.nix)/bin/socket-forward-client localhost 9186 client.sock client.pem
```

2. Finally, write to the local `client.sock` socket using *netcat*: `echo "test 123" |nc -U client.sock`
   * The string `test 123` should be printed (because netcat writes the reponse from the "echo socket service" to stdout)

## Debugging

Run the following command to print the service logs:

```
journalctl --unit socket-over-tls.service --follow
```
