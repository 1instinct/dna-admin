#!/bin/bash

set -ex

# Save built docker image and push it to k8 cache.
#
# This won't be necessary if it is pushed to dockerhub
# or another registry server.

docker-compose build

# wait for web to build assets
# FIXME: this doesn't work
docker-compose up
sleep 5 ; docker-compose stop

docker commit dna-admin_web_1 dna-admin_web:0.1
docker tag dna-admin_web:0.1 dna-admin:0.1
docker save dna-admin > dna-admin.tar
microk8s ctr image import dna-admin.tar

microk8s kubectl delete deployment.apps/dna-admin || :
microk8s kubectl apply -f dna-k8.yaml
