#!/bin/bash

set -ex

# Save built docker image and push it to k8 cache.
#
# This won't be necessary if it is pushed to dockerhub
# or another registry server.

docker-compose build
docker tag dna-admin_web dna-admin:0.1
docker save dna-admin > dna-admin.tar
microk8s ctr image import dna-admin.tar

microk8s kubectl delete deployment.apps/dna-admin || :
microk8s kubectl apply -f dna-k8.yaml
