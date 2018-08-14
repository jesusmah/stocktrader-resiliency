#!/bin/bash

################
## PARAMETERS ##
################
INGRESS="stocktrader.ibm.com"
NUM_THREADS=$1
NUM_ITERATIONS=$2
NUM_USERS=$3
NUMBER_OF_SHARES=$4
MULT_FACTOR=${5:-1}

##################
## Cookies file ##
##################
COOKIE_FILE=$6

######################
## output directory ##
######################
DIRECTORY="output"

#################
## CREDENTIALS ##
#################
ID=stock
PASSWORD=trader

#######################
## HTTP return codes ##
#######################
LOGIN_CODE=302
SUMMARY_CODE=200
DELETE_CODE=200

##############
## COMMANDS ##
##############

login()
{
  echo "[`date '+%H:%M:%S'`] [MAIN] - Logging into the IBM StockTrader application using ${ID} and ${PASSWORD}..."
  RESPONSE=`curl -c ${COOKIE_FILE} -o /dev/null -w '%{http_code}' -s "https://${INGRESS}/trader/login" \
                    -H "Origin: https://${INGRESS}" \
                    -H "Referer: https://${INGRESS}/trader/login" \
                    --data id=${ID}\&password=${PASSWORD}\&submit=Submit \
                    --compressed --insecure`

  if [ ${RESPONSE} -ne ${LOGIN_CODE} ]; then
    echo "[`date '+%H:%M:%S'`] [MAIN] - An error occured logging into the IBM StockTrader application using ${ID} and ${PASSWORD}"
    # Do not exit as the test would finish
    # exit 1
  fi
  echo "[`date '+%H:%M:%S'`] [MAIN] - Done"
  echo
}

summary()
{
  echo "[`date '+%H:%M:%S'`] [MAIN] - Getting the ${1} summary report..."
  RESPONSE=`curl -b ${COOKIE_FILE} -o ${DIRECTORY}/summary_${1}.html -w '%{http_code}' -s "https://${INGRESS}/trader/summary" \
                      -H "Origin: https://${INGRESS}" \
                      -H "Referer: https://${INGRESS}/trader/summary" \
                      --compressed --insecure`
  if [ ${RESPONSE} -ne ${SUMMARY_CODE} ]; then
    echo "[`date '+%H:%M:%S'`] [MAIN] - An error occured getting the ${1} summary page"
    # Do not exit as the test would finish
    # exit 1
  fi
  echo "[`date '+%H:%M:%S'`] [MAIN] - Done"
}

delete()
{
  RESPONSE=`curl -b ${COOKIE_FILE} -o /dev/null -w '%{http_code}' -s "https://${INGRESS}/trader/summary" \
                    -H "Origin: https://${INGRESS}" \
                    -H "Referer: https://${INGRESS}/trader/summary" \
                    --data action=delete\&owner=${USER}\&submit=Submit \
                    --compressed --insecure`
  if [ ${RESPONSE} -ne ${DELETE_CODE} ]; then
    echo "[`date '+%H:%M:%S'`] [MAIN] - An error occured deleting user ${USER}"
    exit 1
  fi
}

export_db()
{
  echo "[`date '+%H:%M:%S'`] [MAIN] - Exporting the DB..."
  POD=`kubectl get pods | grep ibm-db2oltp-dev | awk '{print $1}'`
  kubectl exec ${POD} -- bash -c "sh /tmp/export.sh" > /dev/null
  if [ $? -ne 0 ]; then
    echo "[`date '+%H:%M:%S'`] [MAIN] - An error occured exporting the STOCKTRD DB"
    exit 1
  fi
  kubectl exec ${POD} -- bash -c "cat /tmp/stock.txt" > output/stock_${1}.txt
  kubectl exec ${POD} -- bash -c "cat /tmp/portfolio.txt" > output/portfolio_${1}.txt
  echo "[`date '+%H:%M:%S'`] [MAIN] - Done"
}

delete_users()
{
  echo "[`date '+%H:%M:%S'`] [MAIN] - Deleting all previous users..."
  POD=`kubectl get pods | grep ibm-db2oltp-dev | awk '{print $1}'`
  kubectl exec ${POD} -- bash -c "rm -rf /tmp/users.txt; sh /tmp/users.sh" > /dev/null
  for user in `kubectl exec ${POD} -- bash -c "cat /tmp/users.txt"`
  do
    echo "[`date '+%H:%M:%S'`] [MAIN] - deleting user ${user}"
    USER=${user}
    delete
  done
  echo "[`date '+%H:%M:%S'`] [MAIN] - Done"
  echo
}

######################################
##                                  ##
##               TEST               ##
##                                  ##
######################################

echo "[`date '+%H:%M:%S'`] [MAIN] - Begin of script"
echo
echo "[`date '+%H:%M:%S'`] [MAIN] - IBM StockTrader Ingress: ${INGRESS}"
echo
echo "[`date '+%H:%M:%S'`] [MAIN] - Number of threads: ${NUM_THREADS}"
echo "[`date '+%H:%M:%S'`] [MAIN] - Number of iterations: ${NUM_ITERATIONS}"
echo "[`date '+%H:%M:%S'`] [MAIN] - Number of users: ${NUM_USERS}"
echo "[`date '+%H:%M:%S'`] [MAIN] - Number of shares to add per iteration per symbol: ${NUMBER_OF_SHARES}"
echo "[`date '+%H:%M:%S'`] [MAIN] - Multiplication factor for shares: ${MULT_FACTOR}"
echo

# Prepare output folder
echo "[`date '+%H:%M:%S'`] [MAIN] - Cleaning output folder..."
if [ -d "${DIRECTORY}" ]; then
  rm -rf ${DIRECTORY} && mkdir ${DIRECTORY}
else
  mkdir ${DIRECTORY}
fi
echo "[`date '+%H:%M:%S'`] [MAIN] - Done"
echo

# Logging into the application
# login

# Deleting previous users
delete_users

# Kick off monkey chaos script
echo "[`date '+%H:%M:%S'`] [MAIN] - Wait 10 seconds to allow Monkey Chaos injection"
sleep 10

# Loop
for thread in $(seq $NUM_THREADS)
do
  echo "[`date '+%H:%M:%S'`] [MAIN] - Executing trader_user_loop.sh script for [THREAD_${thread}]"
  sh trader_user_loop.sh ${INGRESS} ${thread} ${NUM_ITERATIONS} ${NUM_USERS} ${NUMBER_OF_SHARES} ${MULT_FACTOR} ${COOKIE_FILE} ${DIRECTORY} &
done

# Wait for all threads to finish
while [ `ls -l ${DIRECTORY} | grep "done" | wc -l` -ne ${NUM_THREADS} ]
do
  sleep 10
done

# Final results
echo "[`date '+%H:%M:%S'`] [MAIN] - Getting the final reports..."
summary "final"
export_db "final"
echo "[`date '+%H:%M:%S'`] [MAIN] - Done"

echo "[`date '+%H:%M:%S'`] [MAIN] - End of script"
exit 0
