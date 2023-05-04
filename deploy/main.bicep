@description('The suffix applied to all resources')
param appName string = uniqueString(resourceGroup().id)

@description('Location to deploy all our resources')
param location string = resourceGroup().location

@description('The name of the Log Analytics workspace')
param logAnalyticsWorkspaceName string = 'law-${appName}'

@description('The name of the container app environment')
param containerAppEnvName string = 'env-${appName}'

@description('The name of the Service Bus namespace')
param serviceBusName string = 'sb-${appName}'

@description('The name of the Container Registry')
param containerRegistryName string = 'cr${appName}'

@description('The name of the key vault that will be deployed')
param keyVaultName string = 'kv-${appName}'

@description('The name of the App Insights workspace')
param appInsightsName string = 'appins-${appName}'

var topicName = 'orders'

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    retentionInDays: 30
    features: {
      searchVersion: 1
    }
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource serviceBus 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: serviceBusName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }

  resource topic 'topics' = {
    name: topicName
    properties: {
      supportOrdering: true
    }

    resource subscription 'subscriptions' = {
      name: topicName
      properties: {
        deadLetteringOnFilterEvaluationExceptions: true
        deadLetteringOnMessageExpiration: true
        maxDeliveryCount: 10
      }
    }
  }
}

resource env 'Microsoft.App/managedEnvironments@2022-10-01' = {
  name: containerAppEnvName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }

  resource daprComponent 'daprComponents' = {
    name: 'orderpubsub'
    properties: {
      componentType: 'pubsub.azure.servicebus'
      version: 'v1'
      secrets: [
        {
          name: 'sb-root-connectionstring'
          value: '${listKeys('${serviceBus.id}/AuthorizationRules/RootManageSharedAccessKey', serviceBus.apiVersion).primaryConnectionString};EntityPath=orders'
        }
      ]
      metadata: [
        {
          name: 'connectionString'
          secretRef: 'sb-root-connectionstring'
        }
        {
          name: 'consumerID'
          value: 'orders'
        }
      ]
      scopes: []
    }
  }
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: containerRegistryName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    adminUserEnabled: true
    anonymousPullEnabled: false
    dataEndpointEnabled: false
    encryption: {
      status: 'disabled'
    }
    networkRuleBypassOptions: 'AzureServices'
    publicNetworkAccess: 'Enabled'
    zoneRedundancy: 'Disabled'
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    accessPolicies: [
      
    ]
    enabledForTemplateDeployment: true
    enabledForDeployment: true
    enableSoftDelete: false
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}

module orders 'modules/orders.bicep' = {
  name: 'orders'
  params: {
    appInsightsName: appInsights.name
    containerRegistryName: containerRegistry.name
    envId: env.id
    keyVaultName: keyVault.name 
    location: location
    serviceBusName: serviceBus.name
  }
}

module checkout 'modules/checkout.bicep' = {
  name: 'checkout'
  params: {
    appInsightsName: appInsights.name 
    containerRegistryName: containerRegistry.name
    envId: env.id
    keyVaultName: keyVault.name 
    location: location
  }
}
