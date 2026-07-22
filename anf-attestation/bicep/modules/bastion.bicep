// modules/bastion.bicep — Azure Bastion host for private RDP/SSH to the demo VMs.
//
// The SLZ denies public IPs on workload VMs, so remote access goes through
// Azure Bastion (which terminates RDP/SSH in the browser / az CLI). The VMs
// themselves have no public IP.

@description('Short prefix for resource names.')
param prefix string

@description('Azure region.')
param location string

@description('Resource ID of the AzureBastionSubnet.')
param bastionSubnetId string

@description('Bastion SKU. Basic is sufficient for browser RDP/SSH.')
@allowed(['Basic', 'Standard'])
param sku string = 'Basic'

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: '${prefix}-bastion-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
  tags: {
    purpose: 'anf-attestation-demo'
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2023-09-01' = {
  name: '${prefix}-bastion'
  location: location
  sku: {
    name: sku
  }
  properties: {
    ipConfigurations: [
      {
        name: 'bastionIpConfig'
        properties: {
          subnet: {
            id: bastionSubnetId
          }
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
  }
  tags: {
    purpose: 'anf-attestation-demo'
  }
}

output bastionName string = bastion.name
output bastionPublicIp string = publicIp.properties.ipAddress
