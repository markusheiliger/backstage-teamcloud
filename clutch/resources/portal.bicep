
param location string = resourceGroup().location        

param registryServer string = 'teamcloud.azurecr.io'
param registryUsername string = ''
param registryPassword string = ''

param containerImage string 

param azureClientId string
param azureClientSecret string

param teamcloudOrganizationName string

var resourceName = 'bs${uniqueString(resourceGroup().id)}'

resource clutchStorageAccount 'Microsoft.Storage/storageAccounts@2021-06-01' = {
  name: resourceName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {}
}

resource clutchAppServicePlan 'Microsoft.Web/serverfarms@2021-03-01' = {
  name: resourceName
  location: location
  kind: 'linux'
  sku: {
    name: 'S2'
    tier: 'Standard'
  }
  properties: {
    targetWorkerSizeId: 0
    targetWorkerCount: 1
    reserved: true
  }
}

resource clutchAppService 'microsoft.web/sites@2021-03-01' = {
  name: resourceName
  location: location
  properties: {
    serverFarmId: clutchAppServicePlan.id
    siteConfig: {
      // appCommandLine: 'node packages/backend --config app-config.yaml --config app-config.production.yaml'
      linuxFxVersion: 'DOCKER|${registryServer}/${containerImage}'
      appSettings: [
        {
          name: 'DOCKER_REGISTRY_SERVER_URL'
          value: 'https://${registryServer}'
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_USERNAME'
          value: registryUsername
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_PASSWORD'
          value: registryPassword
        }
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'false'
        }
        {
          name: 'WEBSITES_PORT'
          value: '7007'
        }
        {
          name: 'TEAMCLOUD_ORGANIZATION_NAME'
          value: teamcloudOrganizationName
        }
        {
          name: 'STORAGE_ACCOUNT_NAME'
          value: clutchStorageAccount.name
        }
        {
          name: 'STORAGE_ACCOUNT_KEY'
          value: clutchStorageAccount.listKeys().keys[0].value
        }
        {
          name: 'AUTH_MICROSOFT_CLIENT_ID'
          value: azureClientId
        }
        {
          name: 'AUTH_MICROSOFT_CLIENT_SECRET'
          value: azureClientSecret
        }
        {
          name: 'AUTH_MICROSOFT_TENANT_ID'
          value: tenant().tenantId
        }
      ]
    }
  }

  resource logs 'config' = {
    name: 'logs'
    properties: {
      applicationLogs: {
        fileSystem: {
          level: 'Warning'
        }
      }
      detailedErrorMessages: {
        enabled: true
      }
      failedRequestsTracing: {
        enabled: true
      }
      httpLogs: {
        fileSystem: {
          enabled: true
          retentionInDays: 1
          retentionInMb: 35
        }
      }
    }
  }
}

resource publishingcreds 'Microsoft.Web/sites/config@2021-01-01' existing = {
  name: '${resourceName}/publishingcredentials'
}

output portalUrl string = 'https://${clutchAppService.properties.defaultHostName}'
output portalUpdate string = 'https://${list(publishingcreds.id,'2021-01-01').properties.scmUri}/docker/hook'
