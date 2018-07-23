#!/bin/bash

################
## PARAMETERS ##
################
PROXY_IP=$1
BFF_NODEPORT=$2
NUM_ITERATIONS=$3
NUM_USERS=$4
NUMBER_OF_SHARES=$5
MULT_FACTOR=${6:-1}

##################
## Cookies file ##
##################
COOKIE_FILE="cookie.txt"

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
CREATE_CODE=302
RETRIEVE_CODE=200
UPDATE_CODE=302
DELETE_CODE=200

###################
## Share symbols ##
###################
IBM="IBM"
GOOGLE="GOOG"
APPLE="AAPL"
SYMBOLS="${IBM} ${GOOGLE} ${APPLE}"

##############
## COMMANDS ##
##############

login()
{
  echo "[`date '+%Y-%m-%d %H:%M:%S'`]: Logging into the IBM StockTrader application using ${ID} and ${PASSWORD}..."
  RESPONSE=`curl -c ${COOKIE_FILE} -o /dev/null -w '%{http_code}' -s "https://${PROXY_IP}:${BFF_NODEPORT}/trader/login" \
                    -H "Origin: https://${PROXY_IP}:${BFF_NODEPORT}" \
                    -H "Referer: https://${PROXY_IP}:${BFF_NODEPORT}/trader/login" \
                    --data id=${ID}\&password=${PASSWORD}\&submit=Submit \
                    --compressed --insecure`

  if [ ${RESPONSE} -ne ${LOGIN_CODE} ]; then
    echo "[`date '+%Y-%m-%d %H:%M:%S'`]: An error occured logging into the IBM StockTrader application using ${ID} and ${PASSWORD}"
    exit 1
  fi
  echo "[`date '+%Y-%m-%d %H:%M:%S'`]: Done"
  echo
}

summary()
{
  RESPONSE=`curl -b ${COOKIE_FILE} -o ${DIRECTORY}/summary_${1}.html -w '%{http_code}' -s "https://${PROXY_IP}:${BFF_NODEPORT}/trader/summary" \
                      -H "Origin: https://${PROXY_IP}:${BFF_NODEPORT}" \
                      -H "Referer: https://${PROXY_IP}:${BFF_NODEPORT}/trader/summary" \
                      --compressed --insecure`
  if [ ${RESPONSE} -ne ${SUMMARY_CODE} ]; then
    echo "[`date '+%Y-%m-%d %H:%M:%S'`]: An error occured getting the summary page"
    exit 1
  fi
}

create()
{
  echo "[`date '+%Y-%m-%d %H:%M:%S'`]: Creating user ${USER}..."
  RESPONSE=`curl -b ${COOKIE_FILE} -o /dev/null -w '%{http_code}' -s "https://${PROXY_IP}:${BFF_NODEPORT}/trader/addPortfolio" \
                    -H "Origin: https://${PROXY_IP}:${BFF_NODEPORT}" \
                    -H "Referer: https://${PROXY_IP}:${BFF_NODEPORT}/trader/addPortfolio" \
                    --data owner=${USER}\&submit=Submit \
                    --compressed --insecure`
  if [ ${RESPONSE} -ne ${CREATE_CODE} ]; then
    echo "[`date '+%Y-%m-%d %H:%M:%S'`]: An error occured creating the user ${USER}"
    exit 1
  fi
  echo "[`date '+%Y-%m-%d %H:%M:%S'`]: Done"
  echo
}

retrieve()
{
  RESPONSE=`curl -b ${COOKIE_FILE} -o /dev/null -w '%{http_code}' -s "https://${PROXY_IP}:${BFF_NODEPORT}/trader/viewPortfolio?owner=${USER}" \
                      -H "Origin: https://${PROXY_IP}:${BFF_NODEPORT}" \
                      -H "Referer: https://${PROXY_IP}:${BFF_NODEPORT}/trader/summary" \
                      --compressed --insecure`
  if [ ${RESPONSE} -ne ${RETRIEVE_CODE} ]; then
    echo "[`date '+%Y-%m-%d %H:%M:%S'`]: An error occured retrieving the info for user ${USER}"
    exit 1
  fi
}

update()
{
  RESPONSE=`curl -b ${COOKIE_FILE} -o /dev/null -w '%{http_code}' -s "https://${PROXY_IP}:${BFF_NODEPORT}/trader/addStock?owner=${USER}" \
                    -H "Origin: https://${PROXY_IP}:${BFF_NODEPORT}" \
                    -H "Referer: https://${PROXY_IP}:${BFF_NODEPORT}/trader/addStock?owner=${USER}" \
                    --data symbol=${SYMBOL}\&shares=${NUMBER_OF_SHARES}\&submit=Submit \
                    --compressed --insecure`
  if [ ${RESPONSE} -ne ${UPDATE_CODE} ]; then
    echo "[`date '+%Y-%m-%d %H:%M:%S'`]: An error occured adding ${NUMBER_OF_SHARES} ${SYMBOL} shares to ${USER} stock"
    exit 1
  fi
}

delete()
{
  RESPONSE=`curl -b ${COOKIE_FILE} -o /dev/null -w '%{http_code}' -s "https://${PROXY_IP}:${BFF_NODEPORT}/trader/summary" \
                    -H "Origin: https://${PROXY_IP}:${BFF_NODEPORT}" \
                    -H "Referer: https://${PROXY_IP}:${BFF_NODEPORT}/trader/summary" \
                    --data action=delete\&owner=${USER}\&submit=Submit \
                    --compressed --insecure`
  if [ ${RESPONSE} -ne ${DELETE_CODE} ]; then
    echo "[`date '+%Y-%m-%d %H:%M:%S'`]: An error occured deleting user ${USER}"
    exit 1
  fi
}

export_db()
{
  POD=`kubectl get pods | grep ibm-db2oltp-dev | awk '{print $1}'`
  kubectl exec ${POD} -- bash -c "sh /tmp/export.sh" > /dev/null
  if [ $? -ne 0 ]; then
    echo "[`date '+%Y-%m-%d %H:%M:%S'`]: An error occured exporting the STOCKTRD DB"
    exit 1
  fi
  kubectl exec ${POD} -- bash -c "cat /tmp/stock.txt" > output/stock_${1}.txt
  kubectl exec ${POD} -- bash -c "cat /tmp/portfolio.txt" > output/portfolio_${1}.txt
}

delete_users()
{
  echo "[`date '+%Y-%m-%d %H:%M:%S'`]: Deleting all previous users..."
  POD=`kubectl get pods | grep ibm-db2oltp-dev | awk '{print $1}'`
  kubectl exec ${POD} -- bash -c "rm -rf /tmp/users.txt; sh /tmp/users.sh" > /dev/null
  for user in `kubectl exec ${POD} -- bash -c "cat /tmp/users.txt"`
  do
    echo "[`date '+%Y-%m-%d %H:%M:%S'`]: deleting user ${user}"
    USER=${user}
    delete
  done
  echo "[`date '+%Y-%m-%d %H:%M:%S'`]: Done"
  echo
}

######################################
##                                  ##
##               TEST               ##
##                                  ##
######################################

echo "[`date '+%Y-%m-%d %H:%M:%S'`]: Begin of script"
echo
echo "[`date '+%H:%M:%S'`] IBM Cloud Private (ICP) proxy IP: ${PROXY_IP}"
echo "[`date '+%H:%M:%S'`] IBM StockTrader BFF NodePort: ${BFF_NODEPORT}"
echo
echo "[`date '+%H:%M:%S'`] Number of iterations: ${NUM_ITERATIONS}"
echo "[`date '+%H:%M:%S'`] Number of users: ${NUM_USERS}"
echo "[`date '+%H:%M:%S'`] Number of shares to add per iteration per symbol: ${NUMBER_OF_SHARES}"
echo "[`date '+%H:%M:%S'`] Multiplication factor for shares: ${MULT_FACTOR}"
echo

# Prepare output folder
if [ -d "${DIRECTORY}" ]; then
  rm -rf ${DIRECTORY} && mkdir ${DIRECTORY}
else
  mkdir ${DIRECTORY}
fi

# Logging into the application
login

# Deleting previous users
delete_users

# Kick off monkey chaos script
echo "[`date '+%H:%M:%S'`]: Wait 10 seconds to allow Monkey Chaos injection"
sleep 10

# Iterations
for iteration in $(seq $NUM_ITERATIONS)
do
  echo "[`date '+%Y-%m-%d %H:%M:%S'`]: ----- Begin Iteration $iteration"
  echo

  # For each user
  for user in $(seq $NUM_USERS)
  do
    # Set user
    USER="User_${user}"

    # Create user if first iteration
    if [ $iteration -eq 1 ]; then
      create
    fi

    # Add shares of each symbol
    for symbol in ${SYMBOLS}
    do
      SYMBOL=${symbol}
      update
    done
    NUMBER_OF_SHARES=$((NUMBER_OF_SHARES*MULT_FACTOR))
  done

  # Results after an iteration
  summary "iteration_${iteration}"
  #export_db "iteration_${iteration}"

  echo "[`date '+%Y-%m-%d %H:%M:%S'`]: ----- End Iteration $iteration"
  echo
done

# Final results
echo "[`date '+%Y-%m-%d %H:%M:%S'`]: Getting final results"
summary "final"
export_db "final"
echo "[`date '+%Y-%m-%d %H:%M:%S'`]: Done"

echo
echo "[`date '+%Y-%m-%d %H:%M:%S'`]: End of script"
exit 0
