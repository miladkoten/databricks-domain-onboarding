#!/usr/bin/env bash
set -euo pipefail

LOCATION="germanywestcentral"
RG_NAME="rg-tfstate-platform-poc"
CONTAINER_NAME="tfstate"
STORAGE_ACCOUNT="sttfstate$(openssl rand -hex 4)"

echo "Creating resource group ${RG_NAME}..."
az group create \
  --name "$RG_NAME" \
  --location "$LOCATION" \
  --output none

echo "Creating storage account ${STORAGE_ACCOUNT}..."
az storage account create \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RG_NAME" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --output none

echo "Enabling blob versioning..."
az storage account blob-service-properties update \
  --account-name "$STORAGE_ACCOUNT" \
  --resource-group "$RG_NAME" \
  --enable-versioning true \
  --output none

echo "Granting yourself data-plane access..."
USER_ID=$(az ad signed-in-user show --query id -o tsv)
SA_ID=$(az storage account show \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RG_NAME" \
  --query id -o tsv)

az role assignment create \
  --assignee "$USER_ID" \
  --role "Storage Blob Data Contributor" \
  --scope "$SA_ID" \
  --output none

echo "Waiting 30s for RBAC propagation..."
sleep 30

echo "Creating container ${CONTAINER_NAME}..."
az storage container create \
  --name "$CONTAINER_NAME" \
  --account-name "$STORAGE_ACCOUNT" \
  --auth-mode login \
  --output none

echo ""
echo "Done. Add this to envs/dev/backend.tf:"
echo "  resource_group_name  = \"${RG_NAME}\""
echo "  storage_account_name = \"${STORAGE_ACCOUNT}\""
echo "  container_name       = \"${CONTAINER_NAME}\""
