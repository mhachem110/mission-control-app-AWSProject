# Mission Control: COMPLETE Docker + GitHub Actions + S3 project

**What this deploys:** GitHub Actions builds an actual Docker/Nginx image from `Dockerfile`, saves it as a `.tar.gz` archive, runs a container and HTTP smoke test, then uploads the tested image archive **and** its `Dockerfile` to S3. It also uploads the same HTML page to an S3 website path so you can open Mission Control in a browser. **S3 stores the image but cannot run a container.** This design satisfies "Docker build + S3 deployment" without pretending S3 is ECS. If your trainer instead expects the Docker container to run in AWS, ask them which runtime (ECS, App Runner, EC2, etc.); that is a different deployment target.

The archive is complete: `index.html`, `Dockerfile`, `.dockerignore`, `.gitignore`, `.github/workflows/deploy.yml`, `tests/smoke.sh`, `aws-setup/generate-policies.ps1`, and this README. No npm installation, ECR, ECS or Docker Desktop is needed by the GitHub-hosted build runner. Keep Docker Desktop if you want to demo locally.

## START HERE: Replace the existing working files, NOT Git history

**Do not permanently delete your original project's hidden `.git` folder or your GitHub repo.** Easiest safe method:

1. Close VS Code. In File Explorer, rename your old `mission-control` folder to `mission-control-backup` (do not delete it yet).
2. Open PowerShell in the parent folder `AWS_Week1Project1_MahmoudHachem` and clone your **existing** repo:

   ```powershell
   git clone https://github.com/mhachem110/mission-control-app-AWSProject.git mission-control
   cd mission-control
   ```

   If your actual repo's URL is different, copy its HTTPS URL from **GitHub -> Code** and use that instead. If you prefer to keep the existing folder, keep its `.git` directory and replace only the project files.
3. Extract `mission-control-docker-s3-complete.zip`. Select **everything inside the ZIP** (including the hidden-looking `.github` directory) and copy it into the new `mission-control` folder. Choose **Replace** when asked for `index.html` and `Dockerfile`. The ZIP is flat at the root: do not add another nested `mission-control` folder.
4. Remove the OLD `.github/workflows/ci.yml` so that only `deploy.yml` runs. If it exists, you can run `git rm .github/workflows/ci.yml` in PowerShell (ignore the missing-file error if it's absent).
5. Commit your new project to your existing repo's `main` branch:

   ```powershell
   git switch main
   git add -A
   git commit -m "Build Docker and deploy Mission Control through S3"
   git push origin main
   ```

   `main` stores the finished pipeline, but **does not deploy**. The `dev` branch is the automatic deployment trigger.

## 1. Create branches from the UPDATED main

In **GitHub -> your repo -> branch dropdown -> View all branches -> New branch**, create `dev`, `stage`, `uat`, `prod` **from `main`**. If they already exist, update them to include the new workflow before continuing; do not recreate them on top of stale code. If GitHub asks for a base/source branch, choose `main`.

The workflow does:

| Event | Detect | Build Docker | Test running container | Deploy to S3 |
|---|---|---|---|---|
| Push to `dev` | dev | yes | yes | automatic |
| PR opened/updated targeting `stage`, `uat`, `prod` | target | yes | yes | **not yet** |
| PR merged to `stage` or `uat` | target | yes | yes | automatic |
| PR merged to `prod` | prod | yes | yes | **waits for GitHub reviewer** |
| PR closed without merging | skipped | skipped | skipped | skipped |

GitHub's optional **Enable auto-merge** is separate from this workflow. It merges a PR only after the repo's checks and any required reviews pass; the workflow deploys **after** the merge.

## 2. Ask your trainer to prepare AWS (likely necessary for your restricted training account)

The earlier `ecr:DescribeRepositories` error shows your IAM user lacks at least some service permissions. This project does not need ECR, but your trainer/admin might need to create IAM and S3 resources for you.

Give them this request:

> Please create one dedicated S3 bucket for my Docker-to-S3 Mission Control training project in the approved AWS Region. I need GitHub Actions OIDC authentication with four branch/environment-specific IAM roles (dev, stage, uat, prod), each allowed to upload only its own site file and Docker image archives. Please also enable approved S3 static website hosting for the four environment HTML pages, or tell me if our account requires private S3 + CloudFront. I will send you generated trust and permissions policies. No IAM access keys are needed.

**S3 console:** S3 -> Create bucket -> choose an unused, DNS-compatible bucket name and the approved Region (e.g. `us-east-1`). Keep default SSE-S3 encryption; do not turn on requester pays. Enable **Properties -> Static website hosting -> index document `index.html`** if your trainer allows public website endpoints. For this demo only, and only with approval, the trainer can use the generated `OPTIONAL-website-public-read.json` bucket policy and appropriately configured public-access settings. This exposes ONLY `/dev/index.html`, `/stage/index.html`, `/uat/index.html`, `/prod/index.html`, NOT the Docker image archives. **Never disable account/organization-wide public-access controls to circumvent training restrictions.** If public website hosting is prohibited, the CI/CD pipeline can still upload private Docker archives to S3; the trainer must provide an approved private S3 + CloudFront setup to view the site. S3 website endpoints use HTTP, not HTTPS.

**IAM provider (admin):** IAM -> Identity providers -> Add provider -> OpenID Connect -> Provider URL `https://token.actions.githubusercontent.com` -> Audience `sts.amazonaws.com`. Reuse an existing provider if already present.

## 3. Generate exact IAM role policies

We cannot guess your bucket name, account ID, or GitHub OIDC subject. First, **push a commit to `dev`** (even before AWS is ready) so its **1 - Detect environment** Action log prints your numeric **Repository owner ID** and **Repository ID**. Its deploy job will fail until roles and variables exist; that is expected. Alternatively, your admin can obtain IDs and check the subject format from GitHub's OIDC docs.

From PowerShell in the `mission-control` folder, replace every `YOUR_...` entry below with your real values:

```powershell
.\aws-setup\generate-policies.ps1 `
  -AwsAccountId 'YOUR_12_DIGIT_ACCOUNT_ID' `
  -BucketName 'YOUR_ACTUAL_BUCKET_NAME' `
  -GitHubOwner 'YOUR_GITHUB_USERNAME_OR_ORG' `
  -GitHubRepo 'YOUR_GITHUB_REPO_NAME' `
  -GitHubOwnerId 'OWNER_ID_FROM_ACTIONS' `
  -GitHubRepoId 'REPO_ID_FROM_ACTIONS'
```

For repositories created **before July 15, 2026** that have *not* opted into immutable OIDC subjects, omit both ID parameters and add `-LegacySubject`. For newer repositories, **use the IDs**. If IAM reports `Not authorized to perform sts:AssumeRoleWithWebIdentity`, the admin should check the actual OIDC subject before changing trust; GitHub environments change the `sub` format to `...:environment:dev` etc.

The script generates nine JSON documents inside `aws-setup/generated/`: `trust-dev.json`, `permissions-dev.json`, and matching pairs for `stage`, `uat`, `prod`, plus `OPTIONAL-website-public-read.json`. This folder is ignored by Git and the script **does not modify AWS**. Send the files to your trainer. The trust policy identifies which GitHub environment may assume each role; the separate permissions policy allows only `s3:PutObject` to that environment's paths.

**Trainer applies the policies:** IAM -> Roles -> Create role -> **Web identity** -> GitHub OIDC provider and `sts.amazonaws.com` audience. Name the four roles `mission-control-deploy-dev`, `mission-control-deploy-stage`, `mission-control-deploy-uat`, `mission-control-deploy-prod`. For each role, paste its `trust-ENV.json` into **Trust relationships -> Edit trust policy** and its `permissions-ENV.json` under **Permissions -> Add permissions -> Create inline policy -> JSON**. Copy each role ARN. If the IAM wizard cannot create the needed trust directly, have the admin create and edit the role with these exact trust documents. The bucket owner applies the OPTIONAL bucket policy only if public website hosting is explicitly approved.

## 4. Connect the IAM roles to GitHub

Go to **GitHub repository -> Settings -> Secrets and variables -> Actions -> Variables -> New repository variable**:

- `AWS_REGION` = your S3 bucket's Region, for example `us-east-1`.
- `AWS_S3_BUCKET` = your actual bucket name, with **no** `s3://` prefix.

Then **Settings -> Environments** -> create these four lowercase environments: `dev`, `stage`, `uat`, `prod`. For **each** environment, set its deployment branch restriction to its **matching branch only**, and create a secret named **`AWS_ROLE_ARN`** containing the matching role's complete ARN. Do not use permanent AWS access keys.

For **prod**, enable **Required reviewers** and select your trainer. The run's **Review deployments** button provides the manual approval. GitHub Free/Pro/Team required-reviewer protections are generally only available for **public** repositories; an eligible paid enterprise plan or an approved alternative gate may be needed for a private repo. If reviewers are unavailable, the YAML alone cannot provide genuine manual approval. Do not make a private codebase public just to obtain this feature without your trainer's approval.

**Branch controls:** GitHub Settings -> Rules -> Rulesets (or Branches -> Branch protection) -> require PRs for `stage`, `uat`, `prod` and require the **3 - Test Docker container** PR check to pass before merge. Do NOT require the Deploy check before merge: deployment happens after merge. If the trainer requires PRs to merge automatically, enable **Allow auto-merge** under repository Settings -> General, then choose **Enable auto-merge** on each PR (subject to branch controls and plan availability).

## 5. Deploy and show the trainer

Push an update to `dev` (GitHub's repo UI can edit `index.html` on the `dev` branch, or use PowerShell):

```powershell
git fetch origin
git switch --track origin/dev
# Edit index.html and save it in VS Code.
git add index.html
git commit -m "Trigger dev deployment"
git push origin dev
```

If you already have a local dev branch, use `git switch dev` instead of `git switch --track origin/dev`.

Check **GitHub -> Actions -> Mission Control - Docker to S3**. All four stages should pass. In your AWS S3 bucket you should now find:

```text
BUCKET/
  dev/index.html                                 <- LIVE S3 WEBSITE PAGE
  images/dev/<GIT_COMMIT_SHA>/Dockerfile         <- BUILD RECIPE
  images/dev/<GIT_COMMIT_SHA>/mission-control-image.tar.gz <- ACTUAL DOCKER IMAGE ARCHIVE
  images/dev/<GIT_COMMIT_SHA>/SHA256SUMS
```

Open the bucket's **Properties -> Static website hosting -> Bucket website endpoint**, append `/dev/`, and verify the site. If the trainer disallows public websites, check the uploaded S3 objects as proof and ask for the approved CloudFront endpoint.

Create and merge PRs in order: **`dev` -> `stage`**, **`stage` -> `uat`**, **`uat` -> `prod`**. The stage and UAT deployments run after their PRs merge. The prod deployment must pause for a configured GitHub reviewer. Your trainer can see each matching S3 folder and the commit-specific image archive. Repeat the site URL check for `/stage/`, `/uat/`, and `/prod/`.

**Do not delete `mission-control-backup` until you have confirmed everything is in GitHub.**

## Troubleshooting / important boundaries

- `Not authorized to perform sts:AssumeRoleWithWebIdentity`: role trust policy, wrong owner/repository IDs or format, GitHub environment restriction, or missing OIDC provider. Have trainer inspect trust.
- `AccessDenied` during `aws s3 cp`: IAM **permissions** policy, bucket policy, SCP, KMS key requirements, or incorrect bucket/Region. A role trust policy alone does **not** grant S3 uploads.
- `Input required and not supplied: role-to-assume`: missing `AWS_ROLE_ARN` environment secret.
- Browser shows `403 AccessDenied`: site public-read policy/Block Public Access or an approved CloudFront configuration, not the Dockerfile.
- Docker image is in S3 but the container is not running in AWS: **expected**. S3 is object storage, not a container runtime. To run that image on AWS, you must load it into a separate runtime or use ECR+ECS/App Runner.
- The S3 image archive and GitHub build artifacts consume storage; review costs and clean them up after the demonstration. Avoid uploading secrets; the app contains only demonstration data.

## Official references

- GitHub OIDC and IAM trust: https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws
- OIDC immutable subjects: https://docs.github.com/en/actions/reference/security/oidc
- GitHub environments and reviewer availability: https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments
- Docker build / save / load: https://docs.docker.com/reference/cli/docker/image/save/ and https://docs.docker.com/reference/cli/docker/image/load/
- S3 website index document: https://docs.aws.amazon.com/AmazonS3/latest/userguide/IndexDocumentSupport.html
- GitHub PR auto-merge: https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/automatically-merging-a-pull-request
