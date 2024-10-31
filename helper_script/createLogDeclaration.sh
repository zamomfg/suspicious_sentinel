#!/bin/bash

input=$1

input=$( echo -n $input | tr -d " ")

echo -n $input | jq -R  -s -c '
    split(",") | map(
    {
        name: .,
        type: "enter_type",
        description: "enter_description"
    })
'