# wagdoc
Dockerized Wagtail deployment on GCloud using Cloud Run

The create-site.ps1 script creates a wagtail site and all needed GCloud resources

## Usage

Run all steps 
``` sh
./create-site.ps1 -configPath ./example-config.json -allSteps

```

Run a single step
``` sh
./create-site.ps1 -configPath ./example-config.json -step 2
```

Run a single step and skip gcloud login
``` sh
./create-site.ps1 -configPath ./example-config.json -step 2 -noLogin
```