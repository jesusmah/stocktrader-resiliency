# stocktrader-resiliency

This repo contains the artefacts created for ICP application resiliency exploratory test using the IBM StockTrader application. Amongst these artefacts, you will see installation files for the middleware and the application as well as the test scripts themselves.

**LATEST ENV**

https://172.16.40.176:32370/trader/summary

Namepsace: stocktrader
---

1.  [IBM StockTrader application](#ibm-stocktrader-application)
2.  [Installation](#installation)
    - [Middleware](#middleware)
    - [Application](#application)
3.  [Test](#test)

## IBM StockTrader application

The IBM StockTrader application main goal is to showcase how IBM middleware can fit into the new hybrid cloud era where most of the uses cases will have a private cloud (on-premise resources) that needs to interact with services/resources on a public cloud (or more).

As a result, the IBM StockTrader application is a microservices application based on Java MicroProfile which tries to leverage IBM middleware such as IBM MQ, IBM DB2 and IBM DB2 in IBM Cloud Private (ICP) and integrate with IBM Cloud Public services and some notification applications like Slack and Twitter.

The overall architecture looks like the following diagram:

![st-arch](https://github.com/jesusmah/stocktrader-resiliency/raw/master/images/st-arch.png)

Where you can find StockTrader specific microservices in blue and IBM middleware in purple all running on IBM Cloud Private (ICP), IBM Cloud Public services in green and other third party applications in other different colours.

#### Application flow

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


## Installation

As shown in the IBM StockTrader application architecture diagram above, the IBM StockTrader application environment within IBM Cloud Private (ICP) is made up of IBM middleware such as **IBM DB2**, **IBM MQ** and **IBM ODM**, third party applications like **Redis** and the IBM StockTrader application microservices **Trader**, **Portfolio**, **Stock-quote**, **Messaging** and **Notification-Twitter** (**Tradr** and **Notification-Slack** are not part of this work).

In this section, we will outline the steps needed in order to get the aforementioned components installed into IBM Cloud Private (ICP) so that we have a complete functioning IBM StockTrader application to carry out our test on. We will try to use as much automation as possible as well as Helm charts for installing as many components as possible. Most of this components require a post-installation configuration and tuning too.

**IMPORTANT:** The below installation steps will create Kubernetes resources with names and configurations that the IBM StockTrader Helm chart will expect. Therefore, if any of these is changed, the IBM StockTrader Helm installation will need to be modified accordingly.

Finally, most of the installation process will be carried out by using the IBM Cloud Private (ICP) CLI. Follow this [link](https://www.ibm.com/support/knowledgecenter/en/SSBS6K_2.1.0.3/manage_cluster/icp_cli.html) for the installation instructions.

### Platform

1. Create a namespace called **stocktrader**. If you don't know how to do so, follow this [link](https://www.ibm.com/support/knowledgecenter/en/SSBS6K_2.1.0.3/user_management/create_project.html).
2. Give privileged permissions to your recently created namespace as some the IBM middleware need them to function:

```
$ kubectl create rolebinding -n stocktrader st-rolebinding --clusterrole=privileged  --serviceaccount=stocktrader:default
rolebinding "st-rolebinding" created
$ kubectl get rolebindings                 
NAME             KIND                                       SUBJECTS
st-rolebinding   RoleBinding.v1.rbac.authorization.k8s.io   1 item(s)
```

### Middleware

As previously said, IBM middleware will be installed using Helm charts as much as possible. Therefore, we need to add the IBM Helm chart repository to our local Helm chart repositories:

```
$ helm repo add ibm-charts https://raw.githubusercontent.com/IBM/charts/master/repo/stable/
"ibm-charts" has been added to your repositories
$ helm repo list
NAME                    	URL                                                                                                      
stable                  	https://kubernetes-charts.storage.googleapis.com                                                         
local                   	http://127.0.0.1:8879/charts                                                                             
ibm-charts              	https://raw.githubusercontent.com/IBM/charts/master/repo/stable/
```

(\*) If you don't have a **stable** Helm repo pointing to https://kubernetes-charts.storage.googleapis.com, please add it too using:

```
$ helm repo add stable https://kubernetes-charts.storage.googleapis.com
```

#### IBM DB2

User must be subscribed to [Db2 Developer-C Edition on Docker Store](https://store.docker.com/images/db2-developer-c-edition) so they can generate a key to access the image. After subscription, visit [Docker Cloud](https://cloud.docker.com/) and in the upper right corner, click on your user ID drop-down menu and select Account Settings. Scroll down and Add API key.

This way, the IBM Db2 Developer-C Edition Helm chart will be able to pull down the IBM Db2 Developer-C Edition Docker image by using your Docker Cloud credentials and the access key associated to it. We just finally need to store your Docker Cloud credentials into a Kubernetes secret which the IBM Db2 Developer-C Edition Helm chart will read at installation time.

1. Crete a secret that holds your Docker Cloud credentials & Db2 Developer-C Edition API key to retrieve the Db2 Developer-C Edition docker image:

```
$ kubectl create secret docker-registry st-docker-registry --docker-username=<userid> --docker-password=<API key> --docker-email=<email> --namespace=stocktrader
secret "st-docker-registry" created
$ kubectl get secrets   
NAME                  TYPE                                  DATA      AGE
default-token-t92bq   kubernetes.io/service-account-token   3         51d
st-docker-registry    kubernetes.io/dockercfg               1         28s
```

2. Install IBM Db2 Developer-C Edition using the [db2_values.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/installation/middleware/db2_values.yaml) file:

```
$ helm install -n st-db2 --namespace stocktrader --tls ibm-charts/ibm-db2oltp-dev -f db2_values.yaml
NAME:   st-db2
LAST DEPLOYED: Wed Jun 27 18:49:04 2018
NAMESPACE: stocktrader
STATUS: DEPLOYED

RESOURCES:
==> v1/Secret
NAME                    TYPE    DATA  AGE
st-db2-ibm-db2oltp-dev  Opaque  1     5s

==> v1/PersistentVolumeClaim
NAME               STATUS   VOLUME     CAPACITY  ACCESS MODES  STORAGECLASS  AGE
st-db2-st-db2-pvc  Pending  glusterfs  5s

==> v1/Service
NAME                        TYPE       CLUSTER-IP   EXTERNAL-IP  PORT(S)                                  AGE
st-db2-ibm-db2oltp-dev-db2  NodePort   10.10.10.83  <none>       50000:32329/TCP,55000:31565/TCP          5s
st-db2-ibm-db2oltp-dev      ClusterIP  None         <none>       50000/TCP,55000/TCP,60006/TCP,60007/TCP  5s

==> v1beta2/StatefulSet
NAME                    DESIRED  CURRENT  AGE
st-db2-ibm-db2oltp-dev  1        1        5s

==> v1/Pod(related)
NAME                      READY  STATUS   RESTARTS  AGE
st-db2-ibm-db2oltp-dev-0  0/1    Pending  0         4s


NOTES:
1. Get the database URL by running these commands:
  export NODE_PORT=$(kubectl get --namespace stocktrader -o jsonpath="{.spec.ports[0].nodePort}" services st-db2-ibm-db2oltp-dev)
  export NODE_IP=$(kubectl get nodes --namespace stocktrader -o jsonpath="{.items[0].status.addresses[0].address}")
  echo jdbc:db2://$NODE_IP:$NODE_PORT/sample
```

**Important:** This will install the non HA version of IBM Db2 Developer-C Edition with persistent storage using glusterfs.

The command above will take few minutes at least. Monitor the recently created Db2 Developer-C Edition pod, which in our case is called `st-db2-ibm-db2oltp-dev-0`, until you see the following messages:

```
(*) All databases are now active.
(*) Setup has completed.
```
At this point we can be sure the IBM Db2 Developer-C Edition and the **STOCKTRD** database have successfully been installed and created respectively.

3. Now, we need to create the appropriate structure in the **STOCKTRD** database that the IBM StockTrader application needs. We do so by initialising the database with the [initialise_stocktrader_db_v2.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/installation/middleware/initialise_stocktrader_db_v2.yaml) file:

```
$ kubectl apply -f initialise_stocktrader_db_v2.yaml
job "initialise-stocktrader-db" created
```

the command above created a Kubernetes job which spun up a simple db2express-c container that contains the IBM DB2 tools to execute an sql file against a DB2 database on a remote host. The sql file that gets executed against a DB2 database on a remote host is actually the one that initialises the database with appropriate structures the IBM StockTrader application needs. The sql file is [initialise_stocktrader_db_v2.sql](https://github.com/jesusmah/stocktrader-resiliency/blob/master/installation/middleware/initialise_stocktrader_db_v2.sql).

Check the Kubernetes job to make sure it has finished before moving on:

```
$ kubectl get jobs
NAME                        DESIRED   SUCCESSFUL   AGE
initialise-stocktrader-db   1         1            4m
```

4. Finally, we are going to download few util scripts into the IBM Db2 Developer-C recently created container that our test scripts will make use of as explained in the [test section](#test):

```
$ kubectl exec `kubectl get pods | grep ibm-db2oltp-dev | awk '{print $1}'` \
        -- bash -c "yum -y install wget && cd /tmp && wget https://raw.githubusercontent.com/jesusmah/stocktrader-resiliency/master/test/export.sh \
        && wget https://raw.githubusercontent.com/jesusmah/stocktrader-resiliency/master/test/users.sh" && chmod 777 export.sh users.sh
```

Make sure the scripts have been successfully download:

```
$ kubectl exec `kubectl get pods | grep ibm-db2oltp-dev | awk '{print $1}'` -- bash -c "ls -all /tmp | grep sh"
-rwxrwxrwx. 1 root     root         139 Jun 27 17:48 export.sh
-rwxrwxrwx. 1 root     root          98 Jun 27 17:48 users.sh
```

#### IBM MQ

1. Install MQ using the [mq_values.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/installation/middleware/mq_values.yaml) file:

```
$ helm install -n st-mq --namespace stocktrader --tls ibm-charts/ibm-mqadvanced-server-dev -f mq_values.yaml
NAME:   st-mq
LAST DEPLOYED: Thu Jun 28 16:38:22 2018
NAMESPACE: stocktrader
STATUS: DEPLOYED

RESOURCES:
==> v1/Secret
NAME          TYPE    DATA  AGE
st-mq-ibm-mq  Opaque  1     4s

==> v1/Service
NAME          TYPE      CLUSTER-IP    EXTERNAL-IP  PORT(S)                        AGE
st-mq-ibm-mq  NodePort  10.10.10.133  <none>       9443:31184/TCP,1414:32366/TCP  4s

==> v1beta2/StatefulSet
NAME          DESIRED  CURRENT  AGE
st-mq-ibm-mq  1        1        4s

==> v1/Pod(related)
NAME            READY  STATUS   RESTARTS  AGE
st-mq-ibm-mq-0  0/1    Running  0         4s


NOTES:
MQ can be accessed via port 1414 on the following DNS name from within your cluster:
st-mq-ibm-mq.stocktrader.svc.cluster.local

To get your admin password run:

    MQ_ADMIN_PASSWORD=$(kubectl get secret --namespace stocktrader st-mq-ibm-mq -o jsonpath="{.data.adminPassword}" | base64 --decode; echo)

If you set an app password, you can retrieve it by running the following:

    MQ_APP_PASSWORD=$(kubectl get secret --namespace stocktrader st-mq-ibm-mq -o jsonpath="{.data.appPassword}" | base64 --decode; echo)
```

**IMPORTANT:** The `mq_values.yaml` file used to install the IBM Message Queue Helm chart into our IBM Cloud Private (ICP) cluster is configured to install a non-persistent IBM Message Queue due to some problems between IBM MQ and GlusterFS.

2. We now need to create the **NotificationQ** message queue and the **app** message queue user (with the appropriate permissions). For doing so we need to interact with our IBM Message Queue instance we just deployed above through its web console.

For accessing the IBM MQ web console, we need to

- Grab our IBM Cloud Private (ICP) proxy's IP:

```
$ kubectl get nodes -l proxy=true             
NAME            STATUS    AGE       VERSION
172.16.40.176   Ready     57d       v1.9.1+icp-ee
172.16.40.177   Ready     57d       v1.9.1+icp-ee
172.16.40.178   Ready     57d       v1.9.1+icp-ee
```
In this case, we have three proxy nodes in our IBM Cloud Private (ICP) highly available cluster. We are going to use the first proxy node with IP `172.16.40.176` to access any resource we need within our ICP cluster (bearing in mind we could use any of the others and the result would be the same).

- Grab the NodePort for our recently installed IBM Message Queue instance. We can see that NodePort from the output we obtain when we executed the Helm install command under the services section and right beside the internal **9443** port:

```
==> v1/Service
NAME          TYPE      CLUSTER-IP    EXTERNAL-IP  PORT(S)                        AGE
st-mq-ibm-mq  NodePort  10.10.10.133  <none>       9443:31184/TCP,1414:32366/TCP  4s
```

That is, the NodePort for accessing our IBM MQ deployment from the outside is **31184**

- Access the IBM MQ web console pointing your browser to https://<proxy_ip>:<mq_nodeport>/ibmmq/console

![mq-web-console](https://github.com/jesusmah/stocktrader-resiliency/raw/master/images/resiliency1.png)

and using `admin` as the user and `passw0rd` as its password (Anyway, you could also find out what the password is by following the instructions the Helm install command for IBM MQ displayed).

- Once you log into the IBM MQ web console, find out the **Queues on trader** widget/portlet and clieck on `Create` on the top right corner:

![create-queue](https://github.com/jesusmah/stocktrader-resiliency/raw/master/images/resiliency2.png)

- Enter **NotificationQ** on the dialog that pops up and click create:

![queue-name](https://github.com/jesusmah/stocktrader-resiliency/raw/master/images/resiliency3.png)

- On the Queues on trader widget/portlet again, click on the dashes icon and then on the **Manage authority records...** option within the dropdown menu:

![authority](https://github.com/jesusmah/stocktrader-resiliency/raw/master/images/resiliency4.png)

- On the new dialog that opens up, click on **Create** on the top right corner. This will also open up a new dialog to introduce the **Entity name**. Enter **app** as the Entity name and click on create

![entity-name](https://github.com/jesusmah/stocktrader-resiliency/raw/master/images/resiliency5.png)

- Back to the first dialog that opened up, verify the new app entity appears listed, click on it and select **Browse, Inquire, Get and Put** on the right bottom corner as the MQI permissions for the app entity and click on Save:

![mqi-permissions](https://github.com/jesusmah/stocktrader-resiliency/raw/master/images/resiliency6.png)


#### Redis

1. Install Redis using the [redis_values.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/installation/middleware/redis_values.yaml) file:

```
$ $ helm install -n st-redis --namespace stocktrader --tls stable/redis -f redis_values.yaml
NAME:   st-redis
E0628 18:14:21.431010   11573 portforward.go:303] error copying from remote stream to local connection: readfrom tcp4 127.0.0.1:55225->127.0.0.1:55228: write tcp4 127.0.0.1:55225->127.0.0.1:55228: write: broken pipe
LAST DEPLOYED: Thu Jun 28 18:14:19 2018
NAMESPACE: stocktrader
STATUS: DEPLOYED

RESOURCES:
==> v1/Secret
NAME      TYPE    DATA  AGE
st-redis  Opaque  1     3s

==> v1/Service
NAME             TYPE       CLUSTER-IP    EXTERNAL-IP  PORT(S)   AGE
st-redis-master  ClusterIP  10.10.10.4    <none>       6379/TCP  3s
st-redis-slave   ClusterIP  10.10.10.191  <none>       6379/TCP  3s

==> v1beta1/Deployment
NAME            DESIRED  CURRENT  UP-TO-DATE  AVAILABLE  AGE
st-redis-slave  1        1        1           0          3s

==> v1beta2/StatefulSet
NAME             DESIRED  CURRENT  AGE
st-redis-master  1        1        3s

==> v1/Pod(related)
NAME                             READY  STATUS             RESTARTS  AGE
st-redis-slave-5866f6f889-5c2cc  0/1    ContainerCreating  0         3s
st-redis-master-0                0/1    Pending            0         3s


NOTES:
** Please be patient while the chart is being deployed **
Redis can be accessed via port 6379 on the following DNS names from within your cluster:

st-redis-master.stocktrader.svc.cluster.local for read/write operations
st-redis-slave.stocktrader.svc.cluster.local for read-only operations


To get your password run:

    export REDIS_PASSWORD=$(kubectl get secret --namespace stocktrader st-redis -o jsonpath="{.data.redis-password}" | base64 --decode)

To connect to your Redis server:

1. Run a Redis pod that you can use as a client:

   kubectl run --namespace stocktrader st-redis-client --rm --tty -i \
    --env REDIS_PASSWORD=$REDIS_PASSWORD \
   --image docker.io/bitnami/redis:4.0.10 -- bash

2. Connect using the Redis CLI:
   redis-cli -h st-redis-master -a $REDIS_PASSWORD
   redis-cli -h st-redis-slave -a $REDIS_PASSWORD

To connect to your database from outside the cluster execute the following commands:

    export POD_NAME=$(kubectl get pods --namespace stocktrader -l "app=redis" -o jsonpath="{.items[0].metadata.name}")
    kubectl port-forward --namespace stocktrader $POD_NAME 6379:6379
    redis-cli -h 127.0.0.1 -p 6379 -a $REDIS_PASSWORD
```

**IMPORTANT:** The Redis instance installed is a non-persistent non-HA Redis Redis deployment

#### IBM ODM

1. Install IBM Operational Decision Manager (ODM) using the [odm_values.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/installation/middleware/odm_values.yaml) file:

```
$ helm install -n st-odm --namespace stocktrader --tls ibm-charts/ibm-odm-dev -f odm_values.yaml
NAME:   st-odm
LAST DEPLOYED: Thu Jun 28 18:53:45 2018
NAMESPACE: stocktrader
STATUS: DEPLOYED

RESOURCES:
==> v1/ConfigMap
NAME                       DATA  AGE
st-odm-odm-test-configmap  2     3s

==> v1/Service
NAME                TYPE      CLUSTER-IP   EXTERNAL-IP  PORT(S)         AGE
st-odm-ibm-odm-dev  NodePort  10.10.10.39  <none>       9060:31101/TCP  3s

==> v1beta1/Deployment
NAME                DESIRED  CURRENT  UP-TO-DATE  AVAILABLE  AGE
st-odm-ibm-odm-dev  1        1        1           1          3s

==> v1/Pod(related)
NAME                                 READY  STATUS   RESTARTS  AGE
st-odm-ibm-odm-dev-6699d55df5-fv9lv  1/1    Running  0         3s


NOTES:
st-odm is ready to use. st-odm is an instance of the ibm-odm-dev chart.

st-odm uses version 8.9.2 of the IBM® Operational Decision Manager (ODM) components.

ODM Information
----------------

Username/Password :
  - For Decision Center : odmAdmin/odmAdmin
  - For Decision Server Console: odmAdmin/odmAdmin
  - For Decision Server Runtime: odmAdmin/odmAdmin
  - For Decision Runner: odmAdmin/odmAdmin

Get the application URLs by running these commands:

  export NODE_PORT=$(kubectl get --namespace stocktrader -o jsonpath="{.spec.ports[0].nodePort}" services st-odm-ibm-odm-dev)
  export NODE_IP=$(kubectl get nodes --namespace stocktrader -o jsonpath="{.items[0].status.addresses[0].address}")

  -- Decision Center Business Console
  echo http://$NODE_IP:$NODE_PORT/decisioncenter

  -- Decision Center Enterprise Server
  echo http://$NODE_IP:$NODE_PORT/teamserver

  -- Decision Server Console
  echo http://$NODE_IP:$NODE_PORT/res

  -- Decision Server Runtime
  echo http://$NODE_IP:$NODE_PORT/DecisionService

  -- Decision Runner
  echo http://$NODE_IP:$NODE_PORT/DecisionRunner

To learn more about the st-odm release, try:

  $ helm status st-odm
  $ helm get st-odm
```

**IMPORTANT:** The IBM Operational Decision Manager (ODM) installed is a non-persistent IBM ODM deployment.

2. We now need to import the already developed loyalty level IBM ODM project which our IBM StockTrader application will use. To import the such project:

- Download the project from this [link](https://github.com/IBMStockTrader/portfolio/blob/master/stock-trader-loyalty-decision-service.zip)

- Open the IBM Operational Decision Manager by pointing your browser to http://<proxy_ip>:<odm_nodeport> where the `<proxy_ip>` can be obtained as explained in the [IBM MQ installation](#ibm-mq) previous section above and the `<odm_nodeport>` can be obtained under the service section from the output of the Helm install command for IBM ODM above in this section. More precisely, we can see above that in our case `<odm_nodeport>` is **31101**.

![odm](https://github.com/jesusmah/stocktrader-resiliency/raw/master/images/resiliency7.png)

- Click on **Decision Center Business Console** and log into it using the credentials from the Helm install command output above (`odmAdmin/odmAdmin`).

- Once you are logged in, click on the arrow on the left top corner to import a new project.

![odm-import](https://github.com/jesusmah/stocktrader-resiliency/raw/master/images/resiliency8.png)

- On the dialog that pops up, click on `Choose...` and select the **stock-trader-loyalty-decision-service.zip** file you downloaded above. Click on Import.

![odm-choose](https://github.com/jesusmah/stocktrader-resiliency/raw/master/images/resiliency9.png)

- Once the stock-trader-loyalty-decision-service project is imported, you should be redirected into that project within the **Library section** of the Decision Center Business Console. You should see there an icon that says **main**. Click on it.

![odm-library](https://github.com/jesusmah/stocktrader-resiliency/raw/master/images/resiliency10.png)

- The above should have opened the **main** workflow of the stock-trader-loyalty-decision-service project. Now, click on **Deploy** at the top to actually deploy the stock-trader-loyalty-decision-service into the IBM Operational Decision server.

![odm-deploy](https://github.com/jesusmah/stocktrader-resiliency/raw/master/images/resiliency11.png)

- A new dialog will pop up with the **specifics** on how to deploy the main branch for the stock-trader-loyalty-decision-service. Leave it as it is and click on Deploy.

![odm-deploy-specifics](https://github.com/jesusmah/stocktrader-resiliency/raw/master/images/resiliency12.png)

- Finally, you should see a **Deployment status** dialog confirming that the deployment of the stock-trader-loyalty-decision-service project (actually called ICP-Trader-Dev-1) has started. Click OK to close the dialog.

![odm-status](https://github.com/jesusmah/stocktrader-resiliency/raw/master/images/resiliency13.png)

At this point we should have an instance of the IBM Operation Decision Manager deployed into out IBM Cloud Private (ICP) cluster, the stock-trader-loyalty-decision-service project (actually called ICP-Trader-Dev-1) imported into it and deployed to the Operation Decision server for the IBM StockTrader application to use it for calculating the loyalty of the portfolios.

In order to make sure of the aforementioned, we are going to poke the IBM ODM endpoint for our loyalty service to see what it returns. To poke the endpoint, execute

```
$ curl -X POST -d '{ "theLoyaltyDecision": { "tradeTotal": 75000 } }' -H "Content-Type: application/json" http://<proxy_ip>:<odm_nodeport>/DecisionService/rest/ICP_Trader_Dev_1/determineLoyalty
```
where we have already explained how to obtain `<proxy_ip>` and `<odm_nodepot>` few steps above.

The `curl` request should return a **SILVER** loyalty on a JSON obsect similar to the following:

```
{"__DecisionID__":"3d18f834-0095-4821-8e1b-157f41ee1ee80","theLoyaltyDecision":{"tradeTotal":75000,"loyalty":"SILVER","message":null}}
```

**We have finally installed all the middleware** the IBM StockTrader application depends on in order to function properly. Let's now move on to install the IBM StockTrader application.

### Application

The IBM StockTrader application can be deployed to IBM Cloud Private (ICP) using Helm charts. All the microservices that make up the application have been packaged into a Helm chart. They could be deployed individually using their Helm chart or they all can be deployed at once using the main umbrella IBM StockTrader application Helm chart.

The IBM StockTrade Helm chart repository can be found at https://github.com/jesusmah/stocktrader-helm-repo/

As we have done for the middleware pieces installed on the previous section, the IBM StockTrader application installation will be done by passing the desired values/configuration for some its components through a values file called [st_app_values_v2.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/installation/application/st_app_values_v2.yaml). This way the IBM StockTrader application Helm chart are the template/structure of the components that make up the application whereas the [st_app_values_v2.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/installation/application/st_app_values_v2.yaml) file allows us to tailor the application to our needs/configuration/environment.

We suggest you **carefully review this file** in order to make sure the configuration for the middleware matches the installation of it done in previous steps.

Also, there are some sections within this [st_app_values_v2.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/installation/application/st_app_values_v2.yaml) file that need to be completed as they depend on the specifics of the environment the IBM StockTrader application will be installed on as well as personal credentials.

**IMPORTANT:** The values for the following parameters in the [st_app_values_v2.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/installation/application/st_app_values_v2.yaml) file **must be base64 encoded**. As a result, whatever the value you want to set the following parameters with, they first need to be encoded using the this command:

```
echo -n "<the_value_you_want_to_encode>" | base64
```

The pieces you need to complete with your environment/credentials specifics are:

```
oidc:
  nodeport:
```

which specifies the **url callback** parameter the **Trader** microservice will send along with the Open ID Connect authentication requests against the **IBMid** service. As a result, this url to access the StockTrader application must be static. This means you must choose a `<proxy_ip>` from your IBM Cloud Private (ICP) proxies (in case you had several) where the access to your StockTrader application will be done through and your Trader microservice must always expose the same `<trader_microservice_nodeport>`. This is a limitation in the SSO strategy the IBMid service provides since in a Kubernetes plus microservices scenarios, things die and get born so that having hardcoded/reserved ports, urls, etc is not a good practice. The Open ID Connect mechanism, which needs this `oidc` config, is only used when the **Trader** and **Tradr** microservices are deployed on their `latest` versions rather than their `basicregistry` versions (see below). For the resiliency effort carried out in this exercise we are using the `basicregistry` due to some Liberty SSO problems.

```
twitter:
  consumerKey:
  consumerSecret:
  accessToken:
  accessTokenSecret:
```

which specifies the credentials for the IBM StockTrader to tweet notifications for loyalty changes to your Twitter account. In case you don't have a Twitter account or do not want to create one, The IBM StockTrader application **already comes configured with a default Twitter account** which is https://twitter.com/ibmstocktrader

```
watson:
  id:
  pwd:
```

which are your IBM Watson Tone Analyzer credentials for the IBM StockTrader to be able to analyze your feedback in order to adjust the stock fees applied to a portfolio. You can obtain your IBM Watson credentials at https://console.bluemix.net/catalog/services/tone-analyzer

```
ingress_host:
  host:
```

which specifies to the new looking nodejs based **Tradr** (BFF) microservice where to serve the content and accept request from. This should be configured to `<proxy_ip>:<tradr_microservice_nodeport>`.

```
trader:
  image:
    tag:
  service:
    nodePort:
      http:
      https:
```

where

- `tag` specifies what version of the **Trader** microservice we want to deploy, being `latest` the version that uses SSO and `basicregistry` the version that does and uses user/password type of authentication and authorization. For the test carries out in this resiliency effort and explained below in this readme, we have used the `basicregistry` version due to some problems with the Liberty SSO which will be further explained in the test section.
- `http` and `https` specify the NodePorts the **Trader** microservice will be exposed through. As already said, we are hardcoding/reserving/forcing **Trader** to always use the same NodePorts since these need to be registered (along with the `<proxy_ip>`) at the IBMid service level for the SSO to work.

```
tradr:
  service:
    servicePort:
      port:
      nodePort:
```

similar to `trader` above, this will force the **Tradr** microservice to always be accessible through the same NodePorts so that we can register those on the IBMid service for the SSO to work.

Now that we are sure our [st_app_values_v2.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/installation/application/st_app_values_v2.yaml) file configuration for the middleware installed in the previous section looks good and have been completed with NodePorts, credentials, etc, **let's deploy the IBM StockTrader application!**

1. Add the IBM StockTrader Helm repository:

```
$ helm repo add stocktrader https://raw.githubusercontent.com/jesusmah/stocktrader-helm-repo/master/docs/charts
$ helm repo list
NAME                    	URL                                                                                                      
stable                  	https://kubernetes-charts.storage.googleapis.com                                                         
local                   	http://127.0.0.1:8879/charts                                                                             
st                      	https://raw.githubusercontent.com/jesusmah/stocktrader-helm-repo/master/docs/charts                      
ibm-charts              	https://raw.githubusercontent.com/IBM/charts/master/repo/stable/  
```

2. Deploy the IBM StockTrader application using the [st_app_values_v2.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/installation/application/st_app_values_v2.yaml) file:

```
helm install -n <release_name> --tls --namespace stocktrader -f <st_app_values_v2.yaml> stocktrader/stocktrader-app --version "0.2.0"
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

#### Links

- https://www.ibm.com/developerworks/community/blogs/5092bd93-e659-4f89-8de2-a7ac980487f0/entry/Building_Stock_Trader_in_IBM_Cloud_Private_2_1_using_Production_Services?lang=en

- New blog to come out for the newer StockTrader architecture that uses watson, IEX, ODM, etc

- https://github.com/IBMStockTrader

## Files

This section will describe each of the files presented in this repository. In here we have files that refer to two different versions of StockTrader. A simpler one we initiated our resiliency work with (version 1 or v1) and the sort of complete StockTrader version which we have finally used for the resiliency test (version 2 or v2)

#### Installation - Middleware

- [db2_values.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/installation/middleware/db2_values.yaml): tailored IBM DB2 Helm chart values file with the default values that the IBM StockTrader Helm chart expects.
- [initialise_stocktrader_db_v2.sql](https://github.com/jesusmah/stocktrader-resiliency/blob/master/installation/middleware/initialise_stocktrader_db_v2.sql): initialises the IBM StockTrader version 2 database with the appropriate structure for the application to work properly.
- [initialise_stocktrader_db_v2.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/installation/middleware/initialise_stocktrader_db_v2.yaml): Kubernetes job that pulls [initialise_stocktrader_db_v2.sql](https://github.com/jesusmah/stocktrader-resiliency/blob/master/installation/middleware/initialise_stocktrader_db_v2.sql) to initialise the IBM StockTrader version 2 database.
- [initialise_stocktrader_db_v1.sql](https://github.com/jesusmah/stocktrader-resiliency/blob/master/installation/middleware/initialise_stocktrader_db_v1.sql): initialises the IBM StockTrader version 1 database with the appropriate structure for the application to work properly.
- [initialise_stocktrader_db_v1.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/installation/middleware/initialise_stocktrader_db_v1.yaml): Kubernetes job that pulls [initialise_stocktrader_db_v1.sql](https://github.com/jesusmah/stocktrader-resiliency/blob/master/installation/middleware/initialise_stocktrader_db_v1.sql) to initialise the IBM StockTrader version 1 database.
- [mq_values.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/installation/middleware/mq_values.yaml): tailored IBM MQ Helm chart values file with the default values that the IBM StockTrader Helm chart expects.
- [redis_values.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/installation/middleware/master/redis_values.yaml): tailored Redis Helm chart values file with the default values that the IBM StockTrader Helm chart expects.
- [odm_values.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/installation/middleware/odm_values.yaml): tailored IBM Operation Decision Manager (ODM) Helm chart values file with the default values that the IBM StockTrader Helm chart expects.

#### Installation - Application

- [st_app_values_v1.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/installation/application/st_app_values_v1.yaml): Default IBM StockTrader version 1 Helm chart values file.
- [st_app_values_v2.yaml](https://github.com/jesusmah/stocktrader-resiliency/blob/master/installation/application/st_app_values_v2.yaml): Default IBM StockTrader version 2 Helm chart values file.

#### Test

TO BE REVIEWED YET!!!

- [export.sh](https://github.com/jesusmah/stocktrader-resiliency/blob/master/test/export.sh): Shell script to export IBM StockTrader DB to a text file.
- [main_looper_basic_registry.sh](https://github.com/jesusmah/stocktrader-resiliency/blob/master/test/main_looper_basic_registry.sh): Single-threaded IBM StockTrader test script to be used when security is basic registry.
- [main_looper_oidc.sh](https://github.com/jesusmah/stocktrader-resiliency/blob/master/test/main_looper_oidc.sh): Single-threaded IBM StockTrader test script to be used when security is OIDC.
- [threaded_main_looper_basic_registry.sh](https://github.com/jesusmah/stocktrader-resiliency/blob/master/test/threaded_main_looper_basic_registry.sh): Multi-threaded IBM StockTrader test script to be used when security is basic registry.
- [threaded_main_looper_oidc.sh](https://github.com/jesusmah/stocktrader-resiliency/blob/master/test/threaded_main_looper_oidc.sh): Multi-threaded IBM StockTrader test script to be used when security is OIDC.
- [user_loop.sh](https://github.com/jesusmah/stocktrader-resiliency/blob/master/test/user_loop.sh): User behavior simulated test script to be called by the multi-threaded IBM StockTrader test script.
- [users.sh](https://github.com/jesusmah/stocktrader-resiliency/blob/master/test/users.sh): Shell script to export IBM StockTrader users to a text file.
- [get_logs.sh](https://github.com/jesusmah/stocktrader-resiliency/blob/master/test/get_logs.sh): Shell script get all the logs from a Helm release since a period of time (if specified).
