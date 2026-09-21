# Mission Control: four-environment GitHub Actions -> Amazon S3

This is a **static HTML** deployment of your existing `index.html`. It replaces the Docker/ECR/ECS deployment path for this assignment. Keep your `index.html`; the ZIP intentionally does **not** replace it. S3 stores and serves the site; it does not run your Nginx container or server-side code.

## What this implements

| Event | Detect | Build | Test | Deploy |
|---|---|---|---|---|
| Push to `dev` | dev | copy HTML into `dist/` | check nonempty HTML and Mission Control heading | automatic to `s3://BUCKET/dev/` |
| PR opened/updated targeting `stage`/`uat`/`prod` | PR target | yes | yes (PR merge check) | **no** |
| PR **merged** into `stage` or `uat` | target | yes | yes | automatic to corresponding prefix |
| PR **merged** into `prod` | prod | yes | yes | **wait for GitHub environment reviewer**, then upload to `prod/` |
| PR closed without merge | none | skipped | skipped | skipped |

GitHub **auto-merge** is a separate PR setting: it merges once pre-merge checks/reviews pass. The workflow does not merge branches itself. See GitHub setup below.

## 1 — Copy files into your EXISTING app repository

Open the ZIP, then copy the **contents of its `mission-control-s3-pipeline` folder** into the root of your existing `mission-control` repository, merging folders:

```
mission-control/
  index.html                         <- retain your existing file
  Dockerfile                         <- may stay, no longer deployed to S3
  .github/workflows/ci.yml          <- old workflow can stay; triggers main only
  .github/workflows/deploy.yml      <- NEW
  aws-setup/generate-policies.ps1   <- NEW, optional admin helper
  README-SETUP.md                    <- NEW
```

The ZIP has no `index.html` and does not overwrite your current application. Check the GitHub repository full name locally with `git remote -v`.

From the repository root (Windows PowerShell):

```powershell
git switch main
git pull
git add .github/workflows/deploy.yml aws-setup/generate-policies.ps1 README-SETUP.md
git commit -m "Add four-environment S3 deployment pipeline"
git push origin main
```

In GitHub, create branches `dev`, `stage`, `uat`, `prod` **from this updated main branch**, using the branch dropdown -> View all branches -> New branch. If a branch already exists, ensure it contains the new workflow before testing. The existing `main` workflow will NOT deploy on main; only `dev` pushes and merged PRs to the other three branches deploy.

## 2 — Get S3 website hosting configured (trainer/admin if denied)

This is one **dedicated demo bucket** with four prefixes: `dev/`, `stage/`, `uat/`, `prod/`. Have an AWS administrator create the bucket in `us-east-1` or your approved Region. Use a globally unique DNS-compliant name such as `mission-control-ACCOUNTID-us-east-1`; use your own account ID, not the literal word `ACCOUNTID`.

S3 -> Buckets -> bucket -> **Properties** -> Static website hosting -> Edit -> Enable -> Host a static website -> index document `index.html` -> Save. Copy the **Bucket website endpoint** shown there. URLs are that endpoint plus `/dev/`, `/stage/`, `/uat/`, `/prod/` (keep trailing slash). There is no index.html at the bucket root, by design.

**For this public demonstration only**, ask the bucket owner to approve public read of these four published prefixes and add `aws-setup/generated/website-public-read-bucket-policy.json` to the bucket's Permissions -> Bucket policy. Bucket-level S3 Block Public Access must allow a public bucket policy, and account/organization-level Block Public Access must not override it. Do not disable account-level protections to work around a training restriction; if public access is prohibited, ask for the approved CloudFront + Origin Access Control (OAC) option instead. Public S3 website endpoints are **HTTP-only**; CloudFront with a private bucket is preferable for a real production website. Never put secrets or private data in this bucket.

The bucket policy only grants anonymous `s3:GetObject` for the four site prefixes. It does not allow public uploads, deletes, or list operations.

## 3 — Create GitHub's OIDC provider and four scoped IAM roles (AWS admin)

Your earlier ECR error showed missing IAM permissions. If you cannot create S3/IAM resources yourself, send this README and the generated JSON policies to your trainer. Your own IAM *user* is not granted S3 access by a trust policy. A trust policy permits **GitHub's OIDC identity** to assume a role. That role's separate **permissions policy** permits S3 uploads/deletes.

IAM -> Identity providers -> Add provider:
- Provider type: **OpenID Connect**
- Provider URL: `https://token.actions.githubusercontent.com`
- Audience: `sts.amazonaws.com`
- Reuse the provider if your account already has one; never create a duplicate.

Create four IAM roles: `mission-control-deploy-dev`, `mission-control-deploy-stage`, `mission-control-deploy-uat`, `mission-control-deploy-prod`. Each role uses its matching generated `trust-ENV.json` as its **Trust relationships** policy and matching `permissions-ENV.json` as its **inline permissions** policy. The roles do not need AdministratorAccess, ECR, or broad S3 access.

**Important for repositories created from 15 July 2026:** GitHub's OIDC subject may include immutable owner and repository IDs. This generator defaults to that new form. Confirm the actual OIDC `sub` format for your repository with your administrator; repositories created before the change or opted out can use `-LegacySubject` when appropriate. The workflow's **Detect environment** job prints repository owner ID and repository ID in the GitHub Actions log, even if AWS authentication later fails. First push `dev` to obtain these IDs, then generate the policies. Do not guess the IDs or use wildcard repository subjects.

Run this locally in PowerShell with your **actual** identifiers:

```powershell
.\aws-setup\generate-policies.ps1 `
  -AwsAccountId 'YOUR_12_DIGIT_AWS_ACCOUNT_ID' `
  -BucketName 'YOUR_ACTUAL_BUCKET_NAME' `
  -GitHubOwner 'YOUR_GITHUB_OWNER' `
  -GitHubRepo 'YOUR_GITHUB_REPO' `
  -GitHubOwnerId 'OWNER_ID_FROM_ACTIONS' `
  -GitHubRepoId 'REPO_ID_FROM_ACTIONS'
```

Generated files appear under `aws-setup/generated/`. Give the trainer the eight role policy files and the website bucket policy. **Do not commit `aws-setup/generated/` if it contains account-specific details you don't want in your repository.** These are policies, not secrets, but can be shared directly with the trainer.

For each role: IAM -> Roles -> Create role -> Web identity -> select `token.actions.githubusercontent.com` and audience `sts.amazonaws.com` -> create role -> Trust relationships -> Edit trust policy -> paste corresponding generated trust JSON -> Permissions -> Add permissions -> Create inline policy -> JSON -> paste corresponding generated permissions JSON. If the IAM UI is restricted, the admin performs this setup.

The trust `sub` is environment-specific. As an extra safety measure in GitHub Environments, allow each environment to deploy **only from its same-named branch**: dev -> dev, stage -> stage, uat -> uat, prod -> prod. Do not select permissive environment patterns for prod.

## 4 — Configure GitHub repo settings

Repository -> Settings -> Secrets and variables -> Actions -> **Variables**: create:

| Repository variable | Value |
|---|---|
| `AWS_REGION` | `us-east-1` (or the chosen bucket Region) |
| `AWS_S3_BUCKET` | actual bucket name, without `s3://` |

Repository -> Settings -> **Environments** -> create exactly `dev`, `stage`, `uat`, `prod` (lowercase). For **each** environment:
- Configure deployment branches -> **Selected branches and tags** -> add ONLY the matching branch (`dev`, `stage`, `uat`, or `prod`).
- **Environment secrets** -> New secret -> name `AWS_ROLE_ARN`; set to the ARN of the matching role, e.g. `arn:aws:iam::YOUR_ACCOUNT_ID:role/mission-control-deploy-dev` for dev. Do not put AWS access key IDs or secret keys in GitHub.
- **Only prod:** enable **Required reviewers** and select your trainer/another authorized reviewer. Optionally enable Prevent self-review. The reviewer approves on the Actions run's **Review deployments** screen. A workflow file alone cannot enable the approval rule.

**GitHub plan restriction:** on GitHub Free/Pro/Team, required reviewers work only for **public** repositories; private repositories need a plan with access to that protection, such as GitHub Enterprise. If your private repository does not show Required reviewers, your trainer must provide an eligible repo/plan or another approved approval gate. Do not claim prod approval exists unless you configure and test it.

## 5 — PR protections and optional auto-merge

To enforce PR-only promotion, repository -> Settings -> Branches (or Rules -> Rulesets) -> protect `stage`, `uat`, `prod`: **Require a pull request before merging**, and **Require status checks to pass**; select the workflow's **`3 - Test`** check once it has appeared on a PR. Add review requirements as your trainer requests. This is needed because a direct push to these branches is not a deployment trigger, but without branch protection it could bypass the PR process. Avoid requiring the **Deploy** check before merge: deployment deliberately runs **after** merge, so requiring it before merge would deadlock.

If your trainer literally means **automatic PR merging**, repo -> Settings -> General -> Pull Requests -> enable **Allow auto-merge**. On each PR, click **Enable auto-merge**; it merges after required status checks/reviews pass, and the merge event starts the deployment. The workflow does **not** silently merge PRs or override reviews. Feature availability varies by GitHub plan.

## 6 — Run it end-to-end

1. After bucket/roles/GitHub configuration, edit `index.html` on your local `dev` branch (or simply push a non-breaking change) and `git push origin dev`. The four jobs run, and upload to `s3://BUCKET/dev/`.
2. Browse the S3 website endpoint + `/dev/`. If it is AccessDenied, review **bucket policy and public access settings**, not the GitHub role trust.
3. Open PR **dev -> stage**, wait for `3 - Test`, and merge (manually or enable GitHub auto-merge). It deploys `/stage/`.
4. Open PR **stage -> uat**, merge after tests. It deploys `/uat/`.
5. Open PR **uat -> prod**, merge after tests. The prod deploy job waits for the required GitHub reviewer. Once approved, it deploys `/prod/`.
6. Refresh the corresponding website URLs. Each prefix is independent and `aws s3 sync --delete` only deletes obsolete files **inside that target prefix**.

Useful command to push a tiny change from your local repository:

```powershell
git switch dev
# edit index.html and save
git add index.html
git commit -m "Update Mission Control"
git push origin dev
```

**Expected failure troubleshooting:**
- `No identity-based policy allows s3:...`: trainer must update that IAM role's **permissions** policy, or an SCP/permissions boundary may still block it.
- `Not authorized to perform sts:AssumeRoleWithWebIdentity`: wrong OIDC provider, audience, role ARN, `sub` format/IDs, branch, or environment trust. Check workflow Detect log for numeric IDs.
- `Input required and not supplied: role-to-assume`: GitHub environment secret `AWS_ROLE_ARN` missing/wrong environment.
- 403 on public website: website bucket policy/block public access settings. An authenticated S3 upload succeeding does not grant website visitors anonymous read.
- Prod never pauses: GitHub Required reviewers not configured or unsupported on current plan.

**Costs:** S3 object storage and website requests can incur costs. No ECS service, EC2 instance, ECR image, or Docker server is needed for this static site.

## Reference documentation

- GitHub OIDC with AWS: https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws
- GitHub environments/approvals: https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments
- GitHub auto-merge: https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/automatically-merging-a-pull-request
- S3 website setup and public access warning: https://docs.aws.amazon.com/AmazonS3/latest/userguide/HostingWebsiteOnS3Setup.html
- S3 website endpoints (HTTP-only): https://docs.aws.amazon.com/AmazonS3/latest/userguide/WebsiteEndpoints.html
