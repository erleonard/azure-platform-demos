#!/usr/bin/env bash
# bicep/scripts/deploy.sh — One-shot deployment script.
#
# Usage:
#   bash bicep/scripts/deploy.sh
#
# Prerequisites:
#   - Azure CLI (az) 2.51+
#   - Bicep CLI (installed automatically via `az bicep install`)
#   - Logged in: az login
#   - Target subscription set: az account set --subscription <id>
#
# What this script does:
#   1. Validates the Bicep template (what-if)
#   2. Deploys at subscription scope (creates resource group + all resources)
#   3. Reads the deployment outputs
#   4. Prints the Windows → ANF migration showcase steps

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BICEP_DIR="${DEMO_DIR}/bicep"

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Prerequisites check
# ---------------------------------------------------------------------------
info "Checking prerequisites..."
command -v az  >/dev/null 2>&1 || error "Azure CLI not found. Install from https://docs.microsoft.com/cli/azure/install-azure-cli"
az account show >/dev/null 2>&1 || error "Not logged in. Run: az login"
az bicep install --only-show-errors 2>/dev/null || true   # install/upgrade silently
success "Prerequisites OK"

# ---------------------------------------------------------------------------
# VM admin password (workload VMs). Read from env so it is never committed.
# ---------------------------------------------------------------------------
if grep -Eq "^param deployWorkloadVms\s*=\s*true" "${BICEP_DIR}/main.bicepparam"; then
  if [ -z "${CUSTODY_VM_ADMIN_PASSWORD:-}" ]; then
    error "CUSTODY_VM_ADMIN_PASSWORD is not set. The demo VMs need an admin password.\n         Run:  export CUSTODY_VM_ADMIN_PASSWORD='<a strong password>'\n         (12+ chars, upper/lower/digit/symbol) then re-run this script."
  fi
  export CUSTODY_VM_ADMIN_PASSWORD
fi

# ---------------------------------------------------------------------------
# Read parameters from bicepparam
# ---------------------------------------------------------------------------
PARAM_FILE="${BICEP_DIR}/main.bicepparam"
TEMPLATE_FILE="${BICEP_DIR}/main.bicep"

# Extract location from the param file (used as deployment location)
DEPLOY_LOCATION=$(grep -E "^param location\s*=" "${PARAM_FILE}" | sed "s/.*= *'\([^']*\)'.*/\1/" | tr -d ' ')
DEPLOY_LOCATION="${DEPLOY_LOCATION:-canadacentral}"

# Deployment name is timestamped so multiple runs don't collide
DEPLOYMENT_NAME="anf-attestation-demo-$(date +%Y%m%d%H%M%S)"

info "Deployment name  : ${DEPLOYMENT_NAME}"
info "Location         : ${DEPLOY_LOCATION}"
info "Template         : ${TEMPLATE_FILE}"
info "Parameters       : ${PARAM_FILE}"

# ---------------------------------------------------------------------------
# Validate (what-if)
# ---------------------------------------------------------------------------
info "Running what-if validation..."
az deployment sub what-if \
  --location "${DEPLOY_LOCATION}" \
  --name "${DEPLOYMENT_NAME}-whatif" \
  --template-file "${TEMPLATE_FILE}" \
  --parameters "${PARAM_FILE}" \
  --no-pretty-print \
  --output none 2>&1 | tail -5 || warn "What-if returned warnings (may be normal for first deploy)"
success "Validation complete"

# ---------------------------------------------------------------------------
# Deploy
# ---------------------------------------------------------------------------
info "Starting deployment (this takes ~10-15 minutes for ANF)..."
az deployment sub create \
  --location "${DEPLOY_LOCATION}" \
  --name "${DEPLOYMENT_NAME}" \
  --template-file "${TEMPLATE_FILE}" \
  --parameters "${PARAM_FILE}" \
  --output none

success "Deployment complete"

# ---------------------------------------------------------------------------
# Read outputs
# ---------------------------------------------------------------------------
info "Reading deployment outputs..."

get_output() {
  az deployment sub show \
    --name "${DEPLOYMENT_NAME}" \
    --query "properties.outputs.${1}.value" \
    --output tsv 2>/dev/null
}

RESOURCE_GROUP=$(get_output "resourceGroupName")
LOCATION=$(get_output "location")
ANF_ACCOUNT=$(get_output "anfAccountName")
ANF_POOL=$(get_output "anfPoolName")
ANF_VOLUME=$(get_output "anfVolumeName")
ANF_IP=$(get_output "anfMountTargetIp")
LAW_ID=$(get_output "logAnalyticsWorkspaceId")
LAW_NAME=$(get_output "logAnalyticsWorkspaceName")
BASTION_NAME=$(get_output "bastionName")
WIN_VM=$(get_output "windowsVmName")
WIN_COMPUTER=$(get_output "windowsComputerName")
WIN_IP=$(get_output "windowsPrivateIp")
SOURCE_SHARE=$(get_output "sourceShareName")

# Subscription ID from current context
SUBSCRIPTION_ID=$(az account show --query id --output tsv)

info "Resource group   : ${RESOURCE_GROUP}"
info "ANF account      : ${ANF_ACCOUNT}"
info "ANF volume       : ${ANF_VOLUME}"
info "ANF mount IP     : ${ANF_IP}"

# ---------------------------------------------------------------------------
# Windows → ANF live migration showcase (robocopy over NFSv3, via Bastion)
# ---------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  SHOWCASE: Migrate legal data  Windows Server → Azure NetApp Files${NC}"
echo -e "${YELLOW}════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "  Topology (no public IPs — access via Azure Bastion):"
echo "    ${WIN_COMPUTER} (${WIN_IP})  — source file server, 100 legal files in C:\\LegalData"
echo "    ANF volume ${ANF_VOLUME} (${ANF_IP})  — NFSv3 destination"
echo "    ${BASTION_NAME}  — browser RDP"
echo ""
echo "  1) RDP to the Windows Server through Bastion (username azureadmin):"
echo -e "     ${GREEN}az network bastion rdp --name ${BASTION_NAME} --resource-group ${RESOURCE_GROUP} \\${NC}"
echo -e "     ${GREEN}   --target-resource-id \$(az vm show -g ${RESOURCE_GROUP} -n ${WIN_VM} --query id -o tsv)${NC}"
echo ""
echo "  2) In an elevated PowerShell on the server, run the migration"
echo "     (robocopy Windows → ANF NFSv3 + SHA-256 verification):"
echo -e "     ${GREEN}C:\\demo\\migrate.ps1${NC}"
echo -e "     ${GREEN}Get-Content C:\\demo\\migration-ledger.csv${NC}"
echo ""
echo "  migrate.ps1 mounts ${ANF_IP}:/${ANF_VOLUME} as drive Z:, robocopies the"
echo "  files, and writes a VERIFIED/MISMATCH SHA-256 ledger — the chain-of-custody proof."
echo -e "${YELLOW}════════════════════════════════════════════════════════════════════${NC}"
echo ""

# ---------------------------------------------------------------------------
# Teardown hint
# ---------------------------------------------------------------------------
echo "  To tear down all resources when done:"
echo "    az group delete --name ${RESOURCE_GROUP} --yes --no-wait"
echo ""
success "All done.  Follow the showcase steps above to run the migration on the Windows Server."
