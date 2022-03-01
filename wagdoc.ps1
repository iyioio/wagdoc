#!/usr/local/bin/pwsh
param(
    [string]$configPath=$(throw "-configPath required"),
    [switch]$noLogin,
    [int]$step=-2, # -1 == all steps, -2 == no steps
    [switch]$allSteps,
    [switch]$recreateDbuser,
    [switch]$deployNoBuild,
    [switch]$getSecrets,
    [switch]$getUrl,
    [switch]$getAdminLogin,
    [switch]$getServiceInfo,
    [switch]$overrideTemplate,
    [switch]$skipSetProjectRegion,
    [switch]$migrate
)
$ErrorActionPreference="Stop"

$migrateStepIndex=13

if($migrate){
    $step=$migrateStepIndex
}

if($allSteps){
    $step=-1
}

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
$connectorName=$config.connector
$serviceEmail=''
$bucketName="$project-$name-media"
$dbPassword=''
$secretKey=''
$templDir="$PSScriptRoot/template-files"
$secretName="wag-$name"


$dir="$(Split-Path $configPath)/$name"
$exists=Test-Path $dir
if(!$exists){
    mkdir -p $dir
}
$dir=Resolve-Path -Path $dir


if(!$?){throw "mkdir failed"}

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

function CreateSiteTemplate{

    Write-Host "CreateSiteTemplate" -ForegroundColor Cyan

    if($exists){
        if($overrideTemplate){
            rm -rf $dir
            mkdir -p $dir
        }else{
            throw "Site directory already exists - $dir"
        }
    }

    Push-Location (Split-Path $dir)

    try{

        echo "django-storages[google]==1.12.3" > "$name-requirements.txt"
        echo "django-environ==0.8.1" >> "$name-requirements.txt"
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

    [string]$engine
    if($config.dbEngine -eq 'pgsql'){
        $engine='django.db.backends.postgresql_psycopg2'
    }

    echo "" >> "$dir/.dockerignore"
    echo "# local" >> "$dir/.dockerignore"
    echo "/policy.yaml" >> "$dir/.dockerignore"
    echo "/service.yaml" >> "$dir/.dockerignore"
    echo "/deploy-gcloud.sh" >> "$dir/.dockerignore"
    echo "/cors.json" >> "$dir/.dockerignore"
    echo "/$name/settings_local.py" >> "$dir/.dockerignore"
    echo "/.env-secrets" >> "$dir/.dockerignore"
    echo "/gcloud-manage.ps1" >> "$dir/.dockerignore"
    echo "/add-migration.sh" >> "$dir/.dockerignore"

    $file=Get-Content -Path "$dir/$name/settings/base.py" -Raw
    $file=$file -replace 'PROJECT_DIR\s=','PROJECT_DIR = os.path.dirname(os.path.abspath(__file__)) #'
    Set-Content -Path "$dir/$name/settings_base.py" -Value $file

    cp "$templDir/_.gitignore" "$dir/.gitignore"
    if(!$?){throw "Copy .gitignore failed"}

    echo "settings_local.py" >> "$dir/$name/.gitignore"

    echo '# Put local developer settings in this file' >> "$dir/$name/settings_local.py"

    cp "$templDir/api.py" "$dir/$name/api.py"
    if(!$?){throw "Copy api.py failed"}

    $file=Get-Content -Path "$templDir/manage-app.py" -Raw
    $file=$file.Replace('[[APP_NAME]]',$name)
    Set-Content -Path "$dir/$name/manage-app.py" -Value $file

    $file=Get-Content -Path "$templDir/settings.py" -Raw
    $file=$file.Replace('[[APP_NAME]]',$name)
    Set-Content -Path "$dir/$name/settings.py" -Value $file

    rm -rf "$dir/$name/settings"
    if(!$?){throw "Remove old settings failed"}

    echo '' >> "$dir/$name/urls.py"
    echo 'from .api import api_router' >> "$dir/$name/urls.py"
    echo 'urlpatterns = [path("api/v2/", api_router.urls)] + urlpatterns' >> "$dir/$name/urls.py"
    echo '' >> "$dir/$name/urls.py"

    $dockerfile=Get-Content -Path "$dir/Dockerfile" -Raw
    $dockerfile=$dockerfile -replace 'CMD (.*)',('# CMD $1'+"`n`nCMD set -xe; gunicorn --bind 0.0.0.0:`$PORT --workers 1 --threads 8 --timeout 0 $name.manage-app:app")
    $dockerfile=$dockerfile -replace '(RUN python manage.py collectstatic.*)','# $1'
    Set-Content -Path "$dir/Dockerfile" -Value $dockerfile

    $file=Get-Content -Path "$dir/manage.py" -Raw
    $file=$file.Replace("$name.settings.dev","$name.settings")
    Set-Content -Path "$dir/manage.py" -Value $file

    $file=Get-Content -Path "$dir/$name/wsgi.py" -Raw
    $file=$file.Replace("$name.settings.dev","$name.settings")
    Set-Content -Path "$dir/$name/wsgi.py" -Value $file

    cp "$templDir/cors.json" "$dir/cors.json"
    if(!$?){throw "Copy cors.json failed"}

    mkdir "$dir/$name/migrations"
    touch "$dir/$name/migrations/__init__.py"
    cp "$templDir/0001_createsuperuser.py" "$dir/$name/migrations/0001_createsuperuser.py"

    $service=Get-Content -Path "$templDir/service.yaml" -Raw
    $service=$service.Replace('[[APP_NAME]]',$name)
    $service=$service.Replace('[[DEBUG]]',$config.debug ? "1" : "0")
    $service=$service.Replace('[[SERVICE]]',$serviceName)
    $service=$service.Replace('[[CONNECTOR_NAME]]',$connectorName)
    $service=$service.Replace('[[IMAGE]]',"gcr.io/$($config.project)/$name-image:latest")
    $service=$service.Replace('[[SECRET_NAME]]',$secretName)
    $service=$service.Replace('[[BUCKET_NAME]]',$bucketName)
    $service=$service.Replace('[[ENGINE]]',$engine)
    $service=$service.Replace('[[NAME]]',$config.dbName)
    $service=$service.Replace('[[USER]]',$config.dbUser)
    $service=$service.Replace('[[HOST]]',$config.dbHost)
    $service=$service.Replace('[[PORT]]',$config.dbPort)
    Set-Content -Path "$dir/service.yaml" -Value $service

    cp "$templDir/policy.yaml" "$dir/policy.yaml"
    if(!$?){throw "Copy policy.yaml failed"}

    $deployScript=Get-Content -Path "$templDir/deploy-gcloud.sh" -Raw
    $deployScript=$deployScript.Replace('[[TAG]]',"$name-image")
    $deployScript=$deployScript.Replace('[[IMAGE]]',"gcr.io/$($config.project)/$name-image:latest")
    Set-Content -Path "$dir/deploy-gcloud.sh" -Value $deployScript
    chmod +x "$dir/deploy-gcloud.sh"

    cp "$templDir/gcloud-manage.ps1" "$dir/gcloud-manage.ps1"
    if(!$?){throw "Copy gcloud-manage.ps1 failed"}
    chmod +x "$dir/gcloud-manage.ps1"

    cp "$templDir/add-migration.sh" "$dir/add-migration.sh"
    if(!$?){throw "Copy add-migration.sh failed"}
    chmod +x "$dir/add-migration.sh"

}

function EnableApis{

    Write-Host "EnableApis" -ForegroundColor Cyan

    # enable required APIs
    gcloud services enable `
        vpcaccess.googleapis.com `
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

function CreateServiceAccount{

    Write-Host "CreateServiceAccount" -ForegroundColor Cyan

    SetServcieEmail

    if(!$script:serviceEmail){
        gcloud iam service-accounts create $serviceAccountName
        if(!$?){throw "create service account failed"}

        SetServcieEmail

        $attempt=0
        while(!$script:serviceEmail){
            sleep 2
            SetServcieEmail
            $attempt++
            if($attempt -gt 10){
                throw "Taking to long to get service account info"
            }
        }

        Write-Host "service account - $script:serviceEmail" -ForegroundColor Cyan
    }

    gcloud projects add-iam-policy-binding $project `
        --member serviceAccount:$script:serviceEmail `
        --role roles/cloudsql.client
    if(!$?){throw "Grant service account access to db failed"}


}

function LoadSecrets{
    param(
        [switch]$print,
        [switch]$returnVars
    )
    $content=(gcloud secrets versions access latest --secret=$secretName | Join-String -Separator "`n").Split("`n")

    $vars=@{}

    foreach($line in $content){
        $parts=$line.Split('=',2)
        $vars[$parts[0]]=$parts[1]
    }

    $script:dbPassword=$vars.WAG_PASSWORD
    $script:secretKey=$vars.SECRET_KEY

    if($print){
        $vars
    }

    if($returnVars){
        return $vars
    }

}

function CreateSecrets{

    Write-Host "CreateSecrets" -ForegroundColor Cyan

    try{
        echo "WAG_PASSWORD=$(GeneratePassword)" > "$dir/.env-secrets"
        echo "SECRET_KEY=$(GeneratePassword -length 60)" >> "$dir/.env-secrets"
        echo "MANAGE_SECRET_KEY=$(GeneratePassword -length 60)" >> "$dir/.env-secrets"
        echo "WAG_ADMIN_PASSWORD=$(GeneratePassword -length 20)" >> "$dir/.env-secrets"

        gcloud secrets delete $secretName

        gcloud secrets create $secretName --data-file "$dir/.env-secrets"
        if(!$?){throw "create db user password secret failed"}

        gcloud secrets add-iam-policy-binding $secretName `
            --member serviceAccount:$serviceEmail --role roles/secretmanager.secretAccessor
        if(!$?){throw "Grant service account access to password secret failed"}

    }finally{
        rm -f "$dir/.env-secrets"
    }

    LoadSecrets
}

function ApplyServiceAccount{

    Write-Host "ApplyServiceAccount" -ForegroundColor Cyan

    $service=Get-Content -Path "$dir/service.yaml" -Raw
    $service=$service.Replace('[[SERVICE_ACCOUNT]]',$serviceEmail)
    Set-Content -Path "$dir/service.yaml" -Value $service

}

function CreateDb{

    Write-Host "CreateDb" -ForegroundColor Cyan

    $ErrorActionPreference="SilentlyContinue"
    gcloud sql databases describe $config.dbName --instance $config.dbInstance 2>&1 | Out-Null
    $result=$?
    $ErrorActionPreference="Stop"

    if(!$result){
        Write-Host "Creating db $($config.dbName)"
        gcloud sql databases create $config.dbName --instance $config.dbInstance
        if(!$?){throw "create db failed"}
    }else{
        Write-Host "Db already exists $($config.dbName)"
    }
}

function CreateDbUser{

    Write-Host "CreateDbUser" -ForegroundColor Cyan

    $existing=gcloud sql users list --instance $config.dbInstance --filter $config.dbUser --format "value(name)"

    if($existing){
        if($recreateDbuser){
            gcloud sql users delete $config.dbUser --instance $config.dbInstance
            if(!$?){throw "delete db user failed"}
        }else{
            gcloud sql users set-password $config.dbUser --instance $config.dbInstance --password $dbPassword
            if(!$?){throw "update db user password failed"}
        }
    }else{
        gcloud sql users create $config.dbUser --instance $config.dbInstance --password $dbPassword
        if(!$?){throw "create db user failed"}
    }

}

function CreateBucket{

    Write-Host "CreateBucket" -ForegroundColor Cyan

    gsutil mb -l $region "gs://$bucketName"
    if(!$?){throw "gcloud create bucket failed"}

}

function ConfigureBucket{

    Write-Host "ConfigureBucket" -ForegroundColor Cyan

    gsutil cors set cors.json "gs://$bucketName"
    if(!$?){throw "Configure bucket CORS failed"}

    gsutil iam ch allUsers:objectViewer "gs://$bucketName"
    if(!$?){throw "Configure bucket permissions failed"}
    Write-Host "Bucket is now public"

    gsutil iam ch "serviceAccount:$($serviceEmail):objectAdmin" "gs://$bucketName"
    if(!$?){throw "Configure bucket permissions for service account failed"}
    Write-Host "$serviceEmail now has full access to bucket"

}

function CreateConnector{

    Write-Host "CreateConnector" -ForegroundColor Cyan

    $ErrorActionPreference="SilentlyContinue"
    $conInfo=gcloud compute networks vpc-access connectors describe $connectorName --region $config.region 2>&1 | Join-String
    $result=$?
    $ErrorActionPreference="Stop"
    
    if(!$result){
        Write-Host "Creating connector - $connectorName - $($config.network) - $($config.ipRange)"
        gcloud compute networks vpc-access connectors create $connectorName `
            --network $config.network `
            --region $config.region `
            --range $config.ipRange
        if(!$?){throw "gcloud compute networks vpc-access connectors create failed"}
    }else{
        Write-Host "Connector already exists connector - $connectorName"
        $conInfo
    }

}

function Deploy{

    Write-Host "Deploy" -ForegroundColor Cyan
    
    if($deployNoBuild){
        ./deploy-gcloud.sh no-build
    }else{
        ./deploy-gcloud.sh
    }
    if(!$?){throw "deploy-gcloud.sh failed"}
}

function EnablePublic{

    Write-Host "EnablePublic" -ForegroundColor Cyan

    gcloud run services set-iam-policy $serviceName "$dir/policy.yaml"
    if(!$?){throw "gcloud run services set-iam-policy $serviceName policy.yaml failed"}
    
}

function GetServiceInfo{

    param(
        [string]$prop
    )

    $json=gcloud run services describe $serviceName --format=json | ConvertFrom-Json

    if(!$prop){
        return $json
    }elseif($prop -eq "url"){
        return $json.status.url ? $json.status.url : $(throw "status.url not found")
    }else{
        throw "Invalid prop - $prop"
    }
}

function InvokeUtilManage{

    param(
        [string[]]$commandArgs
    )

    $url=GetServiceInfo -prop url
    $vars=LoadSecrets -returnVars

    $JSON = @{
        "key" = $vars.MANAGE_SECRET_KEY
        "args" = $commandArgs
    } | ConvertTo-Json

    Invoke-RestMethod -Uri "$url/util-manage" -Method Post -Body $JSON -ContentType "application/json"

}

function Migrate{

    Write-Host "Migrate" -ForegroundColor Cyan

    InvokeUtilManage -commandArgs @("migrate","--noinput")
    
}

function CollectStatic{

    Write-Host "CollectStatic" -ForegroundColor Cyan

    InvokeUtilManage -commandArgs @("collectstatic","--noinput")

}


if($step -eq -1 -or $step -eq 1){
    CreateSiteTemplate

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

    if(!$skipSetProjectRegion){
        gcloud config set project $project
        if(!$?){throw "set gcloud project failed"}

        gcloud config set run/region $config.region
        if(!$?){throw "set gcloud run region failed"}
    }

    if($step -eq -1 -or $step -eq 2){
        EnableApis
    }

    if($step -eq -1 -or $step -eq 3){
        CreateServiceAccount
    }else{
        SetServcieEmail
    }

    if($step -eq -1 -or $step -eq 4){
        CreateSecrets
    }elseif($step -gt 4 -or $step -eq -2){
        LoadSecrets
    }

    if($step -eq -1 -or $step -eq 5){
        ApplyServiceAccount
    }

    if($step -eq -1 -or $step -eq 6){
        CreateDb
    }

    if($step -eq -1 -or $step -eq 7){
        CreateDbUser
    }

    if($step -eq -1 -or $step -eq 8){
        CreateBucket
    }

    if($step -eq -1 -or $step -eq 9){
        ConfigureBucket
    }

    if($step -eq -1 -or $step -eq 10){
        CreateConnector
    }

    if($step -eq -1 -or $step -eq 11){
        Deploy
    }

    if($step -eq -1 -or $step -eq 12){
        EnablePublic
    }

    if($step -eq -1 -or $step -eq $migrateStepIndex){
        Migrate
    }

    if($step -eq -1 -or $step -eq 14){
        CollectStatic
    }

    if($getSecrets){
        LoadSecrets -print
    }

    if($getUrl){
        GetServiceInfo -prop url
    }

    if($getServiceInfo){
        GetServiceInfo
    }

    if($getAdminLogin -or $allSteps){
        $url=GetServiceInfo -prop url
        $vars=LoadSecrets -returnVars
        Write-Host "$url/admin/login/?next=/admin/"
        Write-Host "username: admin"
        Write-Host "password: $($vars.WAG_ADMIN_PASSWORD)"
    }

}finally{
    Pop-Location
}

Write-Host "Complete" -ForegroundColor DarkGreen
