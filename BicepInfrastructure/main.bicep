// PARAMETERS
@description('Location for all resources')
param location string = 'South Central US'

@description('Prefix for all resource names')
param namePrefix string = 'tvp'

@description('SKU for the Storage Account')
param storageSku string = 'Standard_LRS'

@description('Name of the Function App runtime stack')
param functionRuntime string = 'python'

@description('Azure Function version')
param functionVersion string = '~4.1038.400.1'

var storageAccountName = toLower('${namePrefix}storage${uniqueString(resourceGroup().id)}')
var functionAppName = toLower('${namePrefix}func${uniqueString(resourceGroup().id)}')
var appInsightsName = '${namePrefix}-ai'
var workspaceName = '${namePrefix}-log'

// STORAGE
resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: storageSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2022-09-01' = {
  name: 'default'
  parent: storageAccount
}

resource blobContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  parent: blobService
  name: 'solar-data'
  properties: {
    publicAccess: 'None'
  }
}

resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2022-09-01' = {
  name: 'default'
  parent: storageAccount
}

resource tableStorage 'Microsoft.Storage/storageAccounts/tableServices/tables@2022-09-01' = {
  parent: tableService
  name: 'solarutilization'
}

// MONITORING
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}
// Diagnostic Settings for Storage Account
resource storageDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${storageAccount.name}-diag'
  scope: storageAccount
  properties: {
    workspaceId: logAnalytics.id

    metrics: [
      {
        category: 'Transaction' // Tracks the overall activity of the Storage Account
        enabled: true
        retentionPolicy: {
          days: 0
          enabled: false
        }
      }
    ]
  }
}
// HOSTING PLAN
resource hostingPlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: '${namePrefix}-plan'
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  kind: 'functionapp'
}

// FUNCTION APP
resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: hostingPlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage' // Tells the function where to store logs
          value: storageAccount.listKeys().keys[0].value
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION' // Function Version
          value: functionVersion
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME' // Declares which language the funtion will use
          value: functionRuntime
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY' // Connects the function to App Insights
          value: appInsights.properties.InstrumentationKey
        }
      ]
    }
    httpsOnly: true
  }
  dependsOn: []
}

// IOT HUB
resource iotHub 'Microsoft.Devices/IotHubs@2021-07-02' = {
  name: '${namePrefix}-iothub'
  location: location
  sku: {
    name: 'B1'
    capacity: 1
  }
  properties: {
    publicNetworkAccess: 'Enabled'
  }
}

// VNET
resource vnet 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: '${namePrefix}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

// NSG
resource nsg 'Microsoft.Network/networkSecurityGroups@2021-05-01' = {
  name: '${namePrefix}-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowHttps'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}
