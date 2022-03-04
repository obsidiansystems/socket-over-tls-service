#!/bin/bash

set -e

SERVER_HOST=localhost

cert() {
   openssl genrsa -out $1.key 4096
   # Note: answer localhost for your Common Name (CN)
   # other answers don't really matter
   openssl req -new -key $1.key -x509 -days 3653 -out $1.crt \
     -subj "/C=na/ST=na/L=na/O=na/OU=na/CN=$SERVER_HOST/emailAddress=na"
   cat $1.key $1.crt > $1.pem
   chmod 600 $1.key $1.pem
}

cert server
cert client

openssl dhparam -out dhparams.pem 4096
cat dhparams.pem >> server.pem

echo "Done"
