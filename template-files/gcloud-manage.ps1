#!/usr/local/bin/pwsh
param(
    [string]$configPath="$PSScriptRoot/../wagtail-config.json",
    [switch]$noLogin,
    [switch]$migrate,
    [switch]$showSecrets,
    [switch]$skipSetProjectRegion
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



$name=$config.name#
$project=$config.project#
$region=$config.region
$serviceName="$name-wag"
$serviceAccountName="wag-$name-sa"
$secretName="wag-$name"


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

    Write-Host "calling $url/util-manage"
    $content=Invoke-RestMethod -UseBasicParsing -Uri "$url/util-manage" -Method Post -Body $JSON -ContentType "application/json"

    Write-Host "Result:"
    Write-Host $content -ForegroundColor Magenta

}

function Migrate{

    Write-Host "Migrate" -ForegroundColor Cyan

    InvokeUtilManage -commandArgs @("migrate","--noinput")
    
}

Push-Location $PSScriptRoot

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

    if($showSecrets){
        LoadSecrets
    }

    if($migrate){
        Migrate
    }

}finally{
    Pop-Location
}

Write-Host "Complete" -ForegroundColor DarkGreen
