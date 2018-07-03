#!/bin/bash
# Randomly delete pods in a Kubernetes namespace.

echo "[`date '+%Y-%m-%d %H:%M:%S'`]: Begin of script"
echo

DELAY=${1:-30}
NAMESPACE=${2:-default}
UNIQUE_ID=$3

if [ -z ${UNIQUE_ID} ]; then
  echo "[ERROR]: Please specify a unique identifier for your Helm release"
  exit 1
fi

echo "Delay: ${DELAY}"
echo "Namespace: ${NAMESPACE}"
echo "Unique ID (Helm release): ${UNIQUE_ID}"
echo

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
  echo
  sleep "${DELAY}"
done
