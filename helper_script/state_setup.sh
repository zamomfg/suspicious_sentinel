#!/bin/bash

APP_NAME="log"
LOCATION="swedencentral"
LOCATION_SHORT="sc"

RESOURCE_GROUP_NAME=rg-terrastate-$LOCATION_SHORT-001
STORAGE_ACCOUNT_NAME=satfstate$APP_NAME$LOCATION_SHORT$RANDOM
CONTAINER_NAME=tfstate-$APP_NAME

groups=$(az group list | jq -r '.[] | .name')
exists=0

for rg in $groups;
do
    if [ "$rg" = "$RESOURCE_GROUP_NAME" ]; then
        echo "RG with the name allready exists, reusing the RG"
        exists=1
        break
    fi
done

if [[ $exists -eq 0 ]]; then
    az group create --name $RESOURCE_GROUP_NAME --location $LOCATION
fi

sa_id=$(az storage account create --resource-group $RESOURCE_GROUP_NAME --name $STORAGE_ACCOUNT_NAME --sku Standard_LRS --encryption-services blob | jq -r '.id')

az storage container create --name $CONTAINER_NAME --account-name $STORAGE_ACCOUNT_NAME


app_info=$(az ad sp create-for-rbac --name github_action_$APP_NAME)

# echo "App id: $(echo $app_info | jq -r '.appId')"

# echo $app_info

az role assignment create --role "Storage Blob Data Contributor" --assignee-object-id "$(echo $app_info | jq -r '.appId')" --assignee-principal-type "ServicePrincipal" --scope "$sa_id/blobServices/default/containers/$CONTAINER_NAME"


echo $app_info | jq -r '.displayName'

echo "AZURE_CLIENT_ID: $(echo $app_info | jq -r '.appId')"
echo "AZURE_SUBSCRIPTION_ID: $(az account show | jq -r '.id')"
echo "AZURE_TENANT_ID: $(echo $app_info | jq -r '.tenant')"

echo "STATE_RESOURCE_GROUP_NAME: $RESOURCE_GROUP_NAME"
echo "STATE_STORAGE_ACCOUNT_NAME: $STORAGE_ACCOUNT_NAME"
echo "STATE_CONTAINER_NAME: $CONTAINER_NAME"