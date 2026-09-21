<#
Generates four environment-isolated role policies and one website bucket policy.
Does NOT change any AWS account resources. Provide the JSON files to your trainer/admin.
#>
param(
    [Parameter(Mandatory=$true)][string]$AwsAccountId,
    [Parameter(Mandatory=$true)][string]$BucketName,
    [Parameter(Mandatory=$true)][string]$GitHubOwner,
    [Parameter(Mandatory=$true)][string]$GitHubRepo,
    [Parameter(Mandatory=$true)][string]$GitHubOwnerId,
    [Parameter(Mandatory=$true)][string]$GitHubRepoId,
    [switch]$LegacySubject
)

$ErrorActionPreference = 'Stop'
if ($AwsAccountId -notmatch '^\d{12}$') { throw 'AwsAccountId must be exactly 12 digits.' }
if ($BucketName -notmatch '^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$') { throw 'BucketName must be a valid lower-case S3 bucket name.' }
if ($GitHubOwner -notmatch '^[A-Za-z0-9-]+$' -or $GitHubRepo -notmatch '^[A-Za-z0-9_.-]+$') { throw 'GitHubOwner or GitHubRepo contains unexpected characters.' }
if (-not $LegacySubject -and ($GitHubOwnerId -notmatch '^\d+$' -or $GitHubRepoId -notmatch '^\d+$')) { throw 'GitHub owner/repo IDs must be numeric.' }

$folder = Join-Path $PSScriptRoot 'generated'
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$subjectPrefix = if ($LegacySubject) {
    "repo:${GitHubOwner}/${GitHubRepo}"
} else {
    "repo:${GitHubOwner}@${GitHubOwnerId}/${GitHubRepo}@${GitHubRepoId}"
}

foreach ($environment in @('dev', 'stage', 'uat', 'prod')) {
    $subject = "${subjectPrefix}:environment:${environment}"
    $trust = @{
        Version = '2012-10-17'
        Statement = @(@{
            Effect = 'Allow'
            Principal = @{ Federated = "arn:aws:iam::${AwsAccountId}:oidc-provider/token.actions.githubusercontent.com" }
            Action = 'sts:AssumeRoleWithWebIdentity'
            Condition = @{ StringEquals = @{
                'token.actions.githubusercontent.com:aud' = 'sts.amazonaws.com'
                'token.actions.githubusercontent.com:sub' = $subject
            } }
        })
    }
    $permissions = @{
        Version = '2012-10-17'
        Statement = @(
            @{
                Sid = 'GetBucketRegion'
                Effect = 'Allow'
                Action = @('s3:GetBucketLocation')
                Resource = "arn:aws:s3:::$BucketName"
            },
            @{
                Sid = 'ListOnlyThisEnvironment'
                Effect = 'Allow'
                Action = @('s3:ListBucket')
                Resource = "arn:aws:s3:::$BucketName"
                Condition = @{ StringLike = @{ 's3:prefix' = @("${environment}/", "${environment}/*") } }
            },
            @{
                Sid = 'DeployOnlyThisEnvironment'
                Effect = 'Allow'
                Action = @('s3:GetObject', 's3:PutObject', 's3:DeleteObject')
                Resource = "arn:aws:s3:::${BucketName}/${environment}/*"
            }
        )
    }
    $trust | ConvertTo-Json -Depth 15 | Set-Content -Encoding utf8 (Join-Path $folder "trust-${environment}.json")
    $permissions | ConvertTo-Json -Depth 15 | Set-Content -Encoding utf8 (Join-Path $folder "permissions-${environment}.json")
}

$resources = @('dev', 'stage', 'uat', 'prod') | ForEach-Object { "arn:aws:s3:::${BucketName}/$_/*" }
$publicRead = @{
    Version = '2012-10-17'
    Statement = @(@{
        Sid = 'PublicReadOfDemoWebsiteOnly'
        Effect = 'Allow'
        Principal = '*'
        Action = 's3:GetObject'
        Resource = $resources
    })
}
$publicRead | ConvertTo-Json -Depth 15 | Set-Content -Encoding utf8 (Join-Path $folder 'website-public-read-bucket-policy.json')
Write-Host "Policy files created in $folder"
Write-Host "Four roles to create: mission-control-deploy-dev, mission-control-deploy-stage, mission-control-deploy-uat, mission-control-deploy-prod"
Write-Host 'IMPORTANT: verify the GitHub OIDC sub format for this repository. New repositories normally use immutable owner/repo IDs.'
