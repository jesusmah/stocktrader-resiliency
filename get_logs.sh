#!/bin/bash

################
## PARAMETERS ##
################
# Unique identifier for the pods
# Tipically the helm release name
UNIQUE_ID=$1
TIME=$2

######################
## output directory ##
######################
DIRECTORY="logs"

##########
## Main ##
##########

# Check the unique identifier
if [ -z "${UNIQUE_ID}" ]; then
  echo "[ERROR]: please provide a unique identifier for your pods as a parameter."
  exit 1
fi

# Build --since param for kubectl logs command
SINCE=""
if [ ${TIME} ]; then
  SINCE="--since=${TIME}m"
fi

# Clean up the log directory
if [ -d "${DIRECTORY}" ]; then
  rm -rf ${DIRECTORY} && mkdir ${DIRECTORY}
else
  mkdir ${DIRECTORY}
fi

echo "Obtaining all log files for the helm release ${UNIQUE_ID}"
echo
for pod in `kubectl get pods | awk '{print $1}' | grep ${UNIQUE_ID}`
do
  echo "Getting logs for pod ${pod}..."
  kubectl logs ${SINCE} ${pod} > ${DIRECTORY}/${pod}.txt
  echo "Done"
done
echo
echo "All logs were obtained and stored in ${DIRECTORY}"

exit 0
