# Retype GitHub Pages Action

A GitHub Action to push a website built by [Retype](https://retype.com/) in a previous [`action-build`](https://github.com/retypeapp/action-build) step back to the GitHub repo where it can then be hosted by [GitHub Pages](https://docs.github.com/en/github/working-with-github-pages/getting-started-with-github-pages).

This action includes options to publish by pushing to a `branch` or a `directory`, automatically create a pull request, or deploy directly to GitHub Pages when your repo is configured with Pages **Source: GitHub Actions**.

## Introduction

This action will commit and push back a Retype website to a GitHub repo. The website will have been built during a previous step by using the [retypeapp/action-build](https://github.com/retypeapp/action-build) action.

The following functionality is configurable by this action:

1. Choose where to publish (`publish-to: branch` or `publish-to: pages`)
2. Target a `branch` (branch mode), or
3. Target a `directory` in the repo (branch mode)
4. Configure whether a new branch should be created if it already exists (`update-branch`, branch mode)
5. Configure a GitHub API access token to allow the action to make a Pull Request (`github-token`, branch mode)

## Prerequisites

This action requires the output of the [retypeapp/action-build](https://github.com/retypeapp/action-build) in a previous step of the workflow.

If you are using the new GitHub Pages publishing model (Pages **Source: GitHub Actions**), you must enable it in your repo first:

- **Settings → Pages → Build and deployment → Source: GitHub Actions**

Please see [Getting Started with GitHub Pages](https://docs.github.com/en/github/working-with-github-pages/getting-started-with-github-pages) for details on how to configure GitHub Pages.

## Usage

The following GitHub Actions workflow demonstrates a typical scenario where the action will trigger Retype to build when changes are pushed to the repo. The fresh Retype powered website is then pushed to a `retype` branch which has been set up in the repo settings to host with GitHub Pages.

```yaml
name: Publish Retype powered website to GitHub Pages
on:
  workflow_dispatch:
  push:
    branches:
      - main

jobs:
  publish:
    name: Publish to retype branch

    runs-on: ubuntu-latest

    permissions:
      contents: write

    steps:
      - uses: actions/checkout@v2

      - uses: retypeapp/action-build@latest

      - uses: retypeapp/action-github-pages@latest
        with:
          update-branch: true
```

### Publish using GitHub Pages Source: GitHub Actions

If your repository is configured with **Pages Source: GitHub Actions**, you can deploy without pushing generated files to a branch.

Key differences vs branch publishing:

- Your workflow must grant `pages: write` and `id-token: write` permissions.
- This action will upload a Pages artifact and then deploy it using the official GitHub Pages actions.

```yaml
name: Publish Retype powered website to GitHub Pages (GitHub Actions)
on:
  workflow_dispatch:
  push:
    branches:
      - main

jobs:
  publish:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pages: write
      id-token: write
    environment:
      name: github-pages
      url: ${{ steps.pages.outputs.page_url }}

    steps:
      - uses: actions/checkout@v4

      - uses: retypeapp/action-build@latest

      - id: pages
        uses: retypeapp/action-github-pages@latest
        with:
          publish-to: pages
```

## Outputs

### `page_url`

The deployed GitHub Pages URL. Only set when `publish-to: pages` and `pages-deploy` is not `false`.

### `artifact_id`

The uploaded Pages artifact ID. Only set when `publish-to: pages`.

## Inputs

### `publish-to`

Controls where the Retype output is published.

- **Default:** `branch`
- **Accepts:** `branch` or `pages`

When set to `pages`, the branch-related inputs (`branch`, `directory`, `update-branch`, `github-token`) are ignored.

### `branch`

Specifies the target branch where the Retype output will be merged.

- **Default:** `retype`
- **Accepts:** A string or the `HEAD` keyword. Examples: `gh-pages`, `main`, `website`, `HEAD`

- **If the branch does not exist**: The action will create a new, orphan branch; then copy over the files, commit, and push.
- **If the branch exists:**
  - **And `update-branch` input is not `true`:** The action will fork from that branch into a new uniquely-named branch. The action will then wipe clean the entire branch (or a subdirectory within that branch), then copy over the Retype output files, then commit and push. This branch can then be merged or be used to make a pull request to the target branch. This action can create the pull request, see `github-token` input below.
  - **The `update-branch` input is `true`:** The action will wipe clean the branch (or directory), then copy over the Retype output, commit, and then push to the target branch.
- **The argument is `HEAD` keyword:** `update-branch` is implied `true` and Retype output files will be committed to the current branch. In this scenario, the action will ONLY run if a `directory` has been configured, as it would otherwise result in the replacement of all branch contents with the Retype output.

When wiping a branch or directory, if there is a `CNAME` file in the target directory root, the existing `CNAME` file will be preserved.

If the [`cname`](https://retype.com/configuration/project/) property is configured within your projects `retype.json` file, the `CNAME` file from the Retype build output will be used.

See [Managing a custom domain for your GitHub Pages site](https://docs.github.com/en/github/working-with-github-pages/managing-a-custom-domain-for-your-github-pages-site) for additional details regarding `CNAME` files and configuring a custom domain or sub-domain for web hosting.

If the `HEAD` keyword is used and `.`, `/`, or any path coinciding with the repository root is specified to `directory` input, then the whole repository data will be replaced with the generated documentation. Likewise, if the path passed as input conflicts with any existing path within the repository, it will be wiped clean by the commit, replaced recursively by only the Retype output.

### `directory`

Specifies the root where to place the Retype output files. The path is relative to the repository.

- **Default:** null (root of the repository)
- **Accepts:** A string. Example: `docs`

Using `/` or `.` is equivalent to not specifying an input, as it will be changing to the `.//` and `./.` directories respectively. Use of upper-level directories (`../`) is accepted but may result in files being copied outside the repository, in which case the action might fail due to being outside the repository boundaries.

### `update-branch`

Indicates whether the action should update the target branch instead of creating a unique named branch.

- **Default:** null
- **Accepts:** `true` or `false`

When this option is configured, no pull request will be attempted even if `github-token` is specified.

When `branch: HEAD` input is specified, this setting is assumed `true` as there will not be a reference to fork off (or pull request to) as `HEAD` is not a valid branch name.

### `github-token`

Specifies a GitHub Access Token that enables the action to make a pull request whenever it pushes a new branch forked from the existing target branch. See [Using the GITHUB_TOKEN in a workflow](https://docs.github.com/en/actions/reference/authentication-in-a-workflow#using-the-github_token-in-a-workflow) and [Creating a personal access token](https://docs.github.com/en/github/authenticating-to-github/creating-a-personal-access-token)for more details.

- **Default:** null
- **Accepts:** A string representing a valid GitHub Access Token either for User, Repository, or Action.

The action will never use the access token if (1) the branch does not exist, (2) `update-branch` is configured, or (3) if `branch: HEAD` is specified.

### `pages-path`

Only used when `publish-to: pages`.

- **Default:** `${RETYPE_OUTPUT_PATH}` (set by `retypeapp/action-build`)
- **Accepts:** a string path

### `pages-artifact-name`

Only used when `publish-to: pages`.

- **Default:** `github-pages`
- **Accepts:** a string

### `pages-retention-days`

Only used when `publish-to: pages`.

- **Default:** `1`
- **Accepts:** a number (days)

### `pages-deploy`

Only used when `publish-to: pages`.

- **Default:** `true`
- **Accepts:** `true` or `false`

If set to `false`, the action will only upload the Pages artifact. You can then deploy it in a separate job using `actions/deploy-pages`.

## Examples

The following GitHub Actions workflow will serve as our starting template for most of the samples below.

```yaml
name: Publish Retype powered website to GitHub Pages
on:
  workflow_dispatch:
  push:
    branches:
      - main

jobs:
  publish:
    name: Publish to retype branch

    runs-on: ubuntu-latest

    permissions:
      contents: write

    steps:
      - uses: actions/checkout@v2

      - uses: retypeapp/action-build@latest

      - uses: retypeapp/action-github-pages@latest
        with:
          update-branch: true
```

The `retypeapp/action-build` is a required step before running the `retypeapp/action-github-pages` action.

### Most common setup

```yaml
- uses: retypeapp/action-github-pages@latest
  with:
    branch: retype
    update-branch: true
```

### Push to a custom branch and use the action's own GitHub Token to create a pull request

In this example we will push to a `gh-pages` branch and allow the action to use its own access token to create the pull request whenever the branch exists.

```yaml
- uses: retypeapp/action-github-pages@latest
  with:
    branch: gh-pages
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

#### Rules:

- **Target branch:** `gh-pages`
- **Root directory in branch:** Branch root directory
- **If branch exists:** Fork off `gh-pages` to a branch called `gh-pages-<github.run_id>-<github.run_number>`,
- **Pull request policy:** if it forked off the target branch, then make a pull request from `gh-pages-<github.run_id>-<github.run_number>` into `gh-pages`

Regarding pull requests, the first time the action runs will probably be the only time a new `gh-pages` branch will be pushed. Starting from the second time and onwards, the branch already exist and a pull request would be created by the action.

GitHub Pages is not automatically configured by the action pushing to the `gh-pages` branch. GitHub Pages must be manually enabled and configured from the repository settings. Please see [Configuring a publishing source for your GitHub Pages site](https://docs.github.com/en/github/working-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site) for more details.

### Send to `main` branch within `docs` folder

This example assumes GitHub Pages was configured to serve pages from the `docs` folder from within the root of the `main`.

```yaml
- uses: retypeapp/action-github-pages@latest
  with:
    branch: main
    directory: docs
```

#### Rules:

- **Target branch:** `main`
- **Root directory in branch:** Branch root directory
- **If branch exists:** Fork off `main` to a branch called `main-<github.run_id>-<github.run_number>`,
- **Pull request policy:** Given the `main` branch always exist, it will always make a pull request from `main--<github.run_id>-<github.run_number>` into `main` when triggered

In this context, one would probably prefer that the action to be triggered on pushes/merges to the `main` branch only, thus the action file would rather be configured like the following:

```yaml
name: GitHub Action for Retype
on:
  push:
    branches:
      - main
jobs:
  job1:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v2

      - uses: retypeapp/action-build@latest

      - uses: retypeapp/action-github-pages@latest
        with:
          branch: main
          directory: docs
```

In this case, if the `branch: HEAD` argument is used, although it would always push to `main` as intended, it would always update the branch directly instead of making a pull request.

### Update GitHub Pages on new release

In the following sample, we configure that whenever a new Release is created in the GitHub repo, update the documentation to the `retype` branch. If GitHub Pages has been configured to host from the `retype` branch, within a few moments the live website will be updated.

```yaml
name: Publish Retype powered website on a new release
on:
  release:
    types: [ published ]

jobs:
  publish:
    name: Assemble and publish docs
    runs-on: ubuntu-latest
    permissions:
      contents: write

    steps:
      - uses: actions/checkout@v2

      - uses: retypeapp/action-build@latest

      - uses: retypeapp/action-github-pages@latest
        with:
          branch: retype
          update-branch: true
```

#### Rules:

- **Target branch:** `retype`
- **Root directory in branch:** Branch root directory
- **If branch exists:** Make changes directly to the branch
- **Pull request policy:** Never create a pull request and will push branch with modifications directly to GitHub

See [Managing Releases in a Repository](https://docs.github.com/en/github/administering-a-repository/managing-releases-in-a-repository) for additional details.
