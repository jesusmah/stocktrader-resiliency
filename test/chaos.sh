#!/bin/bash
# Randomly delete pods in a Kubernetes namespace.
set -ex

DELAY=${1:-30}
NAMESPACE=${2:-default}
UNIQUE_ID=$3

if [ -z ${UNIQUE_ID} ]; then
  echo "[ERROR]: Please specify a unique identifier for your Helm release"
  exit 1
fi

while true; do
  POD=`kubectl \
    --namespace "${NAMESPACE}" \
    -o 'jsonpath={.items[*].metadata.name}' \
    get pods | \
      tr " " "\n" | \
      grep ${UNIQUE_ID} | \
      grep -v trad | \
      gshuf | \
      head -n 1`
  echo Deleting Pod ${POD}...
  kubectl --namespace "${NAMESPACE}" delete pod ${POD}
  sleep "${DELAY}"
done
