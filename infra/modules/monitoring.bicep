@description('Name of the environment')
param environmentName string

@description('Azure region')
param location string

@description('Tags for all resources')
param tags object = {}

@description('Log retention in days')
param retentionDays int = 30

var logAnalyticsName = 'log-cntrl-${environmentName}'
var appInsightsName = 'appi-cntrl-${environmentName}'

// =============================================================================
// Log Analytics Workspace
// =============================================================================
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionDays
  }
}

// =============================================================================
// Application Insights
// =============================================================================
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    RetentionInDays: retentionDays
  }
}

// =============================================================================
// Metric Alerts
// =============================================================================

// Alert: Webhook 5xx error rate > 5%
resource webhook5xxAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-webhook-5xx-${environmentName}'
  location: 'global'
  tags: tags
  properties: {
    severity: 2
    enabled: true
    scopes: [
      appInsights.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'server_errors'
          metricName: 'requests/failed'
          operator: 'GreaterThan'
          threshold: 5
          timeAggregation: 'Count'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
  }
}

// Alert: PostgreSQL connection pool exhaustion (high response time as proxy)
resource highLatencyAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-high-latency-${environmentName}'
  location: 'global'
  tags: tags
  properties: {
    severity: 2
    enabled: true
    scopes: [
      appInsights.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'high_latency'
          metricName: 'requests/duration'
          operator: 'GreaterThan'
          threshold: 5000
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
  }
}

// =============================================================================
// Outputs
// =============================================================================
output logAnalyticsWorkspaceId string = logAnalytics.id
output logAnalyticsCustomerId string = logAnalytics.properties.customerId
output logAnalyticsSharedKey string = logAnalytics.listKeys().primarySharedKey
output appInsightsName string = appInsights.name
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
output appInsightsConnectionString string = appInsights.properties.ConnectionString
