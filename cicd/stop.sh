#!/usr/bin/env bash

# stop the docker container
if docker ps -a | grep book_uc; then
    docker stop book_uc
    docker rm book_uc
    echo "book_uc is stop and removed"
fi
