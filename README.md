# stocktrader-resiliency

This repo contains the test artefacts used for ICP application resiliency test using the IBM StockTrader application.


**LATEST ENV**

https://172.16.40.176:32370/trader/summary

Namepsace: stocktrader

---

There are two versions of StockTrader

#### Version 1

This version is the simpler one where the loyalty-level microservice is a Java based microservice that returns the loyalty of a user based on hardcoded thresholds. The notification microservice has been decoupled into a twitter flow and slack flow. Finally, the security for the application is a simple WebSphere basic registry type of login.

![version 1](https://www.ibm.com/developerworks/community/blogs/5092bd93-e659-4f89-8de2-a7ac980487f0/resource/BLOGS_UPLOADED_IMAGES/StockTraderArch.png)

#### Version 2

This version is a bit more elavorated where we use OIDC as the security mechanism for the application leveraging IBMid as our Identity Provider. It also uses IBM Operational Decision Manager for calculating a user's loyalty as well as delivers new use cases like user's feedback analysed by Watson, stock fees, etc.

![version 2](https://github.com/jesusmah/stocktrader-resiliency/raw/master/image.png)

### Files

#### Middleware

- [db2_pvc.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/db2_pvc.yaml): creates a persistent volume claim of glusterfs storageclass type for backing DB2.
- [db2_values.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/db2_values.yaml): DB2 helm chart values file tailored for what the IBM StockTrader helm chart expects.
- [initialise_stocktrader_db_v2.sql](https://github.com/jesusmah/stocktrader-resiliency/blob/master/initialise_stocktrader_db_v2.sql): Initialises the IBM StockTrader version 2 DB.
- [initialise_stocktrader_db_v2.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/initialise_stocktrader_db_v2.yaml): Kubernetes job to initialise the IBM StockTrader version 2 DB.
- [initialise_stocktrader_db.sql](https://github.com/jesusmah/stocktrader-resiliency/blob/master/initialise_stocktrader_db.sql): Initialises the IBM StockTrader version 1 DB.
- [initialise_stocktrader_db.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/initialise_stocktrader_db.yaml): Kubernetes job to initialise the IBM StockTrader version 1 DB.
- [mq_values.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/mq_values.yaml): MQ helm chart values file tailored for what the IBM StockTrader helm chart expects.
- [redis_values.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/redis_values.yaml): Redis helm chart values file tailored for what the IBM StockTrader helm chart expects.

#### Application

- [st_app_values_v1.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/st_app_values_v1.yaml): Default IBM StockTrader version 1 helm chart values file.
- [st_app_values_v2.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/st_app_values_v2.yaml): Default IBM StockTrader version 2 helm chart values file.

#### Test

- [export.sh](https://github.com/jesusmah/stocktrader-resiliency/blob/master/export.sh): Shell script to export IBM StockTrader DB to a text file.
- [main_looper_basic_registry.sh](https://github.com/jesusmah/stocktrader-resiliency/blob/master/main_looper_basic_registry.sh): Single-threaded IBM StockTrader test script to be used when security is basic registry.
- [main_looper_oidc.sh](https://github.com/jesusmah/stocktrader-resiliency/blob/master/main_looper_oidc.sh): Single-threaded IBM StockTrader test script to be used when security is OIDC.
- [threaded_main_looper_basic_registry.sh](https://github.com/jesusmah/stocktrader-resiliency/blob/master/threaded_main_looper_basic_registry.sh): Multi-threaded IBM StockTrader test script to be used when security is basic registry.
- [threaded_main_looper_oidc.sh](https://github.com/jesusmah/stocktrader-resiliency/blob/master/threaded_main_looper_oidc.sh): Multi-threaded IBM StockTrader test script to be used when security is OIDC.
- [user_loop.sh](https://github.com/jesusmah/stocktrader-resiliency/blob/master/user_loop.sh): User behavior simulated test script to be called by the multi-threaded IBM StockTrader test script.
- [users.sh](https://github.com/jesusmah/stocktrader-resiliency/blob/master/users.sh): Shell script to export IBM StockTrader users to a text file.
- [get_logs.sh](https://github.com/jesusmah/stocktrader-resiliency/blob/master/get_logs.sh): Shell script get all the logs from a helm release since a period of time (if specified).

## Installation

As depicted at the begining of this readme, the IBM StockTrader application environmet is made up of certain middleware as well as microservices based IBM StockTrader application itself. More precisely, we will need IBM DB2, IBM WebSphere MQ, Redis, ODM...

**IMPORTANT:** The below installation steps will create kubernetes resources with names and configurations that the IBM StockTrader Helm chart will be defaulted with.

### Middleware

1. Create a namespace called `stocktrader`
2. Give privileged permissions to your namespace as some IBM middleware needs of them to function: `kubectl create rolebinding -n stocktrader st-rolebinding --clusterrole=privileged  --serviceaccount=stocktrader:default`
3. Crete a secret that holds your docker hub credentials & DB2 API key to retrieve the DB2 docker image: `kubectl create secret docker-registry st-docker-registry --docker-username=<userid> --docker-password=<API key> --docker-email=<email> --namespace=stocktrader`
4. Add IBM helm chart repo: `helm repo add ibm-charts https://raw.githubusercontent.com/IBM/charts/master/repo/stable/`
5. Install DB2 using the [db2_values.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/db2_values.yaml) file: `helm insall -n st-db2 --namespace stocktrader --tls ibm-charts/ibm-db2oltp-dev -f <db2_values.yaml>` **Important:** This does not install the HA version of DB2
5. Initialise IBM StockTrader DB with [initialise_stocktrader_db_v2.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/initialise_stocktrader_db_v2.yaml): `kubectl apply -f <initialise_stocktrader_db_v2.yaml>`
6. Download util scripts: ```kubectl exec `kubectl get pods | grep ibm-db2oltp-dev | awk '{print $1}'` \
        -- bash -c "yum -y install wget && cd /tmp && wget https://raw.githubusercontent.com/jesusmah/stocktrader-resiliency/master/export.sh && wget https://raw.githubusercontent.com/jesusmah/stocktrader-resiliency/master/users.sh" && chmod 777 export.sh users.sh```
6. Install MQ using the [mq_values.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/mq_values.yaml): `helm insall -n st-mq --namespace stocktrader --tls ibm-charts/ibm-mqadvanced-server-dev -f <mq_values.yaml>`
7. Create the trader queue manager, the NotificationQ message queue and the app user giving it the appropriate permissions following this [link](https://www.ibm.com/developerworks/community/blogs/5092bd93-e659-4f89-8de2-a7ac980487f0/entry/Building_Stock_Trader_in_IBM_Cloud_Private_2_1_using_Production_Services?lang=en). **Important:** DO GIVE **inquire** permissions to the app user. Otherwise, StockTrader portfolio microservice will fail to start up.
8. Install redis using [redis_values.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/redis_values.yaml): `helm insall -n st-redis --namespace stocktrader --tls ibm-charts/ibm-redis-ha-dev -f <redis_values.yaml>`
9. Install ODM from ICP catalog with release name `st-odm`
10. Import and deploy ODM project for stocktrader which can be found on the [IBM StockTrader Portfolio microservice github repository](https://github.com/IBMStockTrader/portfolio/blob/master/stock-trader-loyalty-decision-service.zip)

### Application

1. Add the IBM StockTrader Helm repository: `helm repo add stocktrader https://raw.githubusercontent.com/jesusmah/stocktrader-helm-repo/master/docs/charts`
2. Inspect the [st_app_values_v2.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/st_app_values_v2.yaml) so that default values and the values to be modified/completed are correct as explained in detail below before installing the IBM StockTrader application in the next step.
3. Deploy the IBM StockTrader version 2 application using [st_app_values_v2.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/st_app_values_v2.yaml): `helm install -n <release_name> --tls --namespace stocktrader -f <st_app_values_v2.yaml> stocktrader/stocktrader-app --version "0.2.0"`

**IMPORTANT:** Even if you have correctly followed the instructions above and the different pieces StockTrader environment needs around have got the appropriate values the stocktrader installation expects afterwards, there are still some values that need to tailor a bit more or even complete in the [st_app_values_v2.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/st_app_values_v2.yaml):

- Nodeport is url to access your Stocktrader application. This url and port change with every installation and the Identity provider needs to have it registered upfront in order to authorize calls to the stocktrader app. Therefore, not only does the nodeport value need to change but also work on the Identity provider side needs to be done.

   ```
   oidc:
       # nodeport: https://172.16.40.176:32370
       nodeport: aHR0cHM6Ly8xNzIuMTYuNDAuMTc2OjMyMzcw
   ```
- quandl_key holds your QuandL account credetianls to which Stocktrader will run queries against to get stock quotes. You need to create a QuandL account and provide your own credentials.
   ```
   redis:
       # Get your Quandl key
       quandl_key:
   ```
- You need to create an account with IBM Watson services at the url shown below and provide the credentials so that the tone analyzer calls from the feedback use case work successfully.
   ```
   watson:
       # Get your credentials at https://console.bluemix.net/catalog/services/tone-analyzer
       id:
       pwd:
   ```
- trader service nodePort need to be hardcoded to the values you have register your redirect_url at the Identity provider since it needs to always be the same. The following ports also need to match the values for the oidc secret above

   ```
   trader:
     service:
       nodePort:
         http: 31507
         https: 32370
   ```
## Test

**IMPORTANT:** The basic registry stocktrader version do not support SSO and therefore its BFF **can not be scaled up**. The other microservices can be scaled and the basic_registry tests below will work fine.
If you want to scale up the BFF too, you need to use the **latest** version of stocktrader which uses OIDC and therefore use the oidc scripts below.

#### main_looper_basic_registry.sh

This script will

1. Remove the old output directory (where the output of the test will go into)
2. Log into the StockTrader application using `stock/trader` as the default credentials (this will create a cookies.txt file)
3. Delete existing users (if any). This will use [users.sh](https://github.com/jesusmah/stocktrader-resiliency/blob/master/users.sh)
4. Based on the number of iterations it will for each user
   1. Create the user if it is iteration number 1
   2. Add the amount of shares specified to the script for each of the symbols (IBM, APPLE and GOOGLE).
   3. Create a summary for the iteration
5. Finally, once all the action has happened, it will create a final summary and export the database so that we can check it out to make sure the application has function as expected.

```
######################################
##                                  ##
##               TEST               ##
##                                  ##
######################################

echo "[`date '+%Y-%m-%d %H:%M:%S'`]: Begin of script"
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
```

All the actions performed against the stocktrader application will be made on a REST call fashion to the BFF of it.

The script expects the following parameters:

- $1: your ICP proxy IP
- $2: trader microservice nodeport
- $3: Number of iterations
- $4: Number of users
- $5: Number of shared to add of each symbol per user and iteration

Example: `sh main_looper_basic_registry.sh 172.16.40.176 32370 3 6 1`

#### main_looper_oidc.sh

This script will do exactly the same as previous one but will not log into the application as this has to be done manually  using firefox for now by pointing the browser to `https://<ICP_PROXY_IP>:<TRADER_MICROSERVICE_NODEPORT>/trader/login`. Using the cookies.txt firefox add-on we need to manually export the firefox cookies to a txt file which is required as a parameter of this script.

Example: `sh main_looper_oidc.sh 172.16.40.176 32370 3 6 1 cookies.txt`

#### threaded_main_looper_basic_registry.sh

This script will do exactly the same as **main_looper_basic_registry.sh** but will do so in **parallel** as many times as the number of threads you have specified as parameter. That is, for each thread it will execute (in parallel) the [user_loop.sh](https://github.com/jesusmah/stocktrader-resiliency/blob/master/user_loop.sh) script

```
for thread in $(seq $NUM_THREADS)
do
  echo "[`date '+%H:%M:%S'`] [MAIN] - Executing user_loop.sh script for [THREAD_${thread}]"
  sh user_loop.sh ${PROXY_IP} ${BFF_NODEPORT} ${thread} ${NUM_ITERATIONS} ${NUM_USERS} ${NUMBER_OF_SHARES} ${COOKIE_FILE} ${DIRECTORY} &
done
```
which, in turn, will

1. Based on the number of iterations it will for each user
   1. Create the user if it is iteration number 1
   2. Add the amount of shares specified to the script for each of the symbols (IBM, APPLE and GOOGLE).
   3. Create a summary for the iteration
2. Create a summary afer each iteration

```
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
```

All the actions performed against the stocktrader application will be made on a REST call fashion to the BFF of it.

The script expects the following parameters:

- $1: your ICP proxy IP
- $2: trader microservice nodeport
- $3: Number of threads
- $4: Number of iterations
- $5: Number of users
- $6: Number of shared to add of each symbol per user and iteration

Example: `sh threaded_main_looper_basic_registry.sh 172.16.40.176 32370 2 3 6 1`

#### threaded_main_looper_oidc.sh

This script will do exactly the same as previous one but will not log into the application as this has to be done manually  using firefox for now by pointing the browser to `https://<ICP_PROXY_IP>:<TRADER_MICROSERVICE_NODEPORT>/trader/login`. Using the cookies.txt firefox add-on we need to manually export the firefox cookies to a txt file which is required as a parameter of this script.

Example: `sh threaded_main_looper_oidc.sh 172.16.40.176 32370 2 3 6 1 cookies.txt`
