#!/bin/bash
cd "$(dirname "$0")"

if [ "$1" != "no-build" ]; then

    docker build -t test1-image .
    if [ $? -ne 0 ] ; then
        echo 'Docker build failed'
        exit 1
    fi

    docker tag test1-image gcr.io/alfa-prd/test1-image:latest
    if [ $? -ne 0 ] ; then
        echo 'Docker tag failed'
        exit 1
    fi

    docker push gcr.io/alfa-prd/test1-image:latest
    if [ $? -ne 0 ] ; then
        echo 'Docker push failed'
        exit 1
    fi

fi

gcloud run services replace service.yaml
if [ $? -ne 0 ] ; then
    echo 'gcloud run services replace failed'
    exit 1
fi
