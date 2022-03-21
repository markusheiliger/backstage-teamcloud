
param location string = resourceGroup().location        

param registryServer string = 'teamcloud.azurecr.io'
param registryUsername string = ''
param registryPassword string = ''

param containerImage string 

param azureClientId string
param azureClientSecret string

param teamcloudOrganizationName string

var backstageDatabaseUsername = 'backstage'  
var backstageDatabasePassword = '${guid(resourceGroup().id)}'

var resourceName = 'bs${uniqueString(resourceGroup().id)}'

resource backstagePostgreSql 'Microsoft.DBforPostgreSQL/flexibleServers@2021-06-01' = {
  name: resourceName
  location: location
  sku: {
    name: 'Standard_B2s'
    tier: 'Burstable'
  }
  properties:{
    administratorLogin: backstageDatabaseUsername
    administratorLoginPassword: backstageDatabasePassword
    version: '13'
    publicNetworkAccess: 'Enabled'
    storage: {
        storageSizeGB: 32
    }
    backup: {
        backupRetentionDays: 7
        geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
        mode: 'Disabled'
    }  
  }

  resource allowAllWindowsAzureIps 'firewallRules' = {
    name: 'AllowAllAzureServicesAndResourcesWithinAzureIps_2022-3-17_12-3-56' 
    properties: {
      endIpAddress: '0.0.0.0'
      startIpAddress: '0.0.0.0'
    }
  }
}

resource backstageStorageAccount 'Microsoft.Storage/storageAccounts@2021-06-01' = {
  name: resourceName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {}
}

resource backstageAppServicePlan 'Microsoft.Web/serverfarms@2021-03-01' = {
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

resource backstageAppService 'microsoft.web/sites@2021-03-01' = {
  name: resourceName
  location: location
  properties: {
    serverFarmId: backstageAppServicePlan.id
    siteConfig: {
      appCommandLine: 'node packages/backend --config app-config.yaml --config app-config.production.yaml'
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
          name: 'POSTGRES_HOST'
          value: backstagePostgreSql.properties.fullyQualifiedDomainName
        }
        {
          name: 'POSTGRES_PORT'
          value: '5432' 
        }
        {
          name: 'POSTGRES_USER'
          value: '${backstageDatabaseUsername}'
        }
        {
          name: 'POSTGRES_PASSWORD'
          value: backstageDatabasePassword
        }
        {
          name: 'TEAMCLOUD_ORGANIZATION_NAME'
          value: teamcloudOrganizationName
        }
        {
          name: 'STORAGE_ACCOUNT_NAME'
          value: backstageStorageAccount.name
        }
        {
          name: 'STORAGE_ACCOUNT_KEY'
          value: backstageStorageAccount.listKeys().keys[0].value
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

output portalUrl string = 'https://${backstageAppService.properties.defaultHostName}'
output portalUpdate string = 'https://${list(publishingcreds.id,'2021-01-01').properties.scmUri}/docker/hook'
