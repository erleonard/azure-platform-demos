// main.bicepparam — Parameter file for the chain-of-custody demo.
//
// Edit the values below, then run:
//   bash bicep/scripts/deploy.sh

using './main.bicep'

// ── Optional (safe defaults) ─────────────────────────────────────────────────

// Short prefix applied to every resource name (2-8 alphanumeric chars).
param prefix = 'attestation'

// Azure region — choose one where ANF is available.
// https://azure.microsoft.com/en-us/explore/global-infrastructure/products-by-region/?products=netapp
param location = 'canadacentral'

// Networking
param vnetAddressPrefix = '10.0.0.0/16'
param anfSubnetPrefix   = '10.0.1.0/24'

// ANF capacity pool (minimum 2 TiB; Standard is cheapest)
param anfServiceLevel  = 'Standard'
param anfPoolSizeInTib = 2

// ANF volume size in GiB (minimum 100 GiB)
param anfVolumeSizeInGib = 100

// ── Workload VMs (Windows source file server + Linux migrator + Bastion) ──────

// Set false to deploy only the storage/network backbone (no VMs/Bastion).
param deployWorkloadVms = true

// Local admin username for the demo VMs.
param adminUsername = 'azureadmin'

// Local admin password — read from an environment variable so the secret is
// never committed. Before deploying:
//   export CUSTODY_VM_ADMIN_PASSWORD='<a strong password>'
param adminPassword = readEnvironmentVariable('CUSTODY_VM_ADMIN_PASSWORD', '')

// VM size (Gen2-capable). Fallbacks if capacity-constrained: Standard_D2as_v5, Standard_B2ms.
param vmSize = 'Standard_D2s_v5'
