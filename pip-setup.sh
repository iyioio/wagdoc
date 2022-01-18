#!/bin/bash

name=$1

if [ "$name" == "" ]; then
    echo "First argument should be name"
    exit 1
fi

python3 -m venv $name/env
source $name/env/bin/activate
pip install wagtail
wagtail start $name $name
cat $name-requirements.txt >> $name/requirements.txt
cd $name
pip install -r requirements.txt