param lawName string
param policySync bool = false
param labelSync bool = true

resource workspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: lawName
}

resource watchlistPolicy 'Microsoft.SecurityInsights/watchlists@2023-02-01' = if(policySync == true) {
  name: 'Policy'
  scope: workspace
  properties: {
    displayName: 'Policy'
    itemsSearchKey: 'Name'
    provider: 'DLP'
    source: 'DLP'
    contentType: 'text/csv'
    numberOfLinesToSkip: 0
    description: 'DLP Policies'
    rawContent: '''
Name,Workload
40489b3c-b060-4122-af94-5dbe51996729,40489b3c-b060-4122-af94-5dbe51996729
'''
  }
}

resource watchlistSL 'Microsoft.SecurityInsights/watchlists@2023-02-01' = if(labelSync == true) {
  name: 'SensitivityLabels'
  scope: workspace
  properties: {
    displayName: 'SensitivityLabels'
    itemsSearchKey: 'id'
    provider: 'DLP'
    source: 'DLP'
    contentType: 'text/csv'
    numberOfLinesToSkip: 0
    description: 'Sensitivity Labels'
    rawContent: '''
id,name,parent
40489b3c-b060-4122-af94-5dbe51996729,40489b3c-b060-4122-af94-5dbe51996729,40489b3c-b060-4122-af94-5dbe51996729
'''
  }
}
