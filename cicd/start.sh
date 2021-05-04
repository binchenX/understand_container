#!/usr/bin/env bash

# the script is running from /opt/code-deployagent
# we need to cd to the deployment-archive for each deployment
cd "$(dirname "${BASH_SOURCE[0]}")/.."
docker run --name book_uc -d -p 8000:8000 -v ${PWD}:/docs squidfunk/mkdocs-material

