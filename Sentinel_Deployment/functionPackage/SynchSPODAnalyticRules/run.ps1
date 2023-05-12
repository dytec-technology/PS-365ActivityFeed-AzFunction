# Input bindings are passed in via param block.
param($Timer)

#Path to the template file
$filepath = "d:\home\"

#Path for logging of rule progress
$SPOruleprocesslog = $filepath + "SPORuleprocess.log"
$SPOprocessedrules = get-content $SPOruleprocesslog

#Sentinel variables for workspaces update for each workspace to include
#$workspaceId0 = $env:SentinelWorkspaceUS
#$workspaceId1 = $env:SentinelWorkspaceEU
$workspaceId2 = $env:SentinelWorkspace
$main = @{"GlobalWorkspace" = $workspaceId2}


foreach ($workspace in $main.GetEnumerator()) {

$context = Get-AzContext
$profileR = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
$profileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient -ArgumentList ($profileR)
$token = $profileClient.AcquireAccessToken($context.Subscription.TenantId)
$authHeader = @{
  'Content-Type' = 'application/json'
  'Authorization' = 'Bearer ' + $token.AccessToken 
               }
$workspace.value
Set-AzContext $context.Subscription.name
$instance = Get-AzResource -Name $workspace.value -ResourceType Microsoft.OperationalInsights/workspaces
$WorkspaceID = (Get-AzOperationalInsightsWorkspace -Name $instance.Name -ResourceGroupName $Instance.ResourceGroupName).CustomerID

# Get the DLP Policies in store
$q = 'O365DLP_CL
| where TimeGenerated > ago(90d)
| extend PolicyName_ = tostring(parse_json(PolicyDetails_s)[0].PolicyName)
| where PolicyName_ !=""
| extend Name = PolicyName_
| summarize by Name,Workload_s'
$response = Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkspaceID -Query $q

#Get the Watchlist so that we don't store duplicates
$q2 = '(_GetWatchlist("Policy") | project SearchKey)'
$watchlist = Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkspaceID -Query $q2

$policies = $response.results | where {($_.Workload_s -contains "OneDrive") -or ($_.Workload_s -contains "SharePoint")}
$policies = $policies | Select-Object -Unique Name  

$processedPolicies = @()

#Retreiving the Sentinel Analytic rules
$path = $instance.ResourceId
$urllist = "https://management.azure.com$($path)/providers/Microsoft.SecurityInsights/alertRules?api-version=2023-04-01-preview"
$rules = Invoke-RestMethod -Method "Get" -Uri $urllist -Headers $authHeader

#Fetch Template
$template0 =  $rules.value | where-object  {$_.properties.displayname -eq "Template_SPOD"} | select-object
$date = Get-Date

     if (-not ($rules)) {throw 'Failed to connect to Sentinel Workspace'}
     if (-not ($template0)) {throw 'Failed to retreive template'}

# Looping through the policies and create Analytic Rules in Sentinel
foreach ($policy in $policies) {
$alreadyprocessed = $path + "," + $policy.Name 
if ($SPOprocessedrules -notcontains $alreadyprocessed)
                                  {
   
    $policyName2 = $policy.Name + "_SPO"
    $matchexisting = $rules.value | where-object  {$_.properties.displayname -eq $policyName2} | select-object
    $template = $template0 | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    
         if ($matchexisting) {
             $policy.name
            $template.properties.query = $template.properties.query -replace 'Policy != "" //Do Not Remove',  "Policy == '$($policy.name)'"
            $pattern = '\| where not\(Policy has_any \(policywatchlist\)\) //Do not remove'
            $template.properties.query = $template.properties.query -replace $pattern, "//This rule was updated by code $date"
            $template.properties.displayname = $matchexisting.properties.displayname
            $template.name =  $matchexisting.name
            $template.etag = $matchexisting.etag
            $template.properties.displayname = $policyName2
            $template.properties.lastModifiedUtc = ""
            $template.id = ""
                $update = $template | convertto-json -depth 20
                $update = $update -replace '"lastModifiedUtc": ""',''
                $update = $update -replace '"id": "",', ""   
                    $updateRule = $matchexisting.name
                    $urlupdate = "https://management.azure.com$path/providers/Microsoft.SecurityInsights/alertRules/$updateRule" + '?api-version=2023-04-01-preview'
                    $rule = Invoke-RestMethod -Method "Put" -Uri $urlupdate -Headers $authHeader -body $update
                              }

         if (-not $matchexisting) {
            $etag = New-Guid
            $template.properties.query = $template.properties.query -replace 'Policy != "" //Do Not Remove',  "Policy == '$($policy.Name)'"
            $pattern = '\| where not\(Policy has_any \(policywatchlist\)\) //Do not remove'
            $template.properties.query = $template.properties.query -replace $pattern, "//This rule was created by code $date"
            $template.properties.displayname = $policyName2
            $template.etag =  $etag.guid
            $template.name =  $etag.guid
            $template.properties.lastModifiedUtc = ""
            $template.id = ""
                $update = $template | convertto-json -depth 20
                $update = $update -replace '"lastModifiedUtc": ""',''
                $update = $update -replace '"id": "",', ""   
                    $urlupdate = "https://management.azure.com$path/providers/Microsoft.SecurityInsights/alertRules/$($etag.guid)" + '?api-version=2023-04-01-preview'
                    $rule = Invoke-RestMethod -Method "Put" -Uri $urlupdate -Headers $authHeader -body $update
                                  }
            
          #Keep track of already processed rules by placing in array for if sentence
          $processedPolicies += $policy.Name

          #Keep track of workspaces and rules processed
          $track = $path + "," + $policy.Name
          $track
          $track | Out-File -Append -FilePath $SPOruleprocesslog

Clear-Variable matchexisting

                                }
                                    }
$rule.count                                  
                            }
$dlplastchange = $policies.whenChanged | Sort-Object -Descending                               

# Watchlist update                            
$csv = $response.Results 

foreach ($item in $csv) {
if ($item.Name -notin $watchlist.results.SearchKey) {
 $etag = New-Guid
               $a= @{
                'etag'= $etag.guid
                'properties'= @{itemsKeyValue = @()}
                    }           
                $a.properties.itemsKeyValue = $item  
                $update = $a | convertto-json    
            $urlupdate = "https://management.azure.com$path/providers/Microsoft.SecurityInsights/watchlists/Policy/watchlistitems/$($etag)?api-version=2023-04-01-preview"
            Invoke-RestMethod -Method "Put" -Uri $urlupdate -Headers $authHeader -body $update
                                            }
                        }
