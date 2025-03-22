#!/bin/bash

# Script for generating a json file for log decleration from a string of comma seperated values
# Example usage
# ./createLogDeclaration.sh "TimeGenerated, Action, Message" 

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