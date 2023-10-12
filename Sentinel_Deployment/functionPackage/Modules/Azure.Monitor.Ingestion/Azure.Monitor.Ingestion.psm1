<#
 .Synopsis
  Sends mutiple events/objects to Azure Monitor Logs.

 .Description
  Leveraging the Azure Monitor Ingestion client library for .Net, this module sends an array of objects to Azure Monitor Logs via the Logs Ingestion API and a Data Collection Rule (DCR). This function includes logic to properly split the array of data into chunks that are accepted by Azure Monitor.

 .Parameter Data
  The data to be sent to Azure Monitor. This can be a PowerShell object or an array of objects.

 .Parameter BatchSize
  (Optional) The number of objects within the arrary to send to the Azure Monitor API in a single request. If not specified, the entire array will be sent in a single request.

 .Parameter JsonDepth
  (Optional) Specifies how many levels of contained objects are included in the JSON. Default is 100.

 .Parameter TableName
  Name of Azure Monitor Logs table that the data will be sent to. The name needs to include the proper prefix suffix as specified in the DCR (e.g., Custom-TableName_CL).

 .Parameter UamiClientId
  The user-assigned managed identity client ID that will be used to authenticate to Azure Monitor.
   
 .Parameter DceUri
  The Azure Monitor data collection endpoint URI that will be used to send the data to.
 
 .Parameter DcrImmutableId
  The Azure monitor data collection rule immutabel ID.

 .Parameter DataAlreadyGzipEncoded
  (Optional) Specifies if the data to be sent is already Gzip encoded (compressed). Default value is false, in which the data will be compressed via Gzip before sending to Azure Monitor. 

 .Parameter SortBySize
  (Optional) If set to true, the objects in the array will be sorted from smallest to largest before sending to Azure Monitor. This can increase throughput for arrays that have objects that vary greatly in size. Default is true.

 .Parameter MaxRetries
  (Optional) Specified how many times the request will be retried in the event an error occurs during transmission. Default value is 5.

 .Parameter EventIdPropertyName
  (Optional) The property within the object that represents the unique id of the object/event. If specified, this property will be logged in the event an object is too large to send to Azure Monitor.

 .Parameter Timeout
  (Optional) Number of seconds the operation needs to complete within before terminating. Default is 300 seconds (5 minutes).

 .Example
   # Send an array of objects to Azure Monitor Logs.
   Send-DataToAzureMonitorBatched -Data $array -TableName "Custom-TableName_CL" -JsonDepth 100 -UamiClientId  -dceURI $dceURI -dcrImmutableId $dcrImmutableId -DataAlreadyGZipEncoded $false -SortBySize $true -DelayInMilliseconds 0 -BatchSize 10000 -EventIdPropertyName 'Identifier'
#>
function Send-DataToAzureMonitorBatched {
    param (
        $Data,
        [int] $BatchSize = 0, 
        [string] $TableName,
        [int] $JsonDepth = 100,
        [string] $UamiClientId,
        [string] $DceUri,
        [string] $DcrImmutableId,
        [boolean] $DataAlreadyGZipEncoded = $false,
        [boolean] $SortBySize = $true,
        [int] $Delay = 0,
        [int] $MaxRetries = 5,
        [string] $EventIdPropertyName,
        [int] $Timeout = 300
    )
    $skip = 0
    $errorCount = 0
    $time = Get-Date
    if ($BatchSize -eq 0) { $BatchSize = $Data.Count }
    #Sort data by size, smallest to largest to get optimal batching.
    if ($SortBySize -eq $true) { 
        Write-Host "Sorting data..."
        $getSize = { ($_ | ConvertTo-Json -Depth $JsonDepth).Length }
        $Data = $Data | Sort-Object -Property $getSize 
    }
    #Enter error handling loop to send data.
    Write-Host ("Sending " + $Data.Count + " events/objects to Azure Monitor...")
    do {
        try {
            do {
                if ($Data.Count -lt $BatchSize) { $BatchSize = $Data.Count }
                $batchedData = $Data | Select-Object -Skip $skip -First $BatchSize
                if ($batchedData.Count -eq 0) { return }
                Send-DataToAzureMonitor -Data $batchedData -TableName $TableName -JsonDepth $JsonDepth -UamiClientId $UamiClientId -DceUri $DceUri -DcrImmutableId $DcrImmutableId -DataAlreadyGZipEncoded $DataAlreadyGZipEncoded | Out-Null
                $skip += $BatchSize
                Start-Sleep -Milliseconds $Delay
            } until ($skip -ge $Data.Count)
            Write-Host "Completed sending data to Azure Monitor."
            return
        }
        catch {
            if ($_.Exception.InnerException.Message -like "*ErrorCode: ContentLengthLimitExceeded*") { 
                if ($BatchSize -eq 1) {
                    Write-Error ("Event ID: " + $batchedData[0].$EventIdPropertyName + " is too large to submit to Azure Monitor. JSON Length: " + ($batchedData[0] | ConvertTo-Json -Depth $JsonDepth).Length + ". $_") -ErrorAction Continue
                    if ($skip -lt ($Data.Count - 1 )) {
                        $skip++
                    } 
                    else {
                        $errorCount = $MaxRetries
                    }
                }
                else {
                    $BatchSize = [math]::Round($BatchSize / 2)
                    if ($BatchSize -lt 1) { $BatchSize = 1 }
                    Write-Host ("Data too large, reducing batch size to: $BatchSize.")
                }
            }
            else { 
                Write-Error $_ -ErrorAction Continue
                $errorCount++
            }
            if ($errorCount -ge $MaxRetries) { Write-Error "Max number of retries reached, aborting." -ErrorAction Continue}
            if ((Get-Date) -ge $time.AddSeconds($Timeout)) { Write-Error "Timeout reached, aborting." -ErrorAction Continue }
        }
    } until ($errorCount -ge $MaxRetries -or (Get-Date) -ge $time.AddSeconds($Timeout))
}

<#
 .Synopsis
  Sends data to Azure Monitor Logs.

 .Description
  Leveraging the Azure Monitor Ingestion client library for .Net, this module sends an object or array of objects to Azure Monitor Logs via the Logs Ingestion API and a Data Collection Rule (DCR).

 .Parameter Data
  The data to be sent to Azure Monitor. This can be a PowerShell object or an array of objects.

 .Parameter JsonDepth
  (Optional) Specifies how many levels of contained objects are included in the JSON. Default is 100.

 .Parameter TableName
  Name of Azure Monitor Logs table that the data will be sent to. The name needs to include the proper prefix suffix as specified in the DCR (e.g., Custom-TableName_CL).

 .Parameter UamiClientId
  The user-assigned managed identity client ID that will be used to authenticate to Azure Monitor.
   
 .Parameter DceUri
  The Azure Monitor data collection endpoint URI that will be used to send the data to.
 
 .Parameter DcrImmutableId
  The Azure monitor data collection rule immutabel ID.

 .Parameter DataAlreadyGzipEncoded
  (Optional) Specifies if the data to be sent is already Gzip encoded (compressed). Default value is false, in which the data will be compressed via Gzip before sending to Azure Monitor.

 .Example
   # Send an array of objects to Azure Monitor Logs.
   Send-DataToAzureMonitorBatched -Data $array -TableName "Custom-TableName_CL" -JsonDepth 100 -UamiClientId  -dceURI $dceURI -dcrImmutableId $dcrImmutableId -DataAlreadyGZipEncoded $false'
#>
function Send-DataToAzureMonitor {
    param (
        $Data,
        [string] $TableName,
        [int] $JsonDepth,
        [string] $UamiClientId,
        [string] $DceUri,
        [string] $DcrImmutableId,
        [boolean] $DataAlreadyGZipEncoded = $false
    )
    #Create Azure.Identity credential via User Assigned Managed Identity.
    $credential = New-Object Azure.Identity.ManagedIdentityCredential($UamiClientId)
    #Create LogsIngestionClient to handle sending data to Azure Monitor.
    $logIngestionClient = New-Object Azure.Monitor.Ingestion.LogsIngestionClient($DceUri, $credential)
    #Send data to Azure Monitor.
    if ($DataAlreadyGZipEncoded -eq $false) { $logIngestionClient.Upload($DcrImmutableId, $TableName, ($Data | ConvertTo-Json -Depth $JsonDepth -AsArray)) | Out-Null }
    else { $logIngestionClient.Upload($dcrImmutableId, $TableName, ($Data | ConvertTo-Json -Depth $JsonDepth -AsArray), 'gzip') | Out-Null }
}

Export-ModuleMember -Function Send-DataToAzureMonitor
Export-ModuleMember -Function Send-DataToAzureMonitorBatched