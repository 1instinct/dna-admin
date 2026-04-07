@description('Name of the environment')
param environmentName string

@description('Azure region')
param location string

@description('Tags for all resources')
param tags object = {}

@description('Subnet ID for VNET integration')
param subnetId string

@description('Private DNS Zone ID for PostgreSQL')
param privateDnsZoneId string

@description('PostgreSQL administrator login')
param administratorLogin string = 'cntrldbadmin'

@secure()
@description('PostgreSQL administrator password')
param administratorPassword string

@description('SKU name — Burstable B1ms for dev, GP D2s_v3 for prod')
param skuName string = 'Standard_B1ms'

@description('SKU tier — Burstable for dev, GeneralPurpose for prod')
param skuTier string = 'Burstable'

@description('Storage size in GB')
param storageSizeGB int = 32

@description('Backup retention in days')
param backupRetentionDays int = 7

@description('Enable high availability (prod only)')
param highAvailability bool = false

var serverName = 'psql-cntrl-${environmentName}'
var databaseName = 'cntrl_${environmentName}'

// =============================================================================
// PostgreSQL Flexible Server
// =============================================================================
resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-06-01-preview' = {
  name: serverName
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: {
    version: '16'
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorPassword
    storage: {
      storageSizeGB: storageSizeGB
      autoGrow: 'Enabled'
    }
    backup: {
      backupRetentionDays: backupRetentionDays
      geoRedundantBackup: 'Disabled'
    }
    network: {
      delegatedSubnetResourceId: subnetId
      privateDnsZoneArmResourceId: privateDnsZoneId
    }
    highAvailability: {
      mode: highAvailability ? 'ZoneRedundant' : 'Disabled'
    }
  }
}

// =============================================================================
// Database
// =============================================================================
resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-06-01-preview' = {
  parent: postgresServer
  name: databaseName
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

// =============================================================================
// Server Configuration — tune for Rails
// =============================================================================
resource maxConnections 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2023-06-01-preview' = {
  parent: postgresServer
  name: 'max_connections'
  properties: {
    value: '100'
    source: 'user-override'
  }
}

resource logMinDuration 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2023-06-01-preview' = {
  parent: postgresServer
  name: 'log_min_duration_statement'
  properties: {
    value: '1000'
    source: 'user-override'
  }
}

// =============================================================================
// Outputs
// =============================================================================
output serverName string = postgresServer.name
output serverFqdn string = postgresServer.properties.fullyQualifiedDomainName
output databaseName string = database.name
output connectionString string = 'postgresql://${administratorLogin}:PASSWORD@${postgresServer.properties.fullyQualifiedDomainName}:5432/${databaseName}?sslmode=require'
