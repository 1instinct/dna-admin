@description('Name of the environment')
param environmentName string

@description('Azure region')
param location string

@description('Tags for all resources')
param tags object = {}

@description('Subnet ID for Container Apps Environment')
param containerAppsSubnetId string

@description('Log Analytics workspace customer ID')
param logAnalyticsCustomerId string

@secure()
@description('Log Analytics workspace shared key')
param logAnalyticsSharedKey string

@description('Container registry login server')
param registryLoginServer string

@description('Container registry username')
param registryUsername string

@secure()
@description('Container registry password')
param registryPassword string

@description('Key Vault URI')
param keyVaultUri string

@description('Application Insights connection string')
param appInsightsConnectionString string

// Image tags — overridden by CI/CD
@description('Admin (Rails) image tag')
param adminImageTag string = 'latest'

@description('Frontend (Next.js) image tag')
param frontendImageTag string = 'latest'

// API URLs for frontend
@description('MDI API base URL')
param mdiApiBase string = 'https://api.mdintegrations.com/v1'

@description('Honeybee API base URL')
param honeybeeApiBase string = 'https://partners.honeybeehealth.com'

@description('Honeybee Auth base URL')
param honeybeeAuthBase string = 'https://auth.sandbox.honeybeehealth.com'

@description('Public API URL for frontend')
param publicApiUrl string

@description('Public site URL')
param publicSiteUrl string

@description('Sentry DSN')
param sentryDsn string = ''

@description('Application Insights instrumentation key')
param appInsightsInstrumentationKey string = ''

var adminImage = '${registryLoginServer}/cntrl-admin:${adminImageTag}'
var frontendImage = '${registryLoginServer}/cntrl-frontend:${frontendImageTag}'

// =============================================================================
// Container Apps Environment (with VNET integration)
// =============================================================================
resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: 'cae-cntrl-${environmentName}'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsCustomerId
        sharedKey: logAnalyticsSharedKey
      }
    }
    vnetConfiguration: {
      infrastructureSubnetId: containerAppsSubnetId
      internal: false
    }
  }
}

// =============================================================================
// Shared secrets (used by admin + sidekiq)
// =============================================================================
var registrySecrets = [
  { name: 'registry-password', value: registryPassword }
]

var registryConfig = [
  {
    server: registryLoginServer
    username: registryUsername
    passwordSecretRef: 'registry-password'
  }
]

// Env vars that reference Key Vault secrets (Container Apps pull from KV via identity)
// For Container Apps, secrets must be defined at the app level.
// Key Vault references use the format: secretRef pointing to a Container App secret
// that is populated from Key Vault.

// =============================================================================
// cntrl-admin (Rails + Puma)
// =============================================================================
resource adminApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'ca-admin-${environmentName}'
  location: location
  tags: union(tags, { 'azd-service-name': 'admin' })
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 3000
        transport: 'http'
        allowInsecure: false
        customDomains: []
      }
      registries: registryConfig
      secrets: union(registrySecrets, [
        { name: 'database-url', keyVaultUrl: '${keyVaultUri}secrets/DATABASE-URL', identity: 'system' }
        { name: 'redis-url', keyVaultUrl: '${keyVaultUri}secrets/REDIS-URL', identity: 'system' }
        { name: 'rails-master-key', keyVaultUrl: '${keyVaultUri}secrets/RAILS-MASTER-KEY', identity: 'system' }
        { name: 'secret-key-base', keyVaultUrl: '${keyVaultUri}secrets/SECRET-KEY-BASE', identity: 'system' }
        { name: 'devise-secret-key', keyVaultUrl: '${keyVaultUri}secrets/DEVISE-SECRET-KEY', identity: 'system' }
        { name: 'mdi-client-id', keyVaultUrl: '${keyVaultUri}secrets/MDI-CLIENT-ID', identity: 'system' }
        { name: 'mdi-client-secret', keyVaultUrl: '${keyVaultUri}secrets/MDI-CLIENT-SECRET', identity: 'system' }
        { name: 'mdi-webhook-secret', keyVaultUrl: '${keyVaultUri}secrets/MDI-WEBHOOK-SECRET', identity: 'system' }
        { name: 'honeybee-client-id', keyVaultUrl: '${keyVaultUri}secrets/HONEYBEE-CLIENT-ID', identity: 'system' }
        { name: 'honeybee-secret-key', keyVaultUrl: '${keyVaultUri}secrets/HONEYBEE-SECRET-KEY', identity: 'system' }
        { name: 'honeybee-webhook-secret', keyVaultUrl: '${keyVaultUri}secrets/HONEYBEE-WEBHOOK-SECRET', identity: 'system' }
        { name: 'stripe-secret-key', keyVaultUrl: '${keyVaultUri}secrets/STRIPE-SECRET-KEY', identity: 'system' }
        { name: 'stripe-publishable-key', keyVaultUrl: '${keyVaultUri}secrets/STRIPE-PUBLISHABLE-KEY', identity: 'system' }
      ])
    }
    template: {
      containers: [
        {
          name: 'cntrl-admin'
          image: adminImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            { name: 'RAILS_ENV', value: 'production' }
            { name: 'RAILS_LOG_TO_STDOUT', value: 'true' }
            { name: 'RAILS_SERVE_STATIC_FILES', value: 'true' }
            { name: 'PORT', value: '3000' }
            { name: 'WEB_CONCURRENCY', value: '2' }
            { name: 'RAILS_MAX_THREADS', value: '5' }
            { name: 'DATABASE_URL', secretRef: 'database-url' }
            { name: 'REDIS_URL', secretRef: 'redis-url' }
            { name: 'RAILS_MASTER_KEY', secretRef: 'rails-master-key' }
            { name: 'SECRET_KEY_BASE', secretRef: 'secret-key-base' }
            { name: 'DEVISE_SECRET_KEY', secretRef: 'devise-secret-key' }
            { name: 'MDI_API_BASE', value: mdiApiBase }
            { name: 'MDI_CLIENT_ID', secretRef: 'mdi-client-id' }
            { name: 'MDI_CLIENT_SECRET', secretRef: 'mdi-client-secret' }
            { name: 'MDI_WEBHOOK_SECRET', secretRef: 'mdi-webhook-secret' }
            { name: 'HONEYBEE_API_BASE', value: honeybeeApiBase }
            { name: 'HONEYBEE_AUTH_BASE', value: honeybeeAuthBase }
            { name: 'HONEYBEE_CLIENT_ID', secretRef: 'honeybee-client-id' }
            { name: 'HONEYBEE_SECRET_KEY', secretRef: 'honeybee-secret-key' }
            { name: 'HONEYBEE_WEBHOOK_SECRET', secretRef: 'honeybee-webhook-secret' }
            { name: 'STRIPE_SECRET_KEY', secretRef: 'stripe-secret-key' }
            { name: 'STRIPE_PUBLISHABLE_KEY', secretRef: 'stripe-publishable-key' }
            { name: 'SENTRY_DSN', value: sentryDsn }
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: 3000
              }
              initialDelaySeconds: 15
              periodSeconds: 30
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/health'
                port: 3000
              }
              initialDelaySeconds: 10
              periodSeconds: 10
              failureThreshold: 3
            }
            {
              type: 'Startup'
              httpGet: {
                path: '/health'
                port: 3000
              }
              initialDelaySeconds: 5
              periodSeconds: 5
              failureThreshold: 10
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 5
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '50'
              }
            }
          }
        ]
      }
    }
  }
}

// =============================================================================
// cntrl-frontend (Next.js)
// =============================================================================
resource frontendApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'ca-frontend-${environmentName}'
  location: location
  tags: union(tags, { 'azd-service-name': 'frontend' })
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 3001
        transport: 'http'
        allowInsecure: false
        customDomains: []
      }
      registries: registryConfig
      secrets: union(registrySecrets, [
        { name: 'stripe-publishable-key', keyVaultUrl: '${keyVaultUri}secrets/STRIPE-PUBLISHABLE-KEY', identity: 'system' }
      ])
    }
    template: {
      containers: [
        {
          name: 'cntrl-frontend'
          image: frontendImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            { name: 'NODE_ENV', value: 'production' }
            { name: 'PORT', value: '3001' }
            { name: 'NEXT_PUBLIC_API_URL', value: publicApiUrl }
            { name: 'NEXT_PUBLIC_SITE_URL', value: publicSiteUrl }
            { name: 'NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY', secretRef: 'stripe-publishable-key' }
            { name: 'SENTRY_DSN', value: sentryDsn }
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/api/health'
                port: 3001
              }
              initialDelaySeconds: 10
              periodSeconds: 30
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/api/health'
                port: 3001
              }
              initialDelaySeconds: 5
              periodSeconds: 10
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 5
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '100'
              }
            }
          }
        ]
      }
    }
  }
}

// =============================================================================
// cntrl-sidekiq (same Rails image, different entrypoint)
// =============================================================================
resource sidekiqApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'ca-sidekiq-${environmentName}'
  location: location
  tags: union(tags, { 'azd-service-name': 'sidekiq' })
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      // No ingress — Sidekiq is an internal background worker
      registries: registryConfig
      secrets: union(registrySecrets, [
        { name: 'database-url', keyVaultUrl: '${keyVaultUri}secrets/DATABASE-URL', identity: 'system' }
        { name: 'redis-url', keyVaultUrl: '${keyVaultUri}secrets/REDIS-URL', identity: 'system' }
        { name: 'rails-master-key', keyVaultUrl: '${keyVaultUri}secrets/RAILS-MASTER-KEY', identity: 'system' }
        { name: 'secret-key-base', keyVaultUrl: '${keyVaultUri}secrets/SECRET-KEY-BASE', identity: 'system' }
        { name: 'mdi-client-id', keyVaultUrl: '${keyVaultUri}secrets/MDI-CLIENT-ID', identity: 'system' }
        { name: 'mdi-client-secret', keyVaultUrl: '${keyVaultUri}secrets/MDI-CLIENT-SECRET', identity: 'system' }
        { name: 'honeybee-client-id', keyVaultUrl: '${keyVaultUri}secrets/HONEYBEE-CLIENT-ID', identity: 'system' }
        { name: 'honeybee-secret-key', keyVaultUrl: '${keyVaultUri}secrets/HONEYBEE-SECRET-KEY', identity: 'system' }
        { name: 'stripe-secret-key', keyVaultUrl: '${keyVaultUri}secrets/STRIPE-SECRET-KEY', identity: 'system' }
      ])
    }
    template: {
      containers: [
        {
          name: 'cntrl-sidekiq'
          image: adminImage
          command: [ 'bundle', 'exec', 'sidekiq', '-C', 'config/sidekiq.yml' ]
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            { name: 'RAILS_ENV', value: 'production' }
            { name: 'RAILS_LOG_TO_STDOUT', value: 'true' }
            { name: 'DATABASE_URL', secretRef: 'database-url' }
            { name: 'REDIS_URL', secretRef: 'redis-url' }
            { name: 'RAILS_MASTER_KEY', secretRef: 'rails-master-key' }
            { name: 'SECRET_KEY_BASE', secretRef: 'secret-key-base' }
            { name: 'MDI_API_BASE', value: mdiApiBase }
            { name: 'MDI_CLIENT_ID', secretRef: 'mdi-client-id' }
            { name: 'MDI_CLIENT_SECRET', secretRef: 'mdi-client-secret' }
            { name: 'HONEYBEE_API_BASE', value: honeybeeApiBase }
            { name: 'HONEYBEE_AUTH_BASE', value: honeybeeAuthBase }
            { name: 'HONEYBEE_CLIENT_ID', secretRef: 'honeybee-client-id' }
            { name: 'HONEYBEE_SECRET_KEY', secretRef: 'honeybee-secret-key' }
            { name: 'STRIPE_SECRET_KEY', secretRef: 'stripe-secret-key' }
            { name: 'SENTRY_DSN', value: sentryDsn }
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
      }
    }
  }
}

// =============================================================================
// cntrl-migrate (Container Apps Job — runs on deploy)
// =============================================================================
resource migrateJob 'Microsoft.App/jobs@2023-05-01' = {
  name: 'job-migrate-${environmentName}'
  location: location
  tags: union(tags, { 'azd-service-name': 'migrate' })
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    environmentId: containerAppsEnvironment.id
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 300
      replicaRetryLimit: 2
      registries: registryConfig
      secrets: union(registrySecrets, [
        { name: 'database-url', keyVaultUrl: '${keyVaultUri}secrets/DATABASE-URL', identity: 'system' }
        { name: 'rails-master-key', keyVaultUrl: '${keyVaultUri}secrets/RAILS-MASTER-KEY', identity: 'system' }
        { name: 'secret-key-base', keyVaultUrl: '${keyVaultUri}secrets/SECRET-KEY-BASE', identity: 'system' }
      ])
    }
    template: {
      containers: [
        {
          name: 'cntrl-migrate'
          image: adminImage
          command: [ 'bundle', 'exec', 'rails', 'db:migrate' ]
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            { name: 'RAILS_ENV', value: 'production' }
            { name: 'DATABASE_URL', secretRef: 'database-url' }
            { name: 'RAILS_MASTER_KEY', secretRef: 'rails-master-key' }
            { name: 'SECRET_KEY_BASE', secretRef: 'secret-key-base' }
          ]
        }
      ]
    }
  }
}

// =============================================================================
// Outputs
// =============================================================================
output environmentId string = containerAppsEnvironment.id
output adminAppName string = adminApp.name
output adminAppFqdn string = adminApp.properties.configuration.ingress.fqdn
output adminAppPrincipalId string = adminApp.identity.principalId
output frontendAppName string = frontendApp.name
output frontendAppFqdn string = frontendApp.properties.configuration.ingress.fqdn
output sidekiqAppName string = sidekiqApp.name
output sidekiqAppPrincipalId string = sidekiqApp.identity.principalId
output migrateJobName string = migrateJob.name
output migrateJobPrincipalId string = migrateJob.identity.principalId
