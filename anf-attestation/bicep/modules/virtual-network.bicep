// modules/virtual-network.bicep — VNet with subnets.
//
// snet-anf     — Delegated to Microsoft.NetApp/volumes (required by ANF).

@description('Short prefix for resource names.')
param prefix string

@description('Azure region.')
param location string

@description('VNet address space in CIDR notation (e.g. 10.0.0.0/16).')
param addressPrefix string

@description('Subnet CIDR for the ANF delegation (e.g. 10.0.1.0/24).')
param anfSubnetPrefix string

@description('Subnet CIDR for the Windows source file server (e.g. 10.0.3.0/24).')
param serverSubnetPrefix string = '10.0.3.0/24'

@description('Subnet CIDR for Azure Bastion (must be /26 or larger, named AzureBastionSubnet).')
param bastionSubnetPrefix string = '10.0.5.0/26'

// Network Security Group required on every subnet by the ALZ policy
// "Deny-Subnet-Without-Nsg". The default NSG rules already allow intra-VNet
// traffic (needed for NFS from the client subnet and the private endpoint)
// and deny inbound from the internet, which suits this demo.
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: '${prefix}-nsg'
  location: location
  tags: {
    purpose: 'anf-attestation-demo'
  }
}

// Dedicated NSG for AzureBastionSubnet with the rules Azure Bastion requires.
// (Also satisfies Deny-Subnet-Without-Nsg for the Bastion subnet.)
resource bastionNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: '${prefix}-bastion-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowHttpsInbound'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowGatewayManagerInbound'
        properties: {
          priority: 130
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'GatewayManager'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowAzureLoadBalancerInbound'
        properties: {
          priority: 140
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowBastionHostCommunication'
        properties: {
          priority: 150
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: ['8080', '5701']
        }
      }
      {
        name: 'AllowSshRdpOutbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: ['22', '3389']
        }
      }
      {
        name: 'AllowAzureCloudOutbound'
        properties: {
          priority: 110
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureCloud'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowBastionCommunication'
        properties: {
          priority: 120
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: ['8080', '5701']
        }
      }
      {
        name: 'AllowGetSessionInformation'
        properties: {
          priority: 130
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange: '80'
        }
      }
    ]
  }
  tags: {
    purpose: 'anf-attestation-demo'
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: '${prefix}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [addressPrefix]
    }
    subnets: [
      {
        // Subnet delegated to Azure NetApp Files.
        // ANF requires an exclusive, delegated subnet. An NSG is attached to
        // satisfy the Deny-Subnet-Without-Nsg policy; ANF supports NSGs on
        // its delegated subnet.
        name: 'snet-anf'
        properties: {
          addressPrefix: anfSubnetPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
          delegations: [
            {
              name: 'netapp-delegation'
              properties: {
                serviceName: 'Microsoft.NetApp/volumes'
              }
            }
          ]
        }
      }
      {
        // Subnet for the Windows source file server.
        name: 'snet-server'
        properties: {
          addressPrefix: serverSubnetPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
      {
        // Azure Bastion requires a subnet named exactly "AzureBastionSubnet".
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: bastionSubnetPrefix
          networkSecurityGroup: {
            id: bastionNsg.id
          }
        }
      }
    ]
  }
  tags: {
    purpose: 'anf-attestation-demo'
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output anfSubnetId string = vnet.properties.subnets[0].id
output serverSubnetId string = vnet.properties.subnets[1].id
output bastionSubnetId string = vnet.properties.subnets[2].id
output vnetAddressPrefix string = addressPrefix
