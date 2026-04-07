@description('Name of the environment')
param environmentName string

@description('Azure region')
param location string

@description('Tags for all resources')
param tags object = {}

@description('SKU — Basic for dev, Standard for prod')
param skuName string = 'Basic'

// ACR names must be globally unique, alphanumeric only
var registryName = 'crcntrl${environmentName}'

// =============================================================================
// Azure Container Registry
// =============================================================================
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: registryName
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  properties: {
    adminUserEnabled: true
  }
}

// =============================================================================
// Outputs
// =============================================================================
output registryName string = containerRegistry.name
output registryLoginServer string = containerRegistry.properties.loginServer
output registryUsername string = containerRegistry.listCredentials().username
output registryPassword string = containerRegistry.listCredentials().passwords[0].value
