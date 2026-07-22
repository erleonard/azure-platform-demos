// modules/log-analytics.bicep — Log Analytics workspace.
//
// Used as the central sink for:
//   - Azure NetApp Files volume metrics
//
// Retention is set to 90 days (adjust for your compliance requirements).

@description('Short prefix for resource names.')
param prefix string

@description('Azure region.')
param location string

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${prefix}-law'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 90
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
  tags: {
    purpose: 'anf-attestation-audit'
  }
}

output workspaceId string = workspace.id
output workspaceName string = workspace.name
output customerId string = workspace.properties.customerId
