<# 
    .SYNOPSIS 
        This Azure Automation runbook automates tiering of blobs in Azure Storage Accounts.  
 
    .DESCRIPTION 
        This script will scan a designated storage account for all blobs, it will then set the tier (Hot, Cool or Archive) for each 
        blob that is older then a retention period of days in which you specify. 
 
        Setting object level access tier is only supported for Standard LRS, GRS, and RA-GRS Blob Storage and General Purpose  
        V2 Accounts. https://aka.ms/blobtiering 
 
        This is a PowerShell runbook, as opposed to a PowerShell Workflow runbook. 
 
    .PARAMETER AzureCredentialName 
        The name of the PowerShell credential asset in the Automation account that contains username and password 
        for the account used to connect to Azure subscription. 
 
        For for details on credential configuration, see: 
        http://azure.microsoft.com/blog/2014/08/27/azure-automation-authenticating-to-azure-using-azure-active-directory/ 
 
    .PARAMETER AzureSubscriptionIDVariableName 
        The name of the Azure Automation Variable - Azure subscription ID 
     
    .PARAMETER StorageAccountName 
        The Storage Account name in your subscription in which to have this script to scan for blobs, as potential blobs 
        to change the tier on. 
 
    .PARAMETER $StorageTier 
        The Tier you want to set older blobs to. Can be either - Hot | Cool | Archive. 
 
    .PARAMETER $DaysOld 
        Enter the number of days retention you want to set, the tier will be set on any older blobs. 
 
    .EXAMPLE 
        See the documentation at: 
 
        https://marckean.com/2018/05/27/change-azure-storage-blob-tiers/ 
     
    .INPUTS 
        None. 
 
    .OUTPUTS 
        Human-readable informational and error messages produced during the job. Not intended to be consumed by another runbook. 
#> 
 
param(
    [parameter(Mandatory=$true)] 
    [String] $AzureSubscriptionID = "Use *Default Azure Subscription* Variable Value", 
    [parameter(Mandatory=$true)] 
    [String] $StorageAccountName = "mystorageaccountname", 
    [parameter(Mandatory=$true)] 
    [String] $StorageTier = "Hot / Cool / Archive", 
    [parameter(Mandatory=$true)] 
    [int]$DaysOld 
)

    $ServicePrincipalConnection = Get-AutomationConnection -Name 'AzureRunAsConnection'

    $null = Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $ServicePrincipalConnection.TenantId `
        -ApplicationId $ServicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $ServicePrincipalConnection.CertificateThumbprint

    # Select Azure Subscription
    Write-Output "Select Azure subscription…"
    $Subscription = Get-AzureRmSubscription -SubscriptionId $AzureSubscriptionID -TenantId $ServicePrincipalConnection.TenantId
    Select-AzureRmSubscription -Subscription $Subscription

# Setup the Storage Connection stuff
$StgAcct = Get-AzureRmStorageAccount |
Where-Object {($_.StorageAccountName -eq $StorageAccountName) -and ($_.sku.tier -eq 'Standard') -and ($_.Kind -eq 'StorageV2' -or $_.Kind -eq 'BlobStorage')}

write-output "Storage Account Name is: $($StgAcct.StorageAccountName)"

if ($StgAcct) {

$StgAcctKey = (Get-AzureRmStorageAccountKey -ResourceGroupName ($StgAcct).ResourceGroupName `
                                            -Name ($StgAcct).StorageAccountName).Value[0]

$StgAcctContext = New-AzureStorageContext -StorageAccountName ($StgAcct).StorageAccountName `
                                          -StorageAccountKey $StgAcctKey
$StorageContainers = Get-AzureStorageContainer -Context $StgAcctContext

# Cycle through all blobs in the storage account
$Blobs = @()
foreach($StorageContainer in $StorageContainers){
$Blobs += Get-AzureStorageBlob -Context $StgAcctContext -Container ($StorageContainer).Name
}

# Date Logic
$UTCDate = (Get-Date).ToUniversalTime()
$RetentionDate = $UTCDate.AddDays(-$DaysOld)
$EarmarkedBlobs = $Blobs | Where-Object {$_.lastmodified.DateTime -le $RetentionDate}

# Change the Tier on the blobs
Foreach($Blob in $EarmarkedBlobs){
#Set tier of all blobs to desired tier
$blob.icloudblob.SetStandardBlobTier($StorageTier)
}

Write-Output "`n`nDone... Complete. Check your Blog Tiers in the portal.`n"

} else {

Write-Error "Your selected Storage account cannot be used, most likely because it's `
not a V2 Storage account, a blob storage account or it's not a Standard Storage account"

}