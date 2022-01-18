#!/bin/bash
cd "$(dirname "$0")"

if [ "$1" != "no-build" ]; then

    docker build -t [[TAG]] .
    if [ $? -ne 0 ] ; then
        echo 'Docker build failed'
        exit 1
    fi

    docker tag [[TAG]] [[IMAGE]]
    if [ $? -ne 0 ] ; then
        echo 'Docker tag failed'
        exit 1
    fi

    docker push [[IMAGE]]
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