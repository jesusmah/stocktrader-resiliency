# stocktrader-resiliency

**LATEST ENV:** https://172.16.50.173:32370/trader/summary

Namepsace: stocktrader

---

1.  [Introduction](#introduction)
2.  [IBM StockTrader Application](#ibm-stocktrader-application)
3.  [Installation](#installation)
4.  [Test](#test)
    - [Load Test](#load-test)
    - [Load Test Throughput](#load-test-throughput)
    - [Monkey Chaos](#monkey-chaos)
    - [Test Execution](#test-execution)
5.  [Files](#files)
6.  [Links](#links)

## Introduction

The main goal of the work here presented in this GitHub repository is to explore new cloud native microservices based application resiliency on the IBM Cloud Private (ICP) platform. The desired outcome for this work would be a list of some recommendations and things to watch out as far as how to build resilient cloud native microservices based applications on the IBM Cloud Private (ICP) platform.

The work methodology we have chosen consists of using a representative application for each of the different scenarios application resiliency on IBM Cloud Private (ICP)  extensive field might involve, execute some load test on it while simulating platform failures and observe the resiliency of the application while writing down not only its behaviour but the reasons behind it, what is wrong/failing, what can be enhanced, etc. It is important to note that **we consider the middleware the application might use totally resilient** and therefore taking it out of the equation by not simulating platform failures for them.

Different application resiliency on IBM Cloud Private scenarios could be any combination of the following application type and IBM Cloud Private (ICP) topology:

1. Application:
   1. Cloud native stateless microservices based application.
   2. Cloud native stateful microservices based application.
   3. Legacy stateless monolithic application.
   4. Legacy stateful monolithic application.

2. IBM Cloud Private (ICP) topology:
   1. Simple ICP cluster on a datacenter.
   2. Federated/Stretched ICP cluster.

**Does the above make sense?? Frame it otherwise.**

In order to get us started, we have picked what we consider as the easiest scenario: a stateless microservices based application on a simple IBM Cloud Private (ICP) cluster.

The stateless microservices based application we are going to use for this first application resiliency on IBM Cloud Private (ICP) effort is called the [IBM StockTrader application](https://github.com/IBMStockTrader).

## IBM StockTrader Application

The IBM StockTrader application main goal is to showcase how IBM middleware can fit into the new hybrid cloud era where most of the uses cases will have a private cloud (on-premise resources) that needs to interact with services/resources on a public cloud (or more).

As a result, the IBM StockTrader application is a microservices application based on Java MicroProfile which tries to leverage IBM middleware such as IBM MQ, IBM DB2 and IBM ODM in IBM Cloud Private (ICP) and integrate with IBM Cloud Public services and some notification applications like Slack and Twitter.

The overall architecture looks like the following diagram:

<p align="center">
<img alt="st-arch" src="images/st-arch.png"/>
</p>

Where you can find StockTrader specific microservices in blue and IBM middleware in purple all running on IBM Cloud Private (ICP), IBM Cloud Public services in green and other third party applications in other different colours.

### Application flow

There are mainly 4 actions you can execute against the IBM StockTrader application once you are logged in:

1. Create a portfolio, where
    1. A `GET addPortfolio` request is sent to the `trader microservice (BFF)` from the browser by the user which returns a form to be filled with the new portfolio name **(1)**.
    2. `trader microservice (BFF)` sends a `POST addPortfolio` request to the `portfolio microservice` with the new portfolio's data from the previous form to get the portfolio created **(2)**.
    3. `portfolio microservice` interacts with the DB2 database through a JDBC Datasource to create the appropriate records and structure in the DB for the new portfolio **(3)**.
    4. Once the `portfolio microservice` returns a successful message for the `POST addPortfolio` request to the `trader microservice BFF`, this requests a `GET summary` to the `portfolio microservice` to display a summary of the application to the end user **(2)**.
2. Delete a portfolio.
    1. A `POST summary` request is sent to the `trader microservice (BFF)` from the browser by the user  with the action `delete` and owner `portfolio name` as parameters **(1)**.
    2. `trader microservice (BFF)` creates and sends another `POST` request to the `portfolio microservice`**(2)**.
    3. `portfolio microservice` interacts with the DB2 database through a JDBC Datasource to delete the appropriate records and structure in the DB for the portfolio indicated **(3)**.
    4. Once the `portfolio microservice` returns a successful message for the `POST` request to the `trader microservice BFF`, this requests a `GET summary` to the `portfolio microservice` to display a summary of the application to the end user **(2)**.
3. Add stock to an existing portfolio.
    1. A `POST summary` request is sent to the `trader microservice (BFF)` from the browser by the user  with the action `update` and owner `portfolio name` as parameters **(1)**.
    2. `trader microservice (BFF)` redirects the request to itself by sending a `GET addStock` request in order to present the user with a form to input what shares (company) and how many shares to update a portfolio with.
    3. This `GET addStock` request makes the `trader microservice (BFF)` to send a `GET` request to the `portfolio microservice` in order to retrieve the portfolio's next commission to be shown in the form presented to the user. This form will be used by the user to input what shares (company) and how many they want to update the portfolio with **(2)**.
    4. The `trader microservice (BFF)` returns a new page to the user with the form to add stock to be filled up.
    5. The user inputs what shares and how many they want a particular portfolio to be updated with and that sends a `POST addStock` with the portfolio and what shares and how many shares to update it with from the `trader BFF microservice` to the `portfolio microservice`**(2)**.
    6. Now the `portfolio microservice` will interact with `IBM DB2` through a JDBC Datasource, `IBM MQ` through a JMS resource and `IBM ODM` and the `stock quote microservice` through rest calls as follows:
        1. Process the commission for the portfolio update. That is, add the total of commissions for this portfolio **(3)**.
        2. Increment the amount of shares of the share type (company) the user decided to update the portfolio with **(3)**.
        3. Recalculate the total balance of the portfolio with the new amount of shares already added. To do this, the `portfolio microservice` will send a `GET` to the `stock quote microservice` to retrieve the current value for that type of share **(4)** . The `stock quote microservice` will:
            1. Check if the `Redis` cache attached to the `stock quote microservice` contains an acceptable up-to-date value for the type of share requested **(5)**.
            2. If it does, it will return such value. Otherwise, the `stock quote microservice` will call the external `IEX` service through the `API Connect` service set up in IBM Cloud Public **(6)**.
        4. Now that a new total balance for the portfolio to be updated has been calculated, the `portfolio microservice` will process the loyalty level for this portfolio. This will make a `POST` request to the `IBM ODM` with the total balance for the portfolio. `IBM ODM` will return the associated loyalty level for such balance **(7)**.
        5. If the loyalty level has changed, the `portfolio microservice` will send a message to the `IBM MQ` with the portfolio name along with the old and new loyalty levels **(8)**.
    7. The `messaging microservice` will be listening to an specific queue on the `IBM MQ` for messages being dropped by the `portfolio microservice` **(9)**.
    8. If a message, with a portfolio name and old and new loyalty levels, has been dropped into `IBM MQ` the `messaging microservice` will send a `POST` request to the `Notification (Twitter) microservice` (we are not using the Slack flow for now) **(10)**.
    8. The `Notification (Twitter) microservice` will post a tweet with the portfolio name and the old and new loyalties to the twitter account configured for StockTrader **(11)**.
4. Retrieve a portfolio.
    1. A `POST summary` request is sent to the `trader microservice (BFF)` from the browser by the user  with the action `retrieve` and owner `portfolio name` as parameters **(1)**.
    2. `trader microservice (BFF)` sends a `GET viewPortfolio` request to the `portfolio microservice` with the portfolio name **(2)**.
    3. `portfolio microservice` interacts with the DB2 database through a JDBC Datasource to retrieve the appropriate records and data from the DB for the portfolio indicated **(3)**.
    4. `portfolio microservice` returns all the data for the portfolio specified by the user to the `trader microservice (BFF)`and this presents it to the end user on the browser **(2)**.

#### Loyalty Levels

The loyalty levels for the IBM StockTrader application are set as follows:

| Loyalty Level | Stock |
| --- | --- |
| BASIC | 0 - 10.000 |
| BRONZE | 10.001 - 50.000 |
| SILVER | 50.001 - 100.000 |
| GOLD | 100.001 - 1.000.000 |
| PLATINUM | > 1.000.001 |

## Installation

The actual IBM StockTrader Application GitHub repository where the instructions on how to get it installed (with the middleware, third party applications and other integrations it depends on) is located at https://github.com/jesusmah/stocktrader-app/tree/v2.

Please, follow the instructions on the GitHub repository above to get the IBM StockTrader Application successfully installed and verified.

## Test

In this section we provide plain shell scripts to

1. Perform basic load test on the IBM StockTrader application to simulate common user interaction with the application by executing end-to-end scenarios trying to exercise all IBM StockTrader application components as much as possible.
  - [main_looper_basic_registry.sh](test/main_looper_basic_registry.sh)
  - [main_looper_oidc.sh](test/main_looper_oidc.sh)
  - [threaded_main_looper_basic_registry.sh](test/threaded_main_looper_basic_registry.sh)
  - [threaded_main_looper_oidc.sh](test/threaded_main_looper_oidc.sh)

2. Simulate IBM Cloud Private (ICP) platform Kubernetes pod failures that compromises the IBM StockTrader application resiliency.
  [chaos.sh](test/chaos.sh)

The IBM StockTrader's backend for frontend (BFF) microservice used to carry out the test is the **Trader** microservice. As already mentioned in this readme, the Trader microservice is served in two versions as far as authentication and authorisation of the requests is concerned. One uses plain user and password (`basicregistry`) and the other integrates with the IBMid service as the Identity Provider (IP) for the Open ID Connect (OIDC) mechanism (`latest`).

### Load Test

The IBM StockTrader load test scripts will interact with the IBM StockTrader application through **REST calls** against the **Trader** backend for frontend (BFF) microservice. The load test scripts' workflow looks like:

1. Remove the output from previous executions (`output` directory).
2. Log into the StockTrader application (only on the `basic_registry` shell scripts).
3. Delete existing portfolios from previous executions.
4. For each iteration, it will for each portfolio
   1. Create the portfolio if it is iteration number 1.
   2. Add the amount of shares specified for each of the symbols (IBM, APPLE and GOOGLE) multiplied by a factor.
   3. Create a summary for the iteration into the `output` directory (`summary_iteration_#.html` or `summary_thread_#_iteration_#.html`).
5. Create a final summary (`summary_final.html`) and export the database (`portfolio_final.txt` and `stock_final.txt`) reports into the `output` directory so that we can make sure the application has function as expected.

There is a second version of the script above where the main body (point 4) has been threaded in order to get a better request per second throughput. Those scripts are preceded with `threaded_` on their file names.

Finally, both the sequential and threaded versions have got their login section tailored to the two already well mentioned **Trader** microservice authentication and authorisation mechanisms `basicregistry` and `latest`.

As a result, we count with 4 load test scripts which we explain in further detail below.

**IMPORTANT:** given the loyalty levels for the IBM StockTrader application you can check in the [loyalty level section](#loyalty-level) below in this this readme, use a **Multiplication factor for shares** of **2** in the following load test scripts if you want to exponentially increment the amount of shares to add to the portfolios per iteration and, as a result, reach higher levels of loyalty and better stress the messaging and notification pieces of the IBM StockTrader application architecture.

#### main_looper_basic_registry.sh

The [main_looper_basic_registry.sh](test/main_looper_basic_registry.sh) will execute the workflow described in the [Load Test](#load-test) section above in a **sequential manner** with the **login section automated** using stock and trader as user and password when the **Trader** microservice version deployed is `basicregistry`.

The [main_looper_basic_registry.sh](test/main_looper_basic_registry.sh) script expects the following parameters:

- $1: your `<proxy_ip>`.
- $2: your `<trader_microservice_nodeport>`.
- $3: Number of iterations.
- $4: Number of portfolios.
- $5: Number of shares to add of each symbol per portfolio and iteration.
- $6: Multiplication factor for shares.

Example: `sh main_looper_basic_registry.sh 172.16.40.176 32370 3 6 1 1`

#### main_looper_oidc.sh

The [main_looper_oidc.sh](test/main_looper_oidc.sh) script will do exactly the same as the previous `basicregistry` version but will not log into the application automatically. The reason for this is that we encountered some problems automating such task which did not make sense to invest more time investigating.

As a result, the logging into the IBM StockTrader application `latest` version has to be done manually and the appropriate associated cookies exported in order to get the load testing scripts executed against. To export the appropriate cookies associated with the manual logging into the IBM StockTrader application, we have used Firefox to log into the IBM StockTrader application and the [cookies.txt Firefox add-on](https://addons.mozilla.org/en-US/firefox/addon/cookies-txt/) for exporting the cookies.

The [main_looper_oidc.sh](test/main_looper_oidc.sh) script expects the following parameters:

- $1: your `<proxy_ip>`.
- $2: your `<trader_microservice_nodeport>`.
- $3: Number of iterations.
- $4: Number of portfolios.
- $5: Number of shares to add of each symbol per portfolio and iteration.
- $6: Multiplication factor for shares.
- $7: IBM StockTrader authorisation and authorisation cookies file.

Example: `sh main_looper_oidc.sh 172.16.40.176 32370 3 6 1 1 cookies.txt`

#### threaded_main_looper_basic_registry.sh and threaded_main_looper_oidc.sh

The [threaded_main_looper_basic_registry.sh](test/threaded_main_looper_basic_registry.sh) and [threaded_main_looper_oidc.sh](test/threaded_main_looper_oidc.sh) scripts will do work exactly the same as their non-threaded versions explained above but will execute the main stock adding workflow piece in parallel for a better request per second throughput.

That is, from these scripts we will execute the [user_loop.sh](test/user_loop.sh) script in parallel as many times as threads has the main load test scripts been specified with:

```Shell
for thread in $(seq $NUM_THREADS)
do
  echo "[`date '+%H:%M:%S'`] [MAIN] - Executing user_loop.sh script for [THREAD_${thread}]"
  sh user_loop.sh ${PROXY_IP} ${BFF_NODEPORT} ${thread} ${NUM_ITERATIONS} ${NUM_USERS} ${NUMBER_OF_SHARES} ${COOKIE_FILE} ${DIRECTORY} &
done
```

where [user_loop.sh](test/user_loop.sh), will, in turn and in parallel, execute the adding stock code from the non-threaded script versions.

The scripts expects the following parameters:

- $1: your `<proxy_ip>`.
- $2: your `<trader_microservice_nodeport>`.
- $3: Number of threads
- $4: Number of iterations
- $5: Number of users
- $6: Number of shares to add of each symbol per portfolio and iteration
- $7: Multiplication factor for shares.
- $8: IBM StockTrader authorisation and authorisation cookies file (`oidc` version only).

Example: `sh threaded_main_looper_basic_registry.sh 172.16.40.176 32370 2 3 6 1 1`

Example: `sh threaded_main_looper_oidc.sh 172.16.40.176 32370 2 3 6 1 1 cookies.txt` (`oidc` version)

#### Execution

Here we are going to demo the execution of the non-threaded `basicregistry` version of the load test scripts and what the output of it would be (the threaded version would create more users which would just generate higher requests per second):

```
$ sh main_looper_basic_registry.sh 172.16.40.176 32370 4 2 20 1
[2018-07-03 11:46:33]: Begin of script

[11:46:33] IBM Cloud Private (ICP) proxy IP: 172.16.40.176
[11:46:33] IBM StockTrader BFF NodePort: 32370

[11:46:33] Number of iterations: 4
[11:46:33] Number of users: 2
[11:46:33] Number of shares to add per iteration per symbol: 20
[11:46:33] Multiplication factor for shares: 1

[2018-07-03 11:46:33]: Logging into the IBM StockTrader application using stock and trader...
[2018-07-03 11:46:34]: Done

[2018-07-03 11:46:34]: Deleting all previous users...
[2018-07-03 11:46:56]: deleting user User_1
[2018-07-03 11:46:58]: deleting user User_2
[2018-07-03 11:47:00]: Done

[2018-07-03 11:47:00]: ----- Begin Iteration 1

[2018-07-03 11:47:00]: Creating user User_1...
[2018-07-03 11:47:02]: Done

[2018-07-03 11:47:09]: Creating user User_2...
[2018-07-03 11:47:10]: Done

[2018-07-03 11:47:20]: ----- End Iteration 1

[2018-07-03 11:47:20]: ----- Begin Iteration 2

[2018-07-03 11:47:37]: ----- End Iteration 2

[2018-07-03 11:47:37]: ----- Begin Iteration 3

[2018-07-03 11:47:54]: ----- End Iteration 3

[2018-07-03 11:47:54]: ----- Begin Iteration 4

[2018-07-03 11:48:11]: ----- End Iteration 4

[2018-07-03 11:48:11]: Getting final results
[2018-07-03 11:48:30]: Done

[2018-07-03 11:48:30]: End of script
```

As we can read above, the load test script has created two users (portfolios) to which has added 20 shares per symbol (IBM, GOOGLE, ORACLE) each iteration (4 iterations) making IBM StockTrader to look like this

<p align="center">
<img alt="demo-main" src="images/resiliency20.png" width="500"/>
</p>

and our twitter account to look like this after having those two portfolios progressed few loyalty levels up:

<p align="center">
<img alt="demo-twitter" src="images/resiliency21.png" width="500"/>
</p>

As explained in the [Load Test](#load-test) section, the load test scripts also produce some more detailed test results into the `output` directory:

```
$ ls output
portfolio_final.txt
stock_final.txt
summary_final.html
summary_iteration_1.html
summary_iteration_2.html
summary_iteration_3.html
summary_iteration_4.html
```
where the `summary html` files would be a graphical snapshot of who the IBM StockTrader application looks like after each iteration and at the end of the load test script execution and `portfolio.txt` and `stock_final.txt` an IBM StockTrader application database dump at the end of the load test script execution:

```
$ cat portfolio_final.txt

OWNER                            TOTAL                    LOYALTY  BALANCE                  COMMISSIONS              FREE        SENTIMENT       
-------------------------------- ------------------------ -------- ------------------------ ------------------------ ----------- ----------------
User_1                             +1.16360000000000E+005 GOLD       -5.18800000000000E+001   +1.01880000000000E+002           0 Unknown         
User_2                             +1.16360000000000E+005 GOLD       -5.18800000000000E+001   +1.01880000000000E+002           0 Unknown         

  2 record(s) selected.
```
```
$ cat stock_final.txt

OWNER                            SYMBOL   SHARES      PRICE                    TOTAL                    DATEQUOTED COMMISSION              
-------------------------------- -------- ----------- ------------------------ ------------------------ ---------- ------------------------
User_1                           IBM               80   +1.39860000000000E+002   +1.11888000000000E+004 07/02/2018   +3.49600000000000E+001
User_1                           GOOG              80   +1.12746000000000E+003   +9.01968000000000E+004 07/02/2018   +3.49600000000000E+001
User_1                           AAPL              80   +1.87180000000000E+002   +1.49744000000000E+004 07/02/2018   +3.19600000000000E+001
User_2                           IBM               80   +1.39860000000000E+002   +1.11888000000000E+004 07/02/2018   +3.49600000000000E+001
User_2                           GOOG              80   +1.12746000000000E+003   +9.01968000000000E+004 07/02/2018   +3.49600000000000E+001
User_2                           AAPL              80   +1.87180000000000E+002   +1.49744000000000E+004 07/02/2018   +3.19600000000000E+001

  6 record(s) selected.
```

### Load Test Throughput

The following table describes the load test scripts maximum throughput when executed against the IBM StockTrader application:

**Replica 1**

| | #Threads | #Iterations | #Users | #Requests | Duration (sec) | Throughput (req/sec) |
| --- | --- | --- | --- | --- | --- | --- |
| main_looper_basic_registry.sh | - | 10 | 4 | 135 | 241 | **0.56** |
| threaded_main_looper_basic_registry.sh | 4 | 10 | 4 | 540 | 230 | **2.34** |
| threaded_main_looper_basic_registry.sh | 6 | 10 | 4 | 810 | 471 | **1.71** |

where all IBM StockTrader application microservices have 1 replica only.

**Replica 3**

| | #Threads | #Iterations | #Users | #Requests | Duration (sec) | Throughput (req/sec) |
| --- | --- | --- | --- | --- | --- | --- |
| main_looper_basic_registry.sh | - | 10 | 4 | 135 | 272 | **0.49** |
| threaded_main_looper_basic_registry.sh | 4 | 10 | 4 | 540 | 231 | **2.33** |
| threaded_main_looper_basic_registry.sh | 6 | 10 | 4 | 810 | 312 | **2.59** |

where all IBM StockTrader application microservices are scaled up to 3 replicas (except from the Trader backend for frontend microservice which can not scale due to some WebSphere Liberty SSO credentials sharing limitation).

The number of requests the load test scripts make to the IBM StockTrader application Trader backend for frontend microservice is calculated considering main loops only and leaving out preparation or summary requests. The equations look like this:

```
main_looper_basic_registry.sh = #Users + ( #Iteration * #Users * #Symbols(=3) ) + #Iterations
threaded_main_looper_basic_registry.sh = #Threads * ( #Users + ( #Iterations * #Users * #Symbols(=3) ) + #Iterations )
```

### Monkey Chaos

This section covers the implementation of a Kubernetes pod failure shell script. The script is actually called [chaos.sh](test/chaos.sh) and it is a tailored piece of the work presented in this [GitHub repository by Eduardo Patrocinio](https://github.com/patrocinio/kubernetes-pod-chaos-monkey) to suit our needs.

Given a namespace (default namespace is default), the IBM StockTrader application Helm release name and a delay (default 10 seconds), the [chaos.sh](test/chaos.sh) script will then randomly choose a Running pod within that namespace which belongs to the specified IBM StockTrader application Helm release and terminate it:

```Shell
while true; do
  POD=`kubectl \
    --namespace "${NAMESPACE}" \
    -o 'jsonpath={.items[*].metadata.name}' \
    get pods | \
      tr " " "\n" | \
      grep ${UNIQUE_ID} | \
      grep Running | \
      grep -v trad | \
      gshuf | \
      head -n 1`
  echo Deleting Pod ${POD}...
  kubectl --namespace "${NAMESPACE}" delete pod ${POD}
  sleep "${DELAY}"
done
```

this way we simulate failures on the IBM Cloud Private (ICP) platform that will allow us to study the IBM StockTrader application resiliency as the cloud native stateless microservices based reference application for the IBM Cloud Private (ICP) resiliency at the application level initial scenario.

Example:

```
$ sh chaos.sh 10 stocktrader test
[2018-07-03 16:14:15]: Begin of script

Delay: 10
Namespace: stocktrader
Unique ID (Helm release): test

Deleting Pod test-notification-twitter-6dd5f9d7dc-bsfs7...
pod "test-notification-twitter-6dd5f9d7dc-bsfs7" deleted

Deleting Pod test-portfolio-75b4dbd485-k6rq4...
pod "test-portfolio-75b4dbd485-k6rq4" deleted

Deleting Pod test-notification-twitter-6dd5f9d7dc-5rmh4...
pod "test-notification-twitter-6dd5f9d7dc-5rmh4" deleted
^C
```

As you can see, the [chaos.sh](test/chaos.sh) script will run until a kill signal is sent to it (ctrl+c).

### Test Execution

As already said in this readme, in order to test what we consider the easiest and therefore first step on testing cloud native microservices based applications on the IBM Cloud Private (ICP) platform (that is stateless microservices based applications), we are going to test the IBM StockTrader application resiliency.

For doing so, we have [deployed the IBM StockTrader application](#installation) and developed [load test scripts](#load-test) for it and a [Kubernetes pod failure shell script](#monkey-chaos) for the IBM Cloud Private (ICP) platform.

Then, we have scaled our stateless microservices to 3 replicas (except from the backend for frontend **Trader** microservice(1)) so that we create high availability, increase our application resiliency and minimise Kubernetes pod failures to break our application. There is no point in testing with only one replica as any pod failure will bring our application down.

(1) The reason the backend for frontend (BFF) Trader microservice has not been scaled is due to a WebSphere Liberty SSO limitation which does not allow to share the SSO credentials/cookies amongst several WebSphere Liberty instances. Hence, requests will get redirected several times to the login mechanism. Since the Trader microservice `latest` version is not able to scale and therefore we are going to have only 1 replica of our backend for frontend (BFF), we have decided to run our tests with the `basicregistry` version instead as the load test scripts for such version automates the login into the IBM StockTrader application.

This is how our testing environment looks like in terms of pods:

```
$ kubectl get pods
NAME                                         READY     STATUS    RESTARTS   AGE
st-db2-ibm-db2oltp-dev-0                     1/1       Running   0          6d
st-mq-ibm-mq-0                               1/1       Running   0          6d
st-odm-ibm-odm-dev-6699d55df5-fv9lv          1/1       Running   0          5d
st-redis-master-0                            1/1       Running   0          5d
st-redis-slave-5866f6f889-fkstr              1/1       Running   0          5d
test-messaging-644ccbcd95-h9pxv              1/1       Running   0          16m
test-messaging-644ccbcd95-mwkjh              1/1       Running   0          2d
test-messaging-644ccbcd95-q58z4              1/1       Running   0          16m
test-notification-twitter-6dd5f9d7dc-8d2ch   1/1       Running   0          16m
test-notification-twitter-6dd5f9d7dc-d474c   1/1       Running   0          16m
test-notification-twitter-6dd5f9d7dc-g47ql   1/1       Running   0          1d
test-portfolio-75b4dbd485-8vjst              1/1       Running   0          16m
test-portfolio-75b4dbd485-k9mxm              1/1       Running   0          1d
test-portfolio-75b4dbd485-ppqd7              1/1       Running   0          16m
test-stock-quote-7679899d76-8q5lc            1/1       Running   0          16m
test-stock-quote-7679899d76-hwndr            1/1       Running   0          16m
test-stock-quote-7679899d76-rgkwr            1/1       Running   0          2d
test-trader-5446499c5b-98x2r                 1/1       Running   0          21m
test-tradr-548b58bc55-kms2z                  1/1       Running   0          3h
```

that is,

- 1 replica of our middleware pieces: `IBM DB2`, `IBM MQ`, `IBM ODM` and `Redis`
- 1 replica of our backend for frontend: `trader` (`tradr` is not used even though it gets installed with the IBM StockTrader application Helm chart)
- 3 replicas of the core IBM StockTrader application microservices: `Portfolio`, `Stock-quote`, `Messaging` and `Notificatio-Twitter`

Now, the only thing that is left is to execute the load test scripts and the Kubernetes pod failure script at the same time over the IBM StockTrader application installation you can see above which we have on our IBM Cloud Private (ICP) instance hosted on our lab.

The results of these executions can be found in the [test execution readme file](test_execution.md).

## Files

This section will describe each of the files presented in this repository.

#### images

This folder contains the images used for this README file.

#### test

- [execution](test/execution): This folder contains the test execution results.
- [chaos.sh](test/chaos.sh): Shell script that simulates Kubernetes pod failures.
- [delete_all_tweets.py](test/delete_all_tweets.py): Python script to delete all tweets from a given twitter account.
- [export.sh](test/export.sh): Shell script to export the IBM StockTrader application database to a text file.
- [get_logs.sh](test/get_logs.sh): Shell script to get all the logs from a Helm release since a period of time (if specified).
- [main_looper_basic_registry.sh](test/main_looper_basic_registry.sh): Single-threaded IBM StockTrader load test script to be used when `basicregistry` Trader microservice version.
- [main_looper_oidc.sh](test/main_looper_oidc.sh): Single-threaded IBM StockTrader load test script to be used when `latest` Trader microservice version.
- [threaded_main_looper_basic_registry.sh](test/threaded_main_looper_basic_registry.sh): Multi-threaded IBM StockTrader load test script to be used when `basicregistry` Trader microservice version.
- [threaded_main_looper_oidc.sh](test/threaded_main_looper_oidc.sh): Multi-threaded IBM StockTrader test script to be used when `latest` Trader microservice version.
- [user_loop.sh](test/user_loop.sh): Simulated user behavior load test script to be called by the multi-threaded IBM StockTrader test scripts to carry out the adding stock workflow piece.
- [users.sh](test/users.sh): Shell script to export the IBM StockTrader portfolios to a text file.

## Links


- [IBM StockTrader Application GitHub repository (for this work)](https://github.com/jesusmah/stocktrader-app)

- [IBM StockTrader Application Helm chart repository (for this work)](https://github.com/jesusmah/stocktrader-helm-repo)

- [Official IBM StockTrader Application GitHub repository](https://github.com/IBMStockTrader)
