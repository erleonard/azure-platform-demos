// modules/netapp-account.bicep — Azure NetApp Files account, capacity pool, and volume.
//
// Resources created:
//   1. NetApp account
//   2. Capacity pool (serviceLevel × poolSizeInTib)
//   3. NFSv4.1 volume with an export policy that restricts access to the
//      VNet CIDR passed in via allowedCidr
//
// After deployment the volume must be mounted on the client machine:
//   sudo mount -t nfs -o rw,hard,rsize=65536,wsize=65536,vers=4.1,tcp \
//     <mountTargetIpAddress>:/<volumeName> /mnt/anf/finance
//
// deploy.sh prints the exact mount command with the real IP.

@description('Short prefix for resource names.')
param prefix string

@description('Azure region.  ANF is not available in all regions.')
param location string

@description('Subnet resource ID for the ANF delegation.')
param anfSubnetId string

@description('CIDR that is allowed to mount the NFS volume (typically the VNet address space).')
param allowedCidr string

@description('ANF capacity pool service level.')
@allowed(['Standard', 'Premium', 'Ultra'])
param serviceLevel string = 'Standard'

@description('Capacity pool size in TiB (minimum 2 TiB; the 1 TiB pool is a preview feature not registered on this subscription).')
@minValue(2)
param poolSizeInTib int = 2

@description('Volume size in GiB (minimum 100 GiB).')
@minValue(100)
param volumeSizeInGib int = 100

// 1 TiB = 1099511627776 bytes; 1 GiB = 1073741824 bytes
var poolSizeInBytes = int(poolSizeInTib) * 1099511627776
var volumeSizeInBytes = int(volumeSizeInGib) * 1073741824

resource anfAccount 'Microsoft.NetApp/netAppAccounts@2023-07-01' = {
  name: '${prefix}-anf'
  location: location
  tags: {
    purpose: 'anf-attestation-demo'
  }
}

resource capacityPool 'Microsoft.NetApp/netAppAccounts/capacityPools@2023-07-01' = {
  parent: anfAccount
  name: '${prefix}-pool'
  location: location
  properties: {
    serviceLevel: serviceLevel
    size: poolSizeInBytes
    qosType: 'Auto'
  }
}

resource volume 'Microsoft.NetApp/netAppAccounts/capacityPools/volumes@2023-07-01' = {
  parent: capacityPool
  name: '${prefix}-volume'
  location: location
  properties: {
    creationToken: '${prefix}-volume'   // NFS export path segment
    usageThreshold: volumeSizeInBytes
    subnetId: anfSubnetId
    protocolTypes: ['NFSv3']
    securityStyle: 'Unix'
    // World-writable so the Windows NFSv3 client (which mounts anonymously as
    // "nobody") can write during the robocopy migration.
    unixPermissions: '0777'
    snapshotDirectoryVisible: false
    kerberosEnabled: false
    exportPolicy: {
      rules: [
        {
          ruleIndex: 1
          unixReadOnly: false
          unixReadWrite: true
          cifs: false
          nfsv3: true
          nfsv41: false
          allowedClients: allowedCidr
          kerberos5ReadOnly: false
          kerberos5ReadWrite: false
          kerberos5iReadOnly: false
          kerberos5iReadWrite: false
          kerberos5pReadOnly: false
          kerberos5pReadWrite: false
          hasRootAccess: true
        }
      ]
    }
    networkFeatures: 'Standard'
    // Optional: enable cross-region replication for extra resilience
    // dataProtection: { replication: { ... } }
  }
}

output anfAccountName string = anfAccount.name
output anfAccountId string = anfAccount.id
output anfPoolName string = capacityPool.name
output anfVolumeName string = volume.name
output anfVolumeId string = volume.id
// mountTargets is populated by the platform after provisioning completes.
output mountTargetIpAddress string = volume.properties.mountTargets[0].ipAddress
// NFSv4.1 export path is the volume's creation token; there is no SMB FQDN.
output nfsMountPath string = '/${volume.properties.creationToken}'
