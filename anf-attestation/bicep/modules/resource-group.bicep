// modules/resource-group.bicep — Creates the demo resource group.
//
// Must run at subscription scope because resource groups are subscription-level
// resources in Azure Resource Manager.

targetScope = 'subscription'

@description('Name of the resource group to create.')
param resourceGroupName string

@description('Azure region for the resource group.')
param location string

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: {
    purpose: 'anf-attestation-demo'
    managedBy: 'bicep'
  }
}

output resourceGroupName string = rg.name
