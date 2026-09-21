<#
Generate restricted GitHub OIDC trust, S3 role permissions and optional public-site
bucket policy. DOES NOT create AWS resources. An AWS administrator applies the JSON.
#>
param(
    [Parameter(Mandatory=$true)][string]$AwsAccountId,
    [Parameter(Mandatory=$true)][string]$BucketName,
    [Parameter(Mandatory=$true)][string]$GitHubOwner,
    [Parameter(Mandatory=$true)][string]$GitHubRepo,
    [string]$GitHubOwnerId,
    [string]$GitHubRepoId,
    [switch]$LegacySubject
)

$ErrorActionPreference = 'Stop'
if ($AwsAccountId -notmatch '^\d{12}$') { throw 'AwsAccountId must be 12 digits.' }
if ($BucketName -notmatch '^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$') { throw 'BucketName must be a valid S3 bucket name.' }
if ($GitHubOwner -notmatch '^[A-Za-z0-9-]+$' -or $GitHubRepo -notmatch '^[A-Za-z0-9_.-]+$') { throw 'Unexpected GitHub owner/repository characters.' }
if (-not $LegacySubject -and ($GitHubOwnerId -notmatch '^\d+$' -or $GitHubRepoId -notmatch '^\d+$')) {
    throw 'For an immutable GitHub subject, set the numeric GitHubOwnerId and GitHubRepoId, or specify -LegacySubject for a verified older repository.'
}

$target = Join-Path $PSScriptRoot 'generated'
New-Item -ItemType Directory -Force -Path $target | Out-Null
$subjectPrefix = if ($LegacySubject) { "repo:${GitHubOwner}/${GitHubRepo}" } else { "repo:${GitHubOwner}@${GitHubOwnerId}/${GitHubRepo}@${GitHubRepoId}" }

foreach ($environment in @('dev','stage','uat','prod')) {
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
        Statement = @(@{
            Sid = 'UploadOnlyThisEnvironment'
            Effect = 'Allow'
            Action = @('s3:PutObject')
            Resource = @(
                "arn:aws:s3:::${BucketName}/${environment}/index.html",
                "arn:aws:s3:::${BucketName}/images/${environment}/*"
            )
        })
    }
    $trust | ConvertTo-Json -Depth 12 | Set-Content -Encoding utf8 (Join-Path $target "trust-${environment}.json")
    $permissions | ConvertTo-Json -Depth 12 | Set-Content -Encoding utf8 (Join-Path $target "permissions-${environment}.json")
}

# Only the *published HTML* is publicly readable; the Docker image stays private.
$siteFiles = @('dev','stage','uat','prod') | ForEach-Object { "arn:aws:s3:::${BucketName}/$_/index.html" }
$websitePolicy = @{
    Version = '2012-10-17'
    Statement = @(@{
        Sid = 'PublicReadPublishedDemoHTMLOnly'
        Effect = 'Allow'
        Principal = '*'
        Action = 's3:GetObject'
        Resource = $siteFiles
    })
}
$websitePolicy | ConvertTo-Json -Depth 12 | Set-Content -Encoding utf8 (Join-Path $target 'OPTIONAL-website-public-read.json')
Write-Host "Created policies in $target"
Write-Host 'AWS roles: mission-control-deploy-dev / -stage / -uat / -prod'
Write-Host 'Check the OIDC subject form before applying these trust policies.'
