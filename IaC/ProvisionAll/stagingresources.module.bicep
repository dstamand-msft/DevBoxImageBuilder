@description('The resource ID of the user assigned identity for the image builder')
param userImgBuilderIdentityIdResourceId string

@description('The principal ID of the user assigned identity for the image builder')
param userImgBuilderIdentityPrincipalId string

@description('The resource ID of the virtual machine assigned identity for the image builder')
param vmImgBuilderIdentityResourceId string

var rbacRoles = loadJsonContent('../rbacRoleIds.json')

resource userImgBuilderIdentityStagingResourceGroupRBAC 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(userImgBuilderIdentityIdResourceId, vmImgBuilderIdentityResourceId, 'Owner')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', rbacRoles.owner)
    principalId: userImgBuilderIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}
