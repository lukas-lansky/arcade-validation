Param(
  [Parameter(Mandatory=$true)][string] $azdoOrg, 
  [Parameter(Mandatory=$true)][string] $azdoProject,
  [Parameter(Mandatory=$true)][int] $buildDefinitionId,
  [Parameter(Mandatory=$true)][string] $azdoToken,
  [Parameter(Mandatory=$true)][string] $githubUser,
  [Parameter(Mandatory=$true)][string] $githubPAT,
  [Parameter(Mandatory=$true)][string] $githubOrg,
  [Parameter(Mandatory=$true)][string] $githubRepoName,
  [Parameter(Mandatory=$true)][string] $barToken, 
  [string] $buildParameters = '',
  [switch] $pushBranchToGithub,
  [string] $azdoRepoName,
  [string] $subscribedBranchName
)

set-strictmode -version 2.0
$ErrorActionPreference = 'Stop'

. $PSScriptRoot\..\common\tools.ps1
. $PSScriptRoot\validation-functions.ps1
$darc = & "$PSScriptRoot\get-darc.ps1"

$global:arcadeSdkPackageName = 'Microsoft.DotNet.Arcade.Sdk'
$global:arcadeSdkVersion = $GlobalJson.'msbuild-sdks'.$global:arcadeSdkPackageName
$global:azdoOrg = $azdoOrg
$global:azdoProject = $azdoProject
$global:buildDefinitionId = $buildDefinitionId
$global:azdoToken = $azdoToken
$global:githubUser = $githubUser
$global:githubPAT = $githubPAT
$global:githubOrg = $githubOrg
$global:githubRepoName = $githubRepoName
$global:barToken = $barToken
$global:buildParameters = if (-not $buildParameters) { "" } else { $buildParameters }
$global:pushBranchToGithub = $pushBranchToGithub
$global:azdoRepoName = if (-not $azdoRepoName) { "" } else { $azdoRepoName }
$global:subscribedBranchName = $subscribedBranchName

Write-Host "##vso[task.setvariable variable=arcadeVersion;isOutput=true]${global:arcadeSdkVersion}"
Write-Host "##vso[task.setvariable variable=qualifiedRepoName;isOutput=true]${global:githubOrg}/${global:githubRepoName}"

# Get a temporary directory for a test root. Use the agent work folder if running under azdo, use the temp path if not.
$testRootBase = if ($env:AGENT_WORKFOLDER) { $env:AGENT_WORKFOLDER } else { $([System.IO.Path]::GetTempPath()) }
$testRoot = Join-Path -Path $testRootBase -ChildPath $([System.IO.Path]::GetRandomFileName())
New-Item -Path $testRoot -ItemType Directory | Out-Null

function Get-LatestBuildSha()
{
    ## Verified that this API gets completed builds, not in progress builds
    $headers = Get-AzDOHeaders
    $uri = "https://dev.azure.com/${global:azdoOrg}/${global:azdoProject}/_apis/build/latest/${global:buildDefinitionId}?branchName=${global:subscribedBranchName}&api-version=5.1-preview.1"
    $response = (Invoke-WebRequest -Uri $uri -Headers $headers -Method Get) | ConvertFrom-Json

    ## Report non-green repos for investigation purposes. 
    if(($response.result -ne "succeeded") -and ($response.result -ne "partiallySucceeded"))
    {
        Write-Host "##vso[task.setvariable variable=buildStatus;isOutput=true]NoLKG"
        Write-Warning "The latest build on '${global:subscribedBranchName}' branch for the '${global:githubRepoName}' repository was not successful."
    }

    if("" -eq $response.triggerInfo)
    {
        return $response.sourceVersion
    }
    else 
    {
        return $response.triggerInfo.'ci.sourceSha'
    }
}

function Invoke-AzDOBuild()
{ 
    $uri = Get-AzDOBuildUri
    $headers = Get-AzDOHeaders

    $body = @{
        "definition"=@{
            "id"=$global:buildDefinitionId
        };
        "sourceBranch"=$global:targetBranch;
    }

    if("" -ne $global:buildParameters)
    {
        $body = $body += @{"parameters"=$global:buildParameters}
    }

    $content = Invoke-WebRequest -Uri $uri -Headers $headers -ContentType "application/json" -Body ($body | ConvertTo-Json) -Method Post 
    return ($content | ConvertFrom-Json).id
}

function Get-BuildStatus(
    [int] $buildId)
{
    $uri = (Get-AzDOBuildUri -buildId $buildId)
    $headers = Get-AzDOHeaders
    $content = Invoke-WebRequest -Uri $uri -Headers $headers -ContentType "application/json" -Method Get 
    return ($content | ConvertFrom-Json).status
}

function Get-BuildResult(
    [int] $buildId)
{
    $uri = (Get-AzDOBuildUri -buildId $buildId)
    $headers = Get-AzDOHeaders
    $content = Invoke-WebRequest -Uri $uri -Headers $headers -ContentType "application/json" -Method Get 
    return ($content | ConvertFrom-Json).result
}

function Get-BuildLink(
    [int] $build)
{
    $uri = (Get-AzDOBuildUri -buildId $buildId)
    $headers = Get-AzDOHeaders
    $content = Invoke-WebRequest -Uri $uri -Headers $headers -ContentType "application/json" -Method Get 
    return ($content | ConvertFrom-Json)._links.web.href
}

function Get-AzDOBuildUri(
    [int] $buildId,
    [string] $queryStringParameters
)
{
    $uri = "https://dev.azure.com/${global:azdoOrg}/${global:azdoProject}/_apis/build/builds/"
    if(0 -ne $buildId) 
    {
        $uri += $buildId
    }
    
    $uri += "?api-version=5.1" + $queryStringParameters

    return $uri
}

function Get-AzDOHeaders()
{
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":${global:azdoToken}"))
    $headers = @{"Authorization"="Basic $base64AuthInfo"}
    return $headers
}

## Global Variables
$global:githubUri = "https://${global:githubUser}:${global:githubPAT}@github.com/${global:githubOrg}/${global:githubRepoName}"
$global:azdoUri = "https://${global:githubUser}:${global:azdoToken}@dev.azure.com/${global:azdoOrg}/${global:azdoProject}/_git/${global:azdoRepoName}"
$global:remoteName = ($global:azdoOrg + "-" + $global:azdoRepoName)
$global:targetBranch = "dev/" + $global:githubUser + "/arcade-" + $global:arcadeSdkVersion
$global:darcBranchName = "refs/heads/" + $global:targetBranch
$global:darcGitHubRepoName = "https://github.com/${global:githubOrg}/${global:githubRepoName}"
$global:darcAzDORepoName = "https://dev.azure.com/${global:azdoOrg}/${global:azdoProject}/_git/${global:azdoRepoName}"
$global:darcRepoName = ""

## If able to retrieve the latest build, get the SHA that it was built from
$sha = Get-LatestBuildSha

## Clone the repo from git
Write-Host "Cloning '${global:githubRepoName} from GitHub"
GitHub-Clone $global:githubRepoName $global:githubUser $global:githubUri

## Check to see if branch exists and clean it up if it does
$branchExists = $false
if($true -eq $global:pushBranchToGithub)
{
    Write-Host "Looking up '${global:targetBranch}' branch on GitHub"
    $branchExists = Git-Command $global:githubRepoName ls-remote --heads $global:githubUri refs/heads/$global:targetBranch
}
else 
{
    Write-Host "Looking up '${global:targetBranch}' branch on Azure DevOps"
    $branchExists = Git-Command $global:githubRepoName ls-remote --heads $global:azdoUri refs/heads/$global:targetBranch
}
if($null -ne $branchExists)
{
    Write-Host "${global:targetBranch} was found. Attempting to clean up."
    try
    {
        if($true -eq $global:pushBranchToGithub)
        {
            & $darc delete-default-channel --channel "General Testing" --branch $global:darcBranchName --repo $global:darcGitHubRepoName --github-pat $global:githubPAT --password $global:bartoken
            Git-Command $global:githubRepoName push origin --delete $global:targetBranch
        }
        else
        {
            & $darc delete-default-channel --channel "General Testing" --branch $global:darcBranchName --repo $global:darcAzDORepoName --azdev-pat $global:azdoToken --password $global:bartoken
            Git-Command $global:githubRepoName remote add $remoteName $global:azdoUri
            Git-Command $global:githubRepoName push $remoteName --delete $global:targetBranch
        }
    }
    catch
    {
        Write-Warning "Unable to delete default channel or branch when cleaning up"
    }
}

## Create a branch from the repo with the given SHA.
Git-Command $global:githubRepoName checkout -b $global:targetBranch $sha

## Get the BAR Build ID for the version of Arcade we want to use in update-dependecies
$asset = & $darc get-asset --name $global:arcadeSdkPackageName --version $global:arcadeSdkVersion --github-pat $global:githubPAT --azdev-pat $global:azdoToken --password $global:bartoken
$barBuildIdString = $asset | Select-String -Pattern 'BAR Build Id:'
$barBuildId = ([regex]"\d+").Match($barBuildIdString).Value

## Make the changes to that branch to update Arcade - use darc
Set-Location $(Get-Repo-Location $global:githubRepoName)
& $darc update-dependencies --id $barBuildId --github-pat $global:githubPAT --azdev-pat $global:azdoToken --password $global:bartoken

