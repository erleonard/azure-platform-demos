// main.bicep — Subscription-scoped orchestration for the ANF attestation demo.
//
// Deploy with:
//   az deployment sub create \
//     --location canadacentral \
//     --template-file bicep/main.bicep \
//     --parameters bicep/main.bicepparam
//
// Or use the one-shot helper:
//   bash bicep/scripts/deploy.sh

targetScope = 'subscription'

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------

@description('Short prefix applied to every resource name.')
@minLength(2)
@maxLength(8)
param prefix string = 'attestation'

@description('Azure region for all resources.')
param location string = 'canadacentral'

@description('VNet address space in CIDR notation.')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Subnet delegated to Microsoft.NetApp/volumes.')
param anfSubnetPrefix string = '10.0.1.0/24'

@description('Subnet for the Windows source file server.')
param serverSubnetPrefix string = '10.0.3.0/24'

@description('Subnet for Azure Bastion (must be /26 or larger).')
param bastionSubnetPrefix string = '10.0.5.0/26'

@description('ANF capacity pool service level.')
@allowed(['Standard', 'Premium', 'Ultra'])
param anfServiceLevel string = 'Standard'

@description('ANF capacity pool provisioned size in TiB (minimum 2).')
@minValue(2)
param anfPoolSizeInTib int = 2

@description('ANF volume provisioned size in GiB (minimum 100).')
@minValue(100)
param anfVolumeSizeInGib int = 100

@description('Deploy the Windows source file server, Linux migration host, and Bastion.')
param deployWorkloadVms bool = true

@description('Local administrator username for the demo VMs.')
param adminUsername string = 'azureadmin'

@description('Local administrator password for the demo VMs. Supply via env var, never commit it.')
@secure()
param adminPassword string = ''

@description('Size for the demo VMs (Gen2-capable).')
param vmSize string = 'Standard_D2s_v5'

@description('Resource ID of the Enforce-Sov-L1-Regions (allowed locations) policy assignment. Assigned at the "alz" management group; a subscription-scoped waiver lets the demo deploy outside the SLZ default regions (canadacentral/canadaeast).')
param sovL1RegionsPolicyAssignmentId string = '/providers/Microsoft.Management/managementGroups/alz/providers/Microsoft.Authorization/policyAssignments/Enforce-Sov-L1-Regions'

// ---------------------------------------------------------------------------
// Resource group
// ---------------------------------------------------------------------------

// Deterministic name so it can be used as a module `scope` (scope must be
// resolvable at the start of deployment; a module output cannot — BCP120).
var resourceGroupName = '${prefix}-rg'

// Subscription-scoped waiver for the Sovereignty Baseline – Global (L1)
// allowed-locations policy (assigned at the "alz" MG with
// listOfAllowedLocations = canadacentral/canadaeast). This must be at
// subscription scope because the resource-group creation itself is evaluated
// at subscription scope — an RG-scoped exemption cannot cover it.
resource sovL1RegionsExemption 'Microsoft.Authorization/policyExemptions@2022-07-01-preview' = {
  name: 'exempt-sov-l1-regions'
  properties: {
    policyAssignmentId: sovL1RegionsPolicyAssignmentId
    exemptionCategory: 'Waiver'
    displayName: 'Waive Sovereignty L1 allowed-locations for the attestation demo'
    description: 'Allows the demo to deploy in ${location}, outside the SLZ default allowed regions (canadacentral/canadaeast).'
  }
}

module rg './modules/resource-group.bicep' = {
  name: 'rgDeployment'
  dependsOn: [sovL1RegionsExemption]
  params: {
    resourceGroupName: resourceGroupName
    location: location
  }
}

// ---------------------------------------------------------------------------
// Policy exemptions (SLZ guardrail waivers scoped to the demo RG)
// ---------------------------------------------------------------------------

module policyExemptions './modules/policy-exemptions.bicep' = {
  name: 'policyExemptionsDeployment'
  scope: resourceGroup(resourceGroupName)
  dependsOn: [rg]
}

// ---------------------------------------------------------------------------
// Log Analytics workspace (audit backbone)
// ---------------------------------------------------------------------------

module logAnalytics './modules/log-analytics.bicep' = {
  name: 'logAnalyticsDeployment'
  scope: resourceGroup(resourceGroupName)
  dependsOn: [rg]
  params: {
    prefix: prefix
    location: location
  }
}

// ---------------------------------------------------------------------------
// Virtual network (ANF delegated subnet + server + Bastion subnets)
// ---------------------------------------------------------------------------

module vnet './modules/virtual-network.bicep' = {
  name: 'vnetDeployment'
  scope: resourceGroup(resourceGroupName)
  dependsOn: [rg, policyExemptions]
  params: {
    prefix: prefix
    location: location
    addressPrefix: vnetAddressPrefix
    anfSubnetPrefix: anfSubnetPrefix
    serverSubnetPrefix: serverSubnetPrefix
    bastionSubnetPrefix: bastionSubnetPrefix
  }
}

// ---------------------------------------------------------------------------
// Azure NetApp Files account, capacity pool, and volume
// ---------------------------------------------------------------------------

module netapp './modules/netapp-account.bicep' = {
  name: 'netappDeployment'
  scope: resourceGroup(resourceGroupName)
  params: {
    prefix: prefix
    location: location
    anfSubnetId: vnet.outputs.anfSubnetId
    allowedCidr: vnetAddressPrefix
    serviceLevel: anfServiceLevel
    poolSizeInTib: anfPoolSizeInTib
    volumeSizeInGib: anfVolumeSizeInGib
  }
}

// ---------------------------------------------------------------------------
// Diagnostic settings → Log Analytics (ANF volume metrics)
// ---------------------------------------------------------------------------

module diagnostics './modules/diagnostic-settings.bicep' = {
  name: 'diagnosticsDeployment'
  scope: resourceGroup(resourceGroupName)
  params: {
    anfAccountName: netapp.outputs.anfAccountName
    anfPoolName: netapp.outputs.anfPoolName
    anfVolumeName: netapp.outputs.anfVolumeName
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
  }
}

// ---------------------------------------------------------------------------
// Workload VMs: Windows source file server + Linux migration host + Bastion
// ---------------------------------------------------------------------------

module bastion './modules/bastion.bicep' = if (deployWorkloadVms) {
  name: 'bastionDeployment'
  scope: resourceGroup(resourceGroupName)
  params: {
    prefix: prefix
    location: location
    bastionSubnetId: vnet.outputs.bastionSubnetId
  }
}

module windowsServer './modules/windows-server.bicep' = if (deployWorkloadVms) {
  name: 'windowsServerDeployment'
  scope: resourceGroup(resourceGroupName)
  params: {
    prefix: prefix
    location: location
    subnetId: vnet.outputs.serverSubnetId
    adminUsername: adminUsername
    adminPassword: adminPassword
    vmSize: vmSize
    anfMountIp: netapp.outputs.mountTargetIpAddress
    anfVolumeName: netapp.outputs.anfVolumeName
  }
}

// ---------------------------------------------------------------------------
// Outputs — consumed by deploy.sh for the migration showcase
// ---------------------------------------------------------------------------

output resourceGroupName string = rg.outputs.resourceGroupName
output location string = location
output anfAccountName string = netapp.outputs.anfAccountName
output anfPoolName string = netapp.outputs.anfPoolName
output anfVolumeName string = netapp.outputs.anfVolumeName
output anfMountTargetIp string = netapp.outputs.mountTargetIpAddress
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId
output logAnalyticsWorkspaceName string = logAnalytics.outputs.workspaceName
output bastionName string = bastion.?outputs.bastionName ?? ''
output windowsVmName string = windowsServer.?outputs.vmName ?? ''
output windowsComputerName string = windowsServer.?outputs.computerName ?? ''
output windowsPrivateIp string = windowsServer.?outputs.privateIp ?? ''
output sourceShareName string = windowsServer.?outputs.shareName ?? ''
