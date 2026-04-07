// =============================================================================
// Cntrl+ DNA Fork — Main Infrastructure Orchestrator
// Deploys all Azure resources for the Cntrl+ platform.
// Usage:
//   az deployment group create -g rg-cntrl-dev -f main.bicep -p @parameters/dev.json
// =============================================================================

targetScope = 'resourceGroup'

@minLength(1)
@maxLength(10)
@description('Environment name (dev, prod)')
param environmentName string

@description('Azure region for all resources')
param location string = resourceGroup().location

// PostgreSQL
@secure()
@description('PostgreSQL administrator password')
param postgresAdminPassword string

// Key Vault secrets
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

// Configuration
param mdiApiBase string = 'https://api.mdintegrations.com/v1'
param honeybeeApiBase string = 'https://partners.honeybeehealth.com'
param honeybeeAuthBase string = 'https://auth.sandbox.honeybeehealth.com'
param publicApiUrl string
param publicSiteUrl string
param sentryDsn string = ''

// SKU overrides (dev vs prod)
param postgresSkuName string = 'Standard_B1ms'
param postgresSkuTier string = 'Burstable'
param postgresStorageGB int = 32
param postgresBackupRetention int = 7
param postgresHighAvailability bool = false
param redisSkuName string = 'Basic'
param redisSkuCapacity int = 0
param registrySkuName string = 'Basic'

// Image tags (overridden by CI/CD)
param adminImageTag string = 'latest'
param frontendImageTag string = 'latest'

var tags = {
  project: 'cntrl-plus'
  environment: environmentName
  managedBy: 'bicep'
}

// =============================================================================
// Module: Network
// =============================================================================
module network 'modules/network.bicep' = {
  name: 'network-${environmentName}'
  params: {
    environmentName: environmentName
    location: location
    tags: tags
  }
}

// =============================================================================
// Module: Monitoring (deploy early — other modules reference outputs)
// =============================================================================
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring-${environmentName}'
  params: {
    environmentName: environmentName
    location: location
    tags: tags
  }
}

// =============================================================================
// Module: Container Registry
// =============================================================================
module registry 'modules/registry.bicep' = {
  name: 'registry-${environmentName}'
  params: {
    environmentName: environmentName
    location: location
    tags: tags
    skuName: registrySkuName
  }
}

// =============================================================================
// Module: PostgreSQL
// =============================================================================
module postgres 'modules/postgres.bicep' = {
  name: 'postgres-${environmentName}'
  params: {
    environmentName: environmentName
    location: location
    tags: tags
    subnetId: network.outputs.postgresSubnetId
    privateDnsZoneId: network.outputs.postgresDnsZoneId
    administratorPassword: postgresAdminPassword
    skuName: postgresSkuName
    skuTier: postgresSkuTier
    storageSizeGB: postgresStorageGB
    backupRetentionDays: postgresBackupRetention
    highAvailability: postgresHighAvailability
  }
}

// =============================================================================
// Module: Redis
// =============================================================================
module redis 'modules/redis.bicep' = {
  name: 'redis-${environmentName}'
  params: {
    environmentName: environmentName
    location: location
    tags: tags
    privateEndpointSubnetId: network.outputs.privateEndpointsSubnetId
    privateDnsZoneId: network.outputs.redisDnsZoneId
    skuName: redisSkuName
    skuCapacity: redisSkuCapacity
  }
}

// =============================================================================
// Module: Container Apps
// =============================================================================
module containerApps 'modules/container-apps.bicep' = {
  name: 'container-apps-${environmentName}'
  params: {
    environmentName: environmentName
    location: location
    tags: tags
    containerAppsSubnetId: network.outputs.containerAppsSubnetId
    logAnalyticsCustomerId: monitoring.outputs.logAnalyticsCustomerId
    logAnalyticsSharedKey: monitoring.outputs.logAnalyticsSharedKey
    registryLoginServer: registry.outputs.registryLoginServer
    registryUsername: registry.outputs.registryUsername
    registryPassword: registry.outputs.registryPassword
    keyVaultUri: keyvault.outputs.vaultUri
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    appInsightsInstrumentationKey: monitoring.outputs.appInsightsInstrumentationKey
    adminImageTag: adminImageTag
    frontendImageTag: frontendImageTag
    mdiApiBase: mdiApiBase
    honeybeeApiBase: honeybeeApiBase
    honeybeeAuthBase: honeybeeAuthBase
    publicApiUrl: publicApiUrl
    publicSiteUrl: publicSiteUrl
    sentryDsn: sentryDsn
  }
}

// =============================================================================
// Module: Key Vault (needs principal IDs from Container Apps)
// Note: This creates a circular dependency with container-apps.bicep because
// Container Apps need the Key Vault URI, and Key Vault needs the principal IDs.
// Resolution: Deploy Key Vault first with empty RBAC, then update after
// Container Apps are created. The CI/CD pipeline handles this in two steps.
// For initial deployment, we pass empty principalIds and add RBAC after.
// =============================================================================
module keyvault 'modules/keyvault.bicep' = {
  name: 'keyvault-${environmentName}'
  params: {
    environmentName: environmentName
    location: location
    tags: tags
    tenantId: subscription().tenantId
    databaseUrl: 'postgresql://cntrldbadmin:${postgresAdminPassword}@${postgres.outputs.serverFqdn}:5432/${postgres.outputs.databaseName}?sslmode=require'
    redisUrl: redis.outputs.redisUrl
    railsMasterKey: railsMasterKey
    secretKeyBase: secretKeyBase
    deviseSecretKey: deviseSecretKey
    mdiClientId: mdiClientId
    mdiClientSecret: mdiClientSecret
    mdiWebhookSecret: mdiWebhookSecret
    honeybeeClientId: honeybeeClientId
    honeybeeSecretKey: honeybeeSecretKey
    honeybeeWebhookSecret: honeybeeWebhookSecret
    stripeSecretKey: stripeSecretKey
    stripePublishableKey: stripePublishableKey
    secretReaderPrincipalIds: [
      containerApps.outputs.adminAppPrincipalId
      containerApps.outputs.sidekiqAppPrincipalId
      containerApps.outputs.migrateJobPrincipalId
    ]
  }
}

// =============================================================================
// Outputs
// =============================================================================
output AZURE_CONTAINER_REGISTRY string = registry.outputs.registryLoginServer
output AZURE_CONTAINER_REGISTRY_NAME string = registry.outputs.registryName
output ADMIN_APP_NAME string = containerApps.outputs.adminAppName
output ADMIN_APP_URL string = 'https://${containerApps.outputs.adminAppFqdn}'
output FRONTEND_APP_NAME string = containerApps.outputs.frontendAppName
output FRONTEND_APP_URL string = 'https://${containerApps.outputs.frontendAppFqdn}'
output SIDEKIQ_APP_NAME string = containerApps.outputs.sidekiqAppName
output MIGRATE_JOB_NAME string = containerApps.outputs.migrateJobName
output POSTGRES_SERVER string = postgres.outputs.serverFqdn
output REDIS_HOST string = redis.outputs.cacheHostName
output KEY_VAULT_NAME string = keyvault.outputs.vaultName
output APP_INSIGHTS_NAME string = monitoring.outputs.appInsightsName
