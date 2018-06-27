#!/bin/bash

################
## PARAMETERS ##
################
PROXY_IP=$1
BFF_NODEPORT=$2
THREAD=$3
NUM_ITERATIONS=$4
NUM_USERS=$5
NUMBER_OF_SHARES=$6
COOKIE_FILE=$7
DIRECTORY=$8

###################
## Share symbols ##
###################
IBM="IBM"
GOOGLE="GOOG"
APPLE="AAPL"
SYMBOLS="${IBM} ${GOOGLE} ${APPLE}"

#######################
## HTTP return codes ##
#######################
CREATE_CODE=302
RETRIEVE_CODE=200
UPDATE_CODE=302
SUMMARY_CODE=200

##############
## COMMANDS ##
##############

create()
{
  echo "[`date '+%H:%M:%S'`] [${THREAD}] - Creating user ${USER}..."
  RESPONSE=`curl -b ${COOKIE_FILE} -o /dev/null -w '%{http_code}' -s "https://${PROXY_IP}:${BFF_NODEPORT}/trader/addPortfolio" \
                    -H "Origin: https://${PROXY_IP}:${BFF_NODEPORT}" \
                    -H "Referer: https://${PROXY_IP}:${BFF_NODEPORT}/trader/addPortfolio" \
                    --data owner=${USER}\&submit=Submit \
                    --compressed --insecure`
  if [ ${RESPONSE} -ne ${CREATE_CODE} ]; then
    echo "[`date '+%H:%M:%S'`] [${THREAD}] - An error occured creating the user ${USER}"
    exit 1
  fi
  echo "[`date '+%H:%M:%S'`] [${THREAD}] - Done"
}

update()
{
  RESPONSE=`curl -b ${COOKIE_FILE} -o /dev/null -w '%{http_code}' -s "https://${PROXY_IP}:${BFF_NODEPORT}/trader/addStock?owner=${USER}" \
                    -H "Origin: https://${PROXY_IP}:${BFF_NODEPORT}" \
                    -H "Referer: https://${PROXY_IP}:${BFF_NODEPORT}/trader/addStock?owner=${USER}" \
                    --data symbol=${SYMBOL}\&shares=${NUMBER_OF_SHARES}\&submit=Submit \
                    --compressed --insecure`
  echo "RESPONSE: ${RESPONSE} || Iteration ${iteration} - user ${USER} - symbol ${SYMBOL}" >> output/return_code.txt
  if [ ${RESPONSE} -ne ${UPDATE_CODE} ]; then
    echo "[`date '+%H:%M:%S'`] [${THREAD}] - An error occured adding ${NUMBER_OF_SHARES} ${SYMBOL} shares to ${USER} stock"
    exit 1
  fi
}

retrieve()
{
  RESPONSE=`curl -b ${COOKIE_FILE} -o ${DIRECTORY}/retrieve_${1}.html -w '%{http_code}' -s "https://${PROXY_IP}:${BFF_NODEPORT}/trader/viewPortfolio?owner=${USER}" \
                      -H "Origin: https://${PROXY_IP}:${BFF_NODEPORT}" \
                      -H "Referer: https://${PROXY_IP}:${BFF_NODEPORT}/trader/summary" \
                      --compressed --insecure`
  if [ ${RESPONSE} -ne ${RETRIEVE_CODE} ]; then
    echo "[`date '+%H:%M:%S'`] [${THREAD}] - An error occured retrieving the info for user ${USER}"
    exit 1
  fi
}

summary()
{
  echo "[`date '+%H:%M:%S'`] [${THREAD}] - Getting the ${1} summary report..."
  RESPONSE=`curl -b ${COOKIE_FILE} -o ${DIRECTORY}/summary_${1}.html -w '%{http_code}' -s "https://${PROXY_IP}:${BFF_NODEPORT}/trader/summary" \
                      -H "Origin: https://${PROXY_IP}:${BFF_NODEPORT}" \
                      -H "Referer: https://${PROXY_IP}:${BFF_NODEPORT}/trader/summary" \
                      --compressed --insecure`
  if [ ${RESPONSE} -ne ${SUMMARY_CODE} ]; then
    echo "[`date '+%H:%M:%S'`] [${THREAD}] - An error occured getting the ${1} summary page"
    exit 1
  fi
  echo "[`date '+%H:%M:%S'`] [${THREAD}] - Done"
}

######################################
##                                  ##
##               TEST               ##
##                                  ##
######################################

echo "[`date '+%H:%M:%S'`] [${THREAD}] - Begin of script"

# Iterations
for iteration in $(seq $NUM_ITERATIONS)
do
  echo "[`date '+%H:%M:%S'`] [${THREAD}] - Begin Iteration $iteration"

  # For each user
  for user in $(seq $NUM_USERS)
  do

    # Set user
    USER="User_${THREAD}_${user}"

    # Create user if first iteration
    if [ ${iteration} -eq 1 ]; then
      create
    fi

    # Add shares of each symbol
    for symbol in ${SYMBOLS}
    do
      SYMBOL=${symbol}
      update
    done
  done

  # Results after an iteration
  summary "thread_${THREAD}_iteration_${iteration}"
  #export_db "iteration_${iteration}"

  echo "[`date '+%H:%M:%S'`] [${THREAD}] - End Iteration $iteration"
done
# Mark this thread as done
touch output/thread_${THREAD}_done.txt

exit 0
