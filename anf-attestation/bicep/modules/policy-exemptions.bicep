// modules/policy-exemptions.bicep — Resource-group-scoped SLZ policy waivers.
//
// The SLZ "Enable-DDoS-VNET" (Modify) policy, assigned at the `landingzones`
// management group, appends a DDoS protection plan reference to every VNet on
// create. The platform was deployed with ddos_protection_plan_enabled = false,
// so that plan does not exist and the VNet PUT fails with a 404 NotFound for
// the phantom plan. This narrow waiver, scoped to the demo resource group,
// lets the VNet deploy. It is torn down with the resource group.
//
// Requires Owner (or Resource Policy Contributor) on the resource group to
// create policy exemptions.

@description('Resource ID of the Enable-DDoS-VNET (Modify) policy assignment to waive on this resource group.')
param ddosPolicyAssignmentId string = '/providers/Microsoft.Management/managementGroups/landingzones/providers/Microsoft.Authorization/policyAssignments/Enable-DDoS-VNET'

resource ddosExemption 'Microsoft.Authorization/policyExemptions@2022-07-01-preview' = {
  name: 'exempt-ddos-modify'
  properties: {
    policyAssignmentId: ddosPolicyAssignmentId
    exemptionCategory: 'Waiver'
    displayName: 'Waive DDoS Modify effect (SLZ DDoS plan not deployed)'
    description: 'SLZ DDoS plan not deployed (ddos_protection_plan_enabled=false); waive the DDoS Modify effect for this demo resource group.'
  }
}

output exemptionId string = ddosExemption.id
