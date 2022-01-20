# Wagdoc
An easy way to deploy Wagtail to GCloud using Cloud Run.

## What does Wagdoc do?
In summary Wagdoc deploys a Wagtail site as a Google Cloud Run service that connects to a Google
Cloud SQL database and uses a Google Cloud Storage bucket for file storage.

## Config
Wagdoc uses a single JSON configuration file.

``` jsonc
{
    // Name of wagtail site
    "name":"example",

    // Google Cloud or Firebase project name
    "project":"my-project",

    // Region to deploy in
    "region":"europe-west1",

    // Database type. For now should always be pgsql
    "dbEngine":"pgsql",

    // Database name
    "dbName":"cmsdb",

    // Cloud SQL instance name
    "dbInstance":"cmssql",

    // Database username. This user will be created
    "dbUser":"cmsuser",

    // Private IP of Cloud SQL instance
    "dbHost":"10.9.212.5",

    // Database port. In almost call cases will be 5432
    "dbPort":"5432",

    // Network name
    "network":"default",

    // Virtual network connector name. If a connector with a matching name
    // does not exists the connector will be created using the configured ipRange
    "connector":"default-europe-west1",

    // ip range to use with creating a new virtual network connector
    "ipRange":"10.8.0.0/28",

    // If true Wagtail be configured to run in Debug mode
    "debug":true
}
```

## Cloud SQL configuration
Before using Wagdoc you should already have a Cloud SQL instance setup with a private IP.
- Enable billing for your project. ( Cloud SQL is a paid service ) - https://console.cloud.google.com/billing/projects
- Goto loud SQL instance ( Make sure to select the correct project) - https://console.cloud.google.com/sql/instances 
- Click "Choose PostgreSQL"
- If not not enabled click "Enabled API"
- Set instance ID and Password. Instance ID will be used to set dbInstance in your config file
- Choose the region where to create the instance. This should match the region in your config file
- For non critical use select Single zone under Zonal availability
- Expand "Customize your instance"
- Choose a Machine type that matches your needs. In most cases a standard or Lightweight type with a single core should work
- Under connections enable the private IP option
- Under "Associated networking" select a network. This network should match the network in your config file.
- If not setup already click on the "Set up connection" button and follow the steps
- Configure the remaining options to fit your needs. Remember you can always upgrade an instance.
- Once the instances is ready use the Private IP as the dbHost in your config file.


## What Google Cloud resources are created
Wagdoc creates the follow google cloud resources
- Custom service account
- Cloud SQL Postgres database on a existing Cloud SQL instance. ( You should already have a Cloud SQL Postgres instance created )
- A single database user for use by Wagtail
- A single secret that stores all secrets used by Wagtail
- A storage bucket to store static and uploaded files
- A virtual network connector to connect Wagtail to a Cloud SQL instance. An existing connector can be used.
- A Wagtail container image

## Steps
Wagdoc preforms the following steps in the listed order. The steps can be ran as a single call to the
Wagdoc script to preformed individually.

1. Creates a Wagtail site template configured to be deploy on Google Could Run or ran locally

2. Enables all required needed GCloud APIs

3. Creates a custom service account with access to only the needed resources to run Wagtail on Cloud Run

4. Stores all secrets such as database passwords and Django secret keys using GCloud secret manager

5. Configures the Wagtail project to use the custom service account

6. Creates a Cloud SQL database in a pre-existing Cloud SQL instance

7. Creates a new database user for uses by Wagtail

8. Creates a GCloud storage bucket to store uploaded content

9. Configures the bucket for public read assess and admin access for Wagtail

10. Creates a virtual network connector to allow Wagtail to connect to Cloud SQL

11. Deploys Wagtail as a new Cloud Run service

12. Enables public access to the new Cloud Run service

13. Runs the Wagtail migration script in the cloud

14. Collects Wagtail static files in the cloud


## Usage

Run all steps 
``` sh
pwsh wagdoc.ps1 -configPath ./example-config.json -allSteps
```

Run a single step
``` sh
pwsh wagdoc.ps1 -configPath ./example-config.json -step 2
```

Run individual steps and and login, set project and set region once. This is the preferred way of
Wagdoc when running steps individually since it avoids logging in and setting project and region for
every step
``` sh

# login and set project and region
pwsh wagdoc.ps1 -configPath ./example-config.json

# run step 2
pwsh wagdoc.ps1 -configPath ./example-config.json -noLogin -skipSetProjectRegion -step 2

# run step N. Replace with with step number
pwsh wagdoc.ps1 -configPath ./example-config.json -noLogin -skipSetProjectRegion -step N
```

## Args


### -configPath **(required)**
Path to a configuration file

<br/>

### -step
Specifies a step to run

<br/>

### -allSteps
Runs all steps

<br/>

### -recreateDbuser
If present and a the configured database user already exists the user will be dropped and re-created

<br/>

### -deployNoBuild
Skips the Docker build when deploying

<br/>

### -getSecrets
Prints the secrets created

<br/>

### -getUrl
Prints the URL of the Cloud Run service

<br/>

### -getServiceInfo
Prints addtional information about the cloud run service

<br/>

### -overrideTemplate
If present and the target folder for the template exists the existing template folder will be overwritten

<br/>

### -skipSetProjectRegion
Skips setting the current project and region. Useful when running steps one by one

<br/>

### -noLogin
Skips Google auth login. Useful when running steps one by one

