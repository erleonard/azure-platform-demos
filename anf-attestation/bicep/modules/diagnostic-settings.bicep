// modules/diagnostic-settings.bicep — Diagnostic settings for the ANF volume.
//
// Attaches an AllMetrics diagnostic setting on the ANF volume → Log Analytics,
// using `existing` resource references (no re-deploy of the ANF resources).

@description('Name of the NetApp account.')
param anfAccountName string

@description('Name of the ANF capacity pool.')
param anfPoolName string

@description('Name of the ANF volume.')
param anfVolumeName string

@description('Log Analytics workspace resource ID.')
param logAnalyticsWorkspaceId string

resource anfAccount 'Microsoft.NetApp/netAppAccounts@2023-07-01' existing = {
  name: anfAccountName
}

resource anfPool 'Microsoft.NetApp/netAppAccounts/capacityPools@2023-07-01' existing = {
  parent: anfAccount
  name: anfPoolName
}

resource anfVolume 'Microsoft.NetApp/netAppAccounts/capacityPools/volumes@2023-07-01' existing = {
  parent: anfPool
  name: anfVolumeName
}

// ANF volume metrics → Log Analytics
resource anfVolumeDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'attestation-anf-volume-diag'
  scope: anfVolume
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

output anfVolumeDiagId string = anfVolumeDiag.id
