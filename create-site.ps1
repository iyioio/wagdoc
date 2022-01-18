#!/usr/local/bin/pwsh
param(
    [string]$configPath=$(throw "-configPath required"),
    [switch]$noLogin,
    [int]$step=-1, # -1 == all steps
    [string]$dest
)
$ErrorActionPreference="Stop"

$config=Get-Content -Path $configPath -Raw | ConvertFrom-Json

if(!$config.name){
    throw "config.name required"
}
if(!$config.project){
    throw "config.project required"
}
if(!$config.region){
    throw "config.region required"
}
if(!$config.dbInstance){
    throw "config.dbInstance required"
}
if(!$config.dbUser){
    throw "config.dbUser required"
}
if(!$config.region){
    throw "config.region required"
}

$dbTypes=@('pgsql')
if(!$dbTypes.Contains($config.dbEngine)){
    throw "Invalid dbType. Supported types = $dbTypes"
}



$name=$config.name
$project=$config.project
$region=$config.region
$serviceName="$name-wag"
$serviceAccountName="wag-$name-sa"
$serviceEmail=''
$bucketName="$project-media"
$dir=Resolve-Path -Path "$(Split-Path $configPath)/$name"
if($dest){
    $dir=Resolve-Path -Path $dest
}
$templDir="$PSScriptRoot/template-files"
$passwordSecretName="wag-$name-db-pass"

function GeneratePassword {

    param(
        [int]$length=40
    )
    
    $chars=( ([byte]65..[byte]90) + ([byte]97..[byte]122) + ([byte]48..[byte]57))

    $buf=[System.Byte[]]::CreateInstance([System.Byte],$length)
    $stream=[System.IO.File]::OpenRead('/dev/urandom')
    $stream.Read($buf,0,$length) | Out-Null

    for($i=0;$i -lt $length;$i++){
        $buf[$i]=$chars[$buf[$i]%$chars.Length]
    }

    return [System.Text.Encoding]::ASCII.GetString($buf)
}

function Step1-CreateSiteTemplate{

    Write-Host "Step1-CreateSiteTemplate" -ForegroundColor Cyan

    if(Test-Path $dir){
        if($config.force){
            rm -rf $dir
        }else{
            throw "Site directory already exists - $dir"
        }
    }

    mkdir -p $dir
    if(!$?){throw "mkdir failed"}

    Push-Location (Split-Path $dir)

    try{

        echo "django-storages[google]==1.12.3" > "$name-requirements.txt"
        if($config.dbEngine -eq "pgsql"){
            echo "psycopg2-binary==2.9.2" >> "$name-requirements.txt"
        }

        &"$PSScriptRoot/pip-setup.sh" $name
        if(!$?){throw "pip-setup.sh failed"}

    }finally{

        if(Test-Path "$name-requirements.txt"){
            rm "$name-requirements.txt"
        }

        Pop-Location
    }

    mv "$dir/$name/settings/base.py" "$dir/$name/settings/basesettings.py" 
    if(!$?){throw "move base settings failed"}

    [string]$engine
    if($config.dbEngine -eq 'pgsql'){
        $engine='django.db.backends.postgresql_psycopg2'
    }

    $settings=Get-Content -Path "$templDir/base.py" -Raw
    $settings=$settings.Replace('[[ENGINE]]',$engine)
    $settings=$settings.Replace('[[NAME]]',$config.dbName)
    $settings=$settings.Replace('[[USER]]',$config.dbUser)
    $settings=$settings.Replace('[[PASSWORD_VAR]]',$config.dbPasswordEnvVar)
    $settings=$settings.Replace('[[HOST]]',$config.dbHost)
    $settings=$settings.Replace("'[[PORT]]'",$config.dbPort)

    Set-Content -Path "$dir/$name/settings/base.py" -Value $settings
    if(!$?){throw "Copy base settings failed"}

    $dockerfile=Get-Content -Path "$dir/Dockerfile" -Raw
    $dockerfile=$dockerfile -replace 'CMD (.*)',('# CMD $1'+"`n`nCMD set -xe; gunicorn --bind 0.0.0.0:`$PORT --workers 1 --threads 8 --timeout 0 $name.wsgi:application")
    $dockerfile=$dockerfile -replace '(RUN python manage.py collectstatic.*)','# $1'
    Set-Content -Path "$dir/Dockerfile" -Value $dockerfile

    cp "$templDir/cors.json" "$dir/cors.json"

    $service=Get-Content -Path "$templDir/service.yaml" -Raw
    $service=$service.Replace('[[SERVICE]]',$serviceName)
    $service=$service.Replace('[[IMAGE]]',"gcr.io/$($config.project)/$name-image:latest")
    $service=$service.Replace('[[PASSWORD_VAR]]',$config.dbPasswordEnvVar)
    $service=$service.Replace('[[SECRET_NAME]]',$passwordSecretName)
    $service=$service.Replace('[[BUCKET_NAME]]',$bucketName)
    Set-Content -Path "$dir/service.yaml" -Value $service

    if($config.public){
        cp "$templDir/policy.yaml" "$dir/policy.yaml"
    }

    $deployScript=Get-Content -Path "$templDir/deploy-gcloud.sh" -Raw
    $deployScript=$deployScript.Replace('[[TAG]]',"$name-image")
    $deployScript=$deployScript.Replace('[[IMAGE]]',"gcr.io/$($config.project)/$name-image:latest")
    Set-Content -Path "$dir/deploy-gcloud.sh" -Value $deployScript
    chmod +x "$dir/deploy-gcloud.sh"

}

function Step2-EnableApis{

    Write-Host "Step2-EnableApis" -ForegroundColor Cyan

    # enable required APIs
    gcloud services enable `
        run.googleapis.com `
        sql-component.googleapis.com `
        sqladmin.googleapis.com `
        compute.googleapis.com `
        cloudbuild.googleapis.com `
        secretmanager.googleapis.com `
        artifactregistry.googleapis.com
    if(!$?){throw "gcloud enable APIs"}

}

function SetServcieEmail{
    $script:serviceEmail=gcloud iam service-accounts list --filter $serviceAccountName --format "value(email)"
    if(!$?){throw "get service account email failed"}
}

function Step3-CreateServiceAccount{

    Write-Host "Step3-CreateServiceAccount" -ForegroundColor Cyan

    SetServcieEmail

    if(!$serviceEmail){
        gcloud iam service-accounts create $serviceAccountName
        if(!$?){throw "create service account failed"}
    }

    SetServcieEmail

    gcloud projects add-iam-policy-binding $project `
        --member serviceAccount:$serviceEmail `
        --role roles/cloudsql.client
    if(!$?){throw "Grant service account access to db failed"}


}

function Step4-ApplyServiceAccount{

    Write-Host "Step4-ApplyServiceAccount" -ForegroundColor Cyan

    $service=Get-Content -Path "$dir/service.yaml" -Raw
    $service=$service.Replace('[[SERVICE_ACCOUNT]]',$serviceEmail)
    Set-Content -Path "$dir/service.yaml" -Value $service

}

function Step5-CreateDbUser{

    Write-Host "Step5-CreateDbUser" -ForegroundColor Cyan

    $dbPass=GeneratePassword

    gcloud secrets delete $passwordSecretName

    printf $dbPass | gcloud secrets create $passwordSecretName --data-file=-
    if(!$?){throw "create db user password secret failed"}

    gcloud secrets add-iam-policy-binding $passwordSecretName `
        --member serviceAccount:$serviceEmail --role roles/secretmanager.secretAccessor
    if(!$?){throw "Grant service account access to password secret failed"}

    gcloud sql users create $config.dbUser --instance $config.dbInstance --password $dbPass
    if(!$?){throw "create db user failed"}

}

function Step6-CreateBucket{

    Write-Host "Step6-CreateBucket" -ForegroundColor Cyan

    gsutil mb -l $region "gs://$bucketName"
    if(!$?){throw "gcloud create bucket failed"}

}

function Step7-SetBucketCors{

    Write-Host "Step7-SetBucketCors" -ForegroundColor Cyan

    gsutil cors set cors.json "gs://$bucketName"
    if(!$?){throw "Configure bucket CORS failed"}

}

function Step8-Deploy{

    Write-Host "Step8-Deploy" -ForegroundColor Cyan
    
    ./deploy-gcloud.sh
    if(!$?){throw "deploy-gcloud.sh failed"}
}

function Step9-EnablePublic{

    Write-Host "Step9-EnablePublic" -ForegroundColor Cyan

    if($config.public){
        gcloud run services set-iam-policy $serviceName policy.yaml
        if(!$?){throw "gcloud run services set-iam-policy $serviceName policy.yaml failed"}
    }
}


if($step -eq -1 -or $step -eq 1){
    Step1-CreateSiteTemplate

    if($step -eq 1){
        Write-Host "Complete" -ForegroundColor DarkGreen
        return
    }
}

Push-Location $dir

try{

    if(!$noLogin){
        gcloud auth login
        if(!$?){throw "gcloud login failed"}
    }

    gcloud config set project $project
    if(!$?){throw "set gcloud project failed"}

    gcloud config set run/region $config.region
    if(!$?){throw "set gcloud run region failed"}

    if($step -eq -1 -or $step -eq 2){
        Step2-EnableApis
    }

    if($step -eq -1 -or $step -eq 3){
        Step3-CreateServiceAccount
    }else{
        SetServcieEmail
    }

    if($step -eq -1 -or $step -eq 4){
        Step4-ApplyServiceAccount
    }

    if($step -eq -1 -or $step -eq 5){
        Step5-CreateDbUser
    }

    if($step -eq -1 -or $step -eq 6){
        Step6-CreateBucket
    }

    if($step -eq -1 -or $step -eq 7){
        Step7-SetBucketCors
    }

    if($step -eq -1 -or $step -eq 8){
        Step8-Deploy
    }

    if($step -eq -1 -or $step -eq 9){
        Step9-EnablePublic
    }

}finally{
    Pop-Location
}

Write-Host "Complete" -ForegroundColor DarkGreen