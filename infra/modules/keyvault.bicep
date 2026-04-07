@description('Name of the environment')
param environmentName string

@description('Azure region')
param location string

@description('Tags for all resources')
param tags object = {}

@description('Tenant ID for Key Vault')
param tenantId string

@description('Principal IDs that should have secret read access (managed identities)')
param secretReaderPrincipalIds array = []

// Secrets to store
@secure()
param databaseUrl string

@secure()
param redisUrl string

@secure()
param railsMasterKey string

@secure()
param secretKeyBase string

@secure()
param deviseSecretKey string

@secure()
param mdiClientId string

@secure()
param mdiClientSecret string

@secure()
param mdiWebhookSecret string = ''

@secure()
param honeybeeClientId string

@secure()
param honeybeeSecretKey string

@secure()
param honeybeeWebhookSecret string

@secure()
param stripeSecretKey string

@secure()
param stripePublishableKey string

var vaultName = 'kv-cntrl-${environmentName}'

// =============================================================================
// Key Vault
// =============================================================================
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: vaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: false
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// =============================================================================
// Secrets
// =============================================================================
resource secretDatabaseUrl 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'DATABASE-URL'
  properties: { value: databaseUrl }
}

resource secretRedisUrl 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'REDIS-URL'
  properties: { value: redisUrl }
}

resource secretRailsMasterKey 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'RAILS-MASTER-KEY'
  properties: { value: railsMasterKey }
}

resource secretSecretKeyBase 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'SECRET-KEY-BASE'
  properties: { value: secretKeyBase }
}

resource secretDeviseSecretKey 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'DEVISE-SECRET-KEY'
  properties: { value: deviseSecretKey }
}

resource secretMdiClientId 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'MDI-CLIENT-ID'
  properties: { value: mdiClientId }
}

resource secretMdiClientSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'MDI-CLIENT-SECRET'
  properties: { value: mdiClientSecret }
}

resource secretMdiWebhookSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'MDI-WEBHOOK-SECRET'
  properties: { value: mdiWebhookSecret }
}

resource secretHoneybeeClientId 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'HONEYBEE-CLIENT-ID'
  properties: { value: honeybeeClientId }
}

resource secretHoneybeeSecretKey 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'HONEYBEE-SECRET-KEY'
  properties: { value: honeybeeSecretKey }
}

resource secretHoneybeeWebhookSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'HONEYBEE-WEBHOOK-SECRET'
  properties: { value: honeybeeWebhookSecret }
}

resource secretStripeSecretKey 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'STRIPE-SECRET-KEY'
  properties: { value: stripeSecretKey }
}

resource secretStripePublishableKey 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'STRIPE-PUBLISHABLE-KEY'
  properties: { value: stripePublishableKey }
}

// =============================================================================
// RBAC — Key Vault Secrets User role for managed identities
// =============================================================================
// Role definition ID for "Key Vault Secrets User"
var keyVaultSecretsUserRole = '4633458b-17de-408a-b874-0445c86b69e6'

resource roleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for principalId in secretReaderPrincipalIds: {
  name: guid(keyVault.id, principalId, keyVaultSecretsUserRole)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRole)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}]

// =============================================================================
// Outputs
// =============================================================================
output vaultName string = keyVault.name
output vaultUri string = keyVault.properties.vaultUri
output vaultId string = keyVault.id
