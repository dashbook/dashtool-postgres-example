# Dashtool example with Postgres

Welcome to our tutorial on creating a data lakehouse using
[dashtool](http://www.github.com/dashbook/dashtool). In this project, you'll
learn how to collect data from an operational database, transform it and make it
available for analytics. Our focus will be on demonstrating the capabilities of
a lakehouse, which combines the benefits of data warehouses and data lakes to
enable business intelligence (BI) and machine learning (ML) directly on cloud
object storage.

To get started, let's walk through what you can expect in this tutorial:

1. **Data ingestion**: We'll utilize a PostgreSQL database as our operational
   system and demonstrate how to extract data using one of the 200+ available
   connectors compatible with the [Singer specification](http://www.singer.io).
   These connectors allow you to easily ingest data from various sources.
2. **Declarative data pipeline**: You'll discover how to set up declarative data
   pipelines that will transform the ingested data using declarative SQL
   statements.
3. **Automated Data Refresh**: Leveraging Argo Workflows, you'll orchestrate
   Kubernetes Jobs that use the
   [Datafusion](https://github.com/apache/arrow-datafusion) query engine to
   automatically update the target tables based on user-defined schedules.
4. **Open Table Format**: Utilizing
   [Apache Iceberg](https://iceberg.apache.org/), you'll store your transformed
   data in a highly performant table format that can be accessed by query
   engines such as Spark and Trino.
5. **Data Analysis with BI Tool**: To visualize and interactively explore the
   processed data, we introduce [Apache Superset](https://superset.apache.org)—a
   popular open-source BI platform. We will use an Apache Arrow Flight server to
   enable Superset to read the Iceberg tables.

By completing this tutorial, you'll have learned to create **declarative data
pipelines** that enables analytics directly on a data lakehouse.

## Setup

Now, let's move forward with setting up the prerequisites for our tutorial.
Below is a summary of the essential components needed for this exercise:

**Requirements:**

- A running Kubernetes cluster.
- `kubectl` - the official CLI tool for managing Kubernetes clusters.
- [`dashtool`](http://www.github.com/dashbook/dashtool)

For simplicity, we recommend using [Kind](https://kind.sigs.k8s.io/), a local
Kubernetes environment ideal for development purposes. However, online
Kubernetes playgrounds such as [KillaCoda](https://killercoda.com/) or
[Play with Kubernetes](https://labs.play-with-k8s.com/) may also serve as
suitable alternatives.

To begin working with Kind, visit the
[official Kind documentation](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
and carefully review installation instructions for your operating system.

Once Kind has been installed successfully, proceed to setup `dashtool`. Follow
the installation instructions from the
[dashtool repository](http://www.github.com/dashbook/dashtool).

## Cluster setup

The lakehouse that we are trying to build in this tutorial is composed of
different components. We need object-storage to store the data, a database as a
data source and a visualization server. Before we can start with the actual
tutorial we need to make sure that all components are runnning.

### Start Kind cluster

As a first step, let's create the kind cluster.

```shell
kind create cluster
```

### Install Argo

Next, we need to install Argo workflows in the cluster. We will create a `argo`
namespace for all its resources.

```sh
kubectl create namespace argo
```

The next step will install argo workflows. Please specify which version should
be used.

```sh
kubectl apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/v<<ARGO_WORKFLOWS_VERSION>>/install.yaml
```

Argo is typically deployed on a permanent cluster with proper SSL certificates.
Since our cluster is used only temporarily, we will not register any SSL
certificates and use the "server" auth mode. This will lead to warnings in the
browser later on but these don't need to concern us.

```shell
kubectl patch deployment \
  argo-server \
  --namespace argo \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/args", "value": [
  "server",
  "--auth-mode=server"
]}]'
```

### Create Secrets

The lakehouse consists of a catalog, an object_store and a visualization server
which all require credentials to access them. We will use Kubernetes secrets to
store this confidential information. Please make sure to use secure passwords in
production environments.

1. Postgres

```shell
kubectl create secret generic postgres-secret --from-literal=password=postgres --from-literal=catalog-url=postgres://postgres:postgres@postgres:5432
export POSTGRES_PASSWORD=postgres
```

2. Arrow Flight

```shell
kubectl create secret generic arrow-flight-secret --from-literal=password=flight_password
```

3. Superset

```shell
kubectl create secret generic superset-secret --from-literal=admin-password=password
```

4. S3 (Localstack)

```shell
kubectl create secret generic aws-secret --from-literal=secret_access_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
export AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

### Start Services

Now, we can start the individual services by applying the provided configuration
files.

1. Start Postgres

```shell
kubectl apply -f kubernetes/postgres.yaml
```

2. Start Localstack S3

```shell
kubectl apply -f kubernetes/localstack.yaml
```

3. Start Arrow Flight Server

```shell
kubectl apply -f kubernetes/arrow-flight.yaml
```

4. Start Superset

```shell
kubectl apply -f kubernetes/superset.yaml
```

5. Grant argo permissons

```shell
kubectl apply -f kubernetes/role.yaml
```

### Check that all pods are running

To start the pods, the cluster will download the required containers. This might
take some time. Please use the following command to check if all pods are
running as expected.

```shell
kubectl get pods
```

### Port-Forwarding

In a production environment you would create ingress resources to get access to
the services. To simplify the process, we will skip this step in this tutorial
and use port-forwarding to allow connections to the pods.

```shell
./kubernetes/port-forwarding.sh
```

After finishing these steps you should have all the required kubernetes services
running.

## Extract & Load (EL)

Now that we have everything setup, we can start with the actual tutorial. In
most cases, data systems are composed of a transactional and an analytical part.
Transactional systems read and write single entries while analytical
systems answer aggregate queries on multiple entries. In this tutorial, the
postgres database, that we've setup, plays the role of the transactional system
and the lakehouse will play the role of the analytical system. We will create
the lakehouse by applying the Extract-Load-Transform (ELT) paradigm. By doing
so, we will first copy the data from the transactional system to the analytical
system without applying any transformations. This is called the EL step, which
we will do next.

### Configure Singer Tap and Target

Dashtool handles the EL step by leveraging the [Singer](www.singer.io)
specification. The Singer specification defines a standard way to communicate
between data sources and destinations, called Taps and Targets.

Let's define a Singer Tap to extract the data from the Postgres database and a
Singer Target to load it in to an Iceberg table. For that we can checkout the
`bronze` branch.

```shell
git checkout bronze
```

You will see the `tap.json` and `target.json` files in the `bronze/inventory`
folder.

#### Tap

The `tap.json` file contains the configuration parameters for the
[Pipelinewise Postgres Tap](https://github.com/transferwise/pipelinewise-tap-postgres).
It contains information about the connection, which schemas to extract and what
kind of replication to use. One great thing about the Pipelinewise Postgres Tap
is that it allows a log based replication which enables incremental extraction
of the data without difficult setup.

```json
{
  "host": "postgres",
  "port": 5432,
  "user": "postgres",
  "password": "$POSTGRES_PASSWORD",
  "dbname": "postgres",
  "filter_schemas": "inventory",
  "default_replication_method": "LOG_BASED"
}
```

#### Target

The `target.json` file contains configuration parameters for the
[Iceberg Target](https://github.com/dashbook/target-iceberg). It contains
information about which tables to extract, which iceberg catalog to use and
parameters for the S3 object store.

```json
{
  "image": "ghcr.io/dashbook/pipelinewise-tap-postgres:sql",
  "streams": {
    "inventory-orders": { "identifier": "bronze.inventory.orders" },
    "inventory-customers": { "identifier": "bronze.inventory.customers" },
    "inventory-products": { "identifier": "bronze.inventory.products" }
  },
  "catalogName": "bronze",
  "catalogUrl": "postgres://postgres:postgres@postgres:5432",
  "awsRegion": "us-east-1",
  "awsAccessKeyId": "AKIAIOSFODNN7EXAMPLE",
  "awsSecretAccessKey": "$AWS_SECRET_ACCESS_KEY",
  "awsEndpoint": "http://localstack:4566",
  "awsAllowHttp": "true",
  "bucket": "s3://example-postgres"
}
```

### Dashtool build

The build command creates a graph of all the entities we have created. So far we
only defined tables for ingestion, but we will soon ad more complex
transformations. One important thing to note is that the build command takes the
current git branch into account. Since Iceberg Tables support branching,
dashtool will create the table with the corresponding branch. Since we are
currently in the `bronze` branch, dashtool will create a `bronze` branch for the
created tables.

```shell
dashtool build
```

### Dashtool workflow

The workflow command takes the graph, generated by the build command, and
creates an Argo Workflow that can be used to update the data in the tables. The
output of the command is written to the `argo/workflow.yaml` file.

```shell
dashtool workflow
```

### Create argo workflow

By executing the following command you deploy the created Workflow to the
Kubernetes cluster. Be default the workflow is defined as a "Cron" workflow that
will execute daily. If you want to change this, you can edit the
`argo/workflow.yaml` file.

```shell
kubectl apply -f argo/workflow.yaml
```

### Run Argo Workflow

Navigate your browser to `https://localhost:2746` to access the Argo Workflow
UI. As mentioned earlier, you might see a warning from the browser that the page
uses a self-signed certificate, which is okay for our use case.

Go to the "Cron Workflows" tab on the left and select the "dashtool" workflow.
By pressing "run", the workflow will start and you will see information about
the individual steps.

### Merge changes into main

If your workflows ran successfully, you can merge the changes into the main
branch.

```shell
git checkout main
git merge bronze
```

## Transform (T)

Now that we loaded the data from the data source into the lakehouse, it's time
to transform the data according to our needs. In this tutorial we will create a
"Medallion" architecture with a "bronze", a "silver" and a "gold" layer. The
"bronze" layer contains replicated data from the source system. The "silver"
layer contains cleansed, merged, conformed, and anonymised data from the
"bronze" layer. It provides a solid basis for further analysis. The "gold" layer
provides consumption ready data sets for Business intelligence, reporting and
Machine learning.

We can see example transformations by checking out the silver branch.

```shell
git checkout silver
```

### Transformation for the Fact table

Dashtool will create a Materialized view for every `.sql` file in the directory
tree. We can see one example in `silver/inventory/fact_order.sql`, which will
create the Materialized View `silver.inventory.fact_order`. As you can see, we
are renaming the columns to fit to our organizational standards.

The "silver" layer is a good place to apply
[Dimensional Modeling](https://en.wikipedia.org/wiki/Dimensional_modeling).
Dimensional Modeling distinguishes between qualitative and quantitative data and
separates them into dimension and fact tables, respectively. The Orders table
contains the `quantity` column as a quantitative measure and is therefore a fact
table. It is related to the dimension tables `dim_customer` and `dim_product`
through the colums `customerId` and `productId`.

```sql
select 
  id as orderId,
  order_date as date,
  quantity,
  purchaser as customerId,
  product_id as productId 
from 
  bronze.inventory.orders;
```

### Dashtool build

By running the dashtool build command, we will create the corresponding
Materialized Views in the lakehouse. Keep in mind that we are currently on the
"silver" branch and therefore the materialized views are created with a "silver"
branch.

```shell
dashtool build
```

### Dashtool workflow

By running the dashtool workflow command, we will create an Argo Workflow that
creates jobs to refresh the previously created Materialized Views. Refreshing
the Materialized View means checking if the data in the source tables has
changed and if so, updating the data in the Materialized View.

```shell
dashtool workflow
```

### Create argo workflow

To apply the updated workflow, execute the following command. Similar to before,
you can go to the Argo Workflows UI to start the workflow, otherwise it will
start according to its schedule.

```shell
kubectl apply -f argo/workflow.yaml
```

### Merge changes into main

If your workflows ran successfully, you can merge the changes into the main
branch.

```shell
git checkout main
git merge silver
```

## Analysis

Now that we have clean and properly modeled data in the lakehouse, we can start
answering questions about our data. This is what the "gold" layer is for.

To see an example analysis, checkout the "gold" branch.

```shell
git checkout gold
```

### Transformation to calculate monthly weight

Let's perform an example analysis that is typically performed in the "gold"
layer. Imagine we are a retail company and we need to estimate the number of
trucks we need each month. To do so, we need to calculate the total weight of
all orders per month. We can calculate this with the following query by joining
the `fact_orders` table with the `dim_product` table. It is typical for queries
in the "gold" layer to compute some kind of aggregation.

```sql
select
  sum(o.quantity * p.weight),
  date_trunc('month', o.date) as month
from 
  silver.inventory.fact_order as o
join
  silver.inventory.dim_product as p
on
  o.productId = p.productId
group by
  month;
```

### Dashtool build

Again, we will create the corresponding Materialized Views by running the
Dashtool build command.

```shell
dashtool build
```

### Dashtool workflow

And create the updated Argo Workflow by running the Dashtool workflow command.

```shell
dashtool workflow
```
  
### Create argo workflow

As before, we have to apply the updated workflow to the Kubernetes cluster.

```shell
kubectl apply -f argo/workflow.yaml
```

### Merge changes into main

If the transformations ran successfully, you can merge the gold branch into the
main branch.

```shell
git checkout main
git merge gold
```

The last time we execute the dashtool `build` command we were still on the `gold` branch, which means that the newly created entities in the lakehouse are also on the gold branch.
In order to merge them to the `main` branch we have to execute dashtool `build` again on the main branch. So let's do that.

```shell
dashtool build
```

Similarly, the current workflow will refresh the data on the gold branch. Let's execute dashtool `workflow` on the main branch so that the workflow will refresh the data on the main branch.

```shell
dashtool workflow
```

And let's apply the newest version to the Kubernetes cluster.

```shell
kubectl apply -f argo/workflow.yaml
```

## Analysis

We finally transformed the data so that it can be used by downstream consumers. The data is typically used for business intelligence or machine learning. Let's connect our BI tool to the data and see what we calulated.
Head to the address `http://localhost:8088` to open Apache Superset. Use the credentails username: "admin" and password: "password" to login.
As a first step we have to add our Arrow Flight Server as a Database. 

1. To do that, click on "Settings" in the upper right corner and under "Data" click "Database Connections".
2. On the next screen click "+ Database" also in the uppper right corner. 
3. In the "Connect a Database" window, click the "SUPPORTED DATABASES" drop-down menu and select "Other".
4. Use "Flight SQL" as the "DISPLAY NAME".
5. Enter the "SQLALCHEMY_URI":

MacOs/Windows
```
adbc_flight_sql://flight_username:flight_password@host.docker.internal:31337?disableCertificateVerification=True&useEncryption=True
```

Linux
```
adbc_flight_sql://flight_username:flight_password@172.17.0.1:31337?disableCertificateVerification=True&useEncryption=True
```

6. Click the "TEST CONNECTION" button to test if everything works as expected
7. Click the "CONNECT" button to save the database connection

Now that we a connection to the Arrow Flight Server, we can query the data in the lakehouse. So let's test it out.

1. Click the "SQL" drop down menu in the top left corner and select "SQL Lab"
2. Write a query that you want to execute:
```sql
SELECT * FROM gold.inventory.monthly_ordered_weight;
```
3. Click the "RUN" button

## Refresh data

The great thing about using materialized views for the transformation is that they automatically keep themselves up-to-date. 
To test this functionality, we will insert additional entries into our operational database and check how the data in the lakehouse changes.
To insert the data to the postgres database, connect to the database:

```shell
psql -h localhost -U postgres
```

The following command generates some more test data:

```sql
INSERT INTO inventory.orders (id, order_date, purchaser, quantity, product_id) VALUES
(10005, '2016-03-05', 1004, 3, 108),
(10006, '2016-03-10', 1001, 1, 103),
(10007, '2016-03-15', 1002, 2, 109),
(10008, '2016-04-20', 1003, 1, 104),
(10009, '2016-04-25', 1004, 3, 105),
(10010, '2016-04-01', 1001, 1, 105),
(10011, '2016-05-05', 1002, 2, 101),
(10012, '2016-05-10', 1003, 1, 106),
(10013, '2016-05-15', 1004, 3, 103),
(10014, '2016-06-20', 1001, 1, 107),
(10015, '2016-06-25', 1002, 2, 103),
(10016, '2016-06-30', 1003, 1, 108);
```

Now head to the Argo Workflow Console at `https://localhost:2746` and execute the workflow again. Alternatively you could wait until the workflow automatically executes on the schedule.
Once it finished, go to Superset and view the updated data.

Congratulations, just just setup your own lakehouse and executed an end to end declarative data pipeline!
