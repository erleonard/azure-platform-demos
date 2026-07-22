// modules/windows-server.bicep — Windows Server 2019 source file server.
//
// Represents the on-premises "CORP-FS01" file server holding legal data.
// A Custom Script Extension seeds 100 files of varied sizes and types into
// C:\LegalData and exposes it as the SMB share \\<vm>\LegalData. The
// intermediate Linux VM mounts this share (CIFS) and migrates the data to
// Azure NetApp Files.
//
// The VM has NO public IP — access is via Azure Bastion only.

@description('Short prefix for resource names.')
param prefix string

@description('Azure region.')
param location string

@description('Resource ID of the subnet to place the VM NIC in.')
param subnetId string

@description('Local administrator username.')
param adminUsername string

@description('Local administrator password.')
@secure()
param adminPassword string

@description('VM size (D-series v5 requires a Gen2 image).')
param vmSize string = 'Standard_D2s_v5'

@description('Windows Server image SKU (Gen2).')
param windowsSku string = '2019-datacenter-gensecond'

@description('NetBIOS computer name for the file server.')
@maxLength(15)
param computerName string = 'CORP-FS01'

@description('ANF mount target IP address (NFSv3).')
param anfMountIp string

@description('ANF volume name (NFS export path segment).')
param anfVolumeName string

// migrate.ps1 — robocopy the legal files to the ANF NFSv3 volume, verify each
// with SHA-256, AND capture the Windows NTFS metadata (owner, ACL SDDL, DOS
// attributes, timestamps) into the custody ledger. NFSv3 can't hold NTFS ACLs,
// so the metadata is preserved as signed *evidence* in the manifest rather than
// on the destination filesystem. Header (single-quoted, interpolated) injects
// the ANF IP and volume; body (triple-quoted, literal) holds the PowerShell so
// its braces and quotes need no escaping. The script is base64-encoded and
// written to disk by the Custom Script Extension.
var migrateHeader = '$anfIp = "${anfMountIp}"\n$anfVol = "${anfVolumeName}"\n$src = "C:\\LegalData"\n$drive = "Z:"\n'
var migrateBody = '''# Robocopy migration: Windows source -> Azure NetApp Files (NFSv3).
# Verifies content with SHA-256 and captures NTFS metadata as custody evidence.
$ErrorActionPreference = "Stop"
if (-not (Get-WindowsFeature NFS-Client).Installed) { Install-WindowsFeature NFS-Client | Out-Null }
# A freshly installed Client for NFS leaves its service stopped; start it so `mount` works.
Get-Service NfsClnt -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne "Running" } | Start-Service -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path C:\demo | Out-Null
Write-Host "Mounting ANF ${anfIp}:/${anfVol} on $drive ..."
cmd /c "mount -o anon ${anfIp}:/${anfVol} $drive" | Write-Host
if (-not [System.IO.Directory]::Exists("$drive\")) {
  throw "ANF mount to $drive failed. If the NFS client was just installed, reboot the VM once, then re-run this script. (mount -o anon ${anfIp}:/${anfVol} $drive)"
}
Write-Host "Copying with robocopy (data + timestamps) ..."
$destDir = "$drive\LegalData"
[System.IO.Directory]::CreateDirectory($destDir) | Out-Null
robocopy $src $destDir /E /COPY:DAT /DCOPY:DAT /R:2 /W:2 /NP | Out-Null
$csv = "C:\demo\migration-ledger.csv"
$json = "C:\demo\migration-manifest.json"
# Enumerate + hash the destination via .NET IO. The Windows PowerShell 5.1
# FileSystem provider (Get-ChildItem / Get-FileHash / Test-Path) throws
# NotSupportedException ("the given path's format is not supported") on NFS-mapped
# drives; the .NET APIs work directly at the Win32 layer.
function Get-Sha256([string]$path) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $fs = [System.IO.File]::OpenRead($path)
    try { return ([System.BitConverter]::ToString($sha.ComputeHash($fs))).Replace("-", "") }
    finally { $fs.Dispose() }
  } finally { $sha.Dispose() }
}
$destMap = @{}
foreach ($p in [System.IO.Directory]::GetFiles($destDir)) { $destMap[[System.IO.Path]::GetFileName($p)] = $p }
if ($destMap.Count -eq 0) { Write-Warning "No files found in $destDir - the ANF mount or robocopy failed." }
$verified = 0; $mismatch = 0
$rows = @()
Get-ChildItem -File $src | ForEach-Object {
  $acl = Get-Acl $_.FullName
  $hs = Get-Sha256 $_.FullName
  if ($destMap.ContainsKey($_.Name)) { $hd = Get-Sha256 $destMap[$_.Name] } else { $hd = "MISSING" }
  if ($hs -eq $hd) { $st = "VERIFIED"; $verified++ } else { $st = "MISMATCH"; $mismatch++ }
  $rows += [pscustomobject]@{
    file          = $_.Name
    size_bytes    = $_.Length
    owner         = $acl.Owner
    acl_sddl      = $acl.Sddl
    attributes    = $_.Attributes.ToString()
    created_utc   = $_.CreationTimeUtc.ToString("o")
    modified_utc  = $_.LastWriteTimeUtc.ToString("o")
    sha256_source = $hs
    sha256_dest   = $hd
    status        = $st
  }
  Write-Host "[$st] $($_.Name)  owner=$($acl.Owner)"
}
# Export-Csv quotes/escapes fields (SDDL, owner) safely; JSON is the richer manifest.
$rows | Export-Csv -NoTypeInformation -Encoding utf8 $csv
$rows | ConvertTo-Json -Depth 3 | Out-File -Encoding utf8 $json
Write-Host "Done. Verified=$verified Mismatch=$mismatch"
Write-Host "Ledger:   $csv"
Write-Host "Manifest: $json  (NTFS owner/ACL/timestamps captured as evidence)"
'''
var migrateScriptB64 = base64(concat(migrateHeader, migrateBody))

// Inline PowerShell (run via Custom Script Extension) that: seeds 100 legal
// files of random size (8 KiB-4 MiB) across 10 file types; shares the folder
// over SMB; installs the NFS client; and drops C:\demo\migrate.ps1.
var seedCommand = 'powershell -ExecutionPolicy Unrestricted -NoProfile -Command "New-Item -ItemType Directory -Force -Path C:\\LegalData,C:\\demo | Out-Null; $e=@(\'pdf\',\'docx\',\'xlsx\',\'txt\',\'csv\',\'zip\',\'pptx\',\'eml\',\'tif\',\'rtf\'); for($i=1;$i -le 100;$i++){$x=$e[$i%$e.Length]; $kb=Get-Random -Minimum 8 -Maximum 4096; $b=New-Object byte[] ($kb*1024); (New-Object Random).NextBytes($b); [IO.File]::WriteAllBytes((\'C:\\LegalData\\legal_{0:D3}.{1}\' -f $i,$x),$b)}; New-SmbShare -Name LegalData -Path C:\\LegalData -FullAccess Everyone -ErrorAction SilentlyContinue; Install-WindowsFeature -Name NFS-Client -ErrorAction SilentlyContinue | Out-Null; [IO.File]::WriteAllText(\'C:\\demo\\migrate.ps1\',[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(\'${migrateScriptB64}\')))"'

resource nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: '${prefix}-fs01-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetId
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
  tags: {
    purpose: 'anf-attestation-demo'
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: '${prefix}-fs01'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: computerName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: windowsSku
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
  }
  tags: {
    purpose: 'anf-attestation-demo'
    role: 'source-file-server'
  }
}

resource seed 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  parent: vm
  name: 'seed-legal-data'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    protectedSettings: {
      commandToExecute: seedCommand
    }
  }
}

output vmName string = vm.name
output computerName string = computerName
output privateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
output shareName string = 'LegalData'
