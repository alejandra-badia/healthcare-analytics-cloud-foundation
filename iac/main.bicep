// PROPERTY OF: HealthOps Analytics Platform (HFD)
// BLUEPRINT: Secure Cloud Data Infrastructure Foundation (Sprint 3)
// FILE: main.bicep

targetScope = 'resourceGroup'

// --- PARAMETERS ---
@description('The organizational department or platform prefix.')
param organization string = 'hfd'

@description('The workload name or platform context.')
param platform string = 'healthops'

@description('The target environment tier.')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string = 'dev'

@description('The Azure location where resources will be provisioned.')
param location string = resourceGroup().location

@description('Array of public IP addresses authorized to temporarily bypass the storage firewall.')
param allowedIPAddresses array = [
 // Automates embedding your verified client firewall IP safely!
]

@description('The master object containing the 8 mandatory governance tags.')
param mandatoryTags object = {
  Platform: 'Healthcare Operations Analytics Platform'
  Workload: 'Cloud Foundation'
  Environment: 'Development'
  BusinessUnit: 'Operations Analytics'
  Owner: 'Cloud Operations Team'
  CostCenter: 'IT-Analytics'
  DataClassification: 'Confidential-HIPAA'
  ManagedBy: 'GitHub-IaC'
}

// --- VARIABLES ---
var vnetName = 'vnet-${organization}-${platform}-${environment}'
var subnetName = 'default'
var storageAccountName = 'st${organization}${platform}${environment}'
var containerName = 'healthops-data'
var privateEndpointName = 'pe-${organization}-${platform}-${environment}-blob'
var privateDnsZoneName = 'privatelink.blob.${az.environment().suffixes.storage}'

// --- VIRTUAL NETWORK & SUBNET ---
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  tags: mandatoryTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.0.0.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          defaultOutboundAccess: false
        }
      }
    ]
  }
}

// --- DATA LAKE STORAGE ACCOUNT (ADLS GEN2) ---
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: mandatoryTags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    isHnsEnabled: true // CRITICAL: Unlocks true Hierarchical Namespace Data Lake capability
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    defaultToOAuthAuthentication: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny' // Enforces zero trust network boundary rules
      ipRules: [for ip in allowedIPAddresses: {
        value: ip
        action: 'Allow'
      }]
    }
  }
}

// --- STORAGE CONTAINERS ---
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: containerName
  properties: {
    publicAccess: 'None'
  }
}

// --- PRIVATE ENDPOINT CONNECTION ---
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: privateEndpointName
  location: location
  tags: mandatoryTags
  properties: {
    subnet: {
      id: vnet.properties.subnets[0].id
    }
    customNetworkInterfaceName: '${privateEndpointName}-nic'
    privateLinkServiceConnections: [
      {
        name: privateEndpointName
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

// --- PRIVATE DNS ZONE INTEGRATION ---
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneName
  location: 'global'
  tags: mandatoryTags
}

resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: '${vnetName}-link'
  location: 'global'
  tags: mandatoryTags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource dnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-blob-core-windows-net'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}