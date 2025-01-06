#!/bin/bash

nc -zv localhost 8443

# build the image and run the container
docker build -t my-code-server .
docker run -d --rm -p 8443:8443 --name code-server my-code-server
