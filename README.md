# Retype APP GitHub Actions - GitHub Pages

GitHub action to push built Retype documentation websites back to GitHub and optionally create a pull request. Basically allows publishing fresh documentation to your preferred GitHub pages destination.

## Introduction

This action will commit and push back Retype documentation previously assembled by the **Retype Build Action** step. It is possible to specify the target branch (`branch`), top-level directory (relative to the repository, `directory`), whether a new branch should be created if it already exists (`update-branch`), and a github API access token to allow the action to also make pull request to the specified branch when needed (`github-token`).

See Retype documentation at [Retype WebSite](https://retype.com/).

See Retype Build Action at [retypeapp/action-build](https://github.com/retypeapp/action-build).

## Prerequisites

This action expects documentation is already built by the **Retype Build Action** in a previous step, so make sure to include it in your job steps.

For the target branch or branch-directory to actually publish the documentation website, the GitHub Pages feature should be available and configured in the repository settings. See [Getting Started with GitHub Pages at GitHub docs](https://docs.github.com/en/github/working-with-github-pages/getting-started-with-github-pages).

**Note:** Read the Retype Build Action documentation for an explanation as to why the actions/setup-dotnet is a recommended step before build. See Retype Build Action at [retypeapp/action-build](https://github.com/retypeapp/action-build).

## Usage

```yaml
- uses: actions/checkout@v2

- uses: actions/setup-dotnet@v1
  with:
    dotnet-version: 5.0.x

- uses: retypeapp/action-build@v1

- uses: retypeapp/action-github-pages@v1
```

## Inputs

### `branch`

Specifies the target branch where Retype output files should be merged to.

- **If the branch does not exist**: the action will create a new, orphan branch; then copy over the files, commit and push.
- **If the branch exists:**
  - **And `update-branch` input is not specified or not `true`:** the action will fork from that branch into a new, uniquely-named one. It will then wipe clean the whole branch (or a subdirectory within that branch) and copy over the Retype output files; then commit and push. This branch can then be merged or be used to make a pull request to the target branch (this action can create the pull request, see `github-token` input below).
  - **The `update-branch` input is `true`:** the action will wipe clean the branch (or directory), copy over Retype output files, commit and push, updating the target branch.
- **The argument is the `HEAD` keyword:** `update-branch` is implied `true` and Retype output files will be committed to the current branch. The action won't run if no `directory` input is specified, as it would mean replacing all branch contents with the output files.

- **Default:** `retype`
- **Accepts:** A string or the `HEAD` keyword. (`gh-pages`, `main`, `website`, `HEAD`)

**Note:** When wiping a branch or directory, if there is a **CNAME** file in the target directory's root, it will be preserved. In case Retype output has the file, it will be overwritten (Retype output takes precedence). See about this file in [Managing a custom domain for your GitHub Pages site at GitHub docs](https://docs.github.com/en/github/working-with-github-pages/managing-a-custom-domain-for-your-github-pages-site).

**Note:** If the `HEAD` keyword is used and `.`, `/`, or any path coinciding with the repository root is specified to `directory` input, then the whole repository data will be replaced with the generated documentation. Likewise, if the path passed as input conflicts with any existing path within the repository, it will be wiped clean by the commit, replaced recursively by only and only the Retype output files.

### `directory`

Specifies the root, relative to the repository path, where to place the Retype output files in.

- **Default:** empty (root of the repository)
- **Accepts:** A string. (`/docs`, `a_directory/documentation`)

**Note:** Using `/` or `.` is equivalent not to specify any input, as it will be changing to the `.//` and `./.` directories, respectively. Use upper-level directories (`../`) is accepted but may result in files being copied outside the repository, in which case the action might fail due to no files to commit within the repository boundaries.

### `update-branch`

Indicates whether the action should update the target branch instead of forking off it before wipe+commit+push.

- **Default:** empty
- **Accepts:** A boolean. (`true`, any other value is equivalent to empty/unspecified)

**Note:** When this option is in effect, no pull request will be attempted even if `github-token` is specified.

**Note:** When `branch: HEAD` input is specified, this setting is assumed `true` as there won't be a reference to fork off (or pull request to) as `HEAD` is not a valid branch name.

### `github-token`

Specifies a GitHub Access Token that enables the action to make pull request whenever it pushes a new branch forked from the (existing) target branch. See [Using the GITHUB_TOKEN in a workflow at GitHub docs](https://docs.github.com/en/actions/reference/authentication-in-a-workflow#using-the-github_token-in-a-workflow).

- **Default:** empty
- **Accepts:** A string representing a valid GitHub Access Token either for User, Repository, or Action. See [Using the GITHUB_TOKEN in a workflow at GitHub docs](https://docs.github.com/en/actions/reference/authentication-in-a-workflow#using-the-github_token-in-a-workflow) and [Creating a personal access token at GitHub docs](https://docs.github.com/en/github/authenticating-to-github/creating-a-personal-access-token).

**Note:** The action will never use the access token if (1) the branch does not exist, (2) `update-branch` is in effect or (3) if `branch: HEAD` is specified.

## Examples

For most examples below the following workflow file will be considered:

```yaml
name: document
on: push
jobs:
  job1:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2

      - uses: actions/setup-dotnet@v1
        with:
          dotnet-version: 5.0.x

      - uses: retypeapp/action-build
```

### Push to the `retype` branch's root

```yaml
- uses: retypeapp/action-github-pages
```

This will simply use the defaults, which are:
- **target branch: retype**
- **root directory in branch:** branch's root directory
- **if branch exists:** fork off to a branch called **retype-_<github.run_id>_-_<github.run_number>_** (see [github context at GitHub docs](https://docs.github.com/en/actions/reference/context-and-expression-syntax-for-github-actions#github-context) for placeholders meaning),
- **pull request policy:** never create pull requests

### Push to a custom branch and use action's own GitHub Token to create pull requests

In this example we'll push to the **gh-pages** and allow the action to use its own access token to create the pull request whenever the branch exists.

```yaml
- uses: retypeapp/action-github-pages
  with:
    branch: gh-pages
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

Now, the rules will be:
- **target branch: gh-pages**
- **root directory in branch:** branch's root directory
- **if branch exists:** fork off **gh-pages** to a branch called **gh-pages-_<github.run_id>_-_<github.run_number>_**,
- **pull request policy:** if it forked off the target branch, then make a pull request from **gh-pages-_<github.run_id>_-_<github.run_number>_** into **gh-pages**

**Note:** Regarding pull requests, the first time the action runs will probably be the only time the **gh-pages** branch will be pushed anew. From the second time onwards, where the branch will already exist, pull requests would be created by the action.

**Note:** Just pushing the **gh-pages** branch from an action won't automatically enable the GitHub Pages feature
 to the repository as it does when a repository admin pushes it. The feature must be manually enabled from the repository settings. See [Configuring a publishing source for your GitHub Pages site at GitHub docs](https://docs.github.com/en/github/working-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site).

### Place documentation to `main` branch within `docs` folder

This example assumes GitHub Pages was configured to serve pages in the **main** branch, under the **docs/** subfolder.

```yaml
- uses: retypeapp/action-github-pages
  with:
    branch: main
    directory: docs
```

Now, the rules will be:
- **target branch: main**
- **root directory in branch:** branch's root directory
- **if branch exists:** fork off **main** to a branch called **main-_<github.run_id>_-_<github.run_number>_**,
- **pull request policy:** given the **main** branch always exist, it will always make a pull request from **main--_<github.run_id>_-_<github.run_number>_** into **main** when triggered

**Note:** In this context, one would probably prefer that the Action be triggered on pushes/merges to the **main** branch only, thus the action file would rather look like this:

```yaml
name: document
on:
  push:
    branches:
      - main
jobs:
  job1:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2

      - uses: actions/setup-dotnet@v1
        with:
          dotnet-version: 5.0.x

      - uses: retypeapp/action-build

      - uses: retypeapp/action-github-pages
        with:
          branch: main
          directory: docs
```

**Note:** In this case if the `branch: HEAD` argument is used, although it would always push to **main** as intended, it would always update the branch directly instead of making pull requests.

### Update GitHub Pages on New Release

The following example will take a full YAML example as it depends on a different context. Here we want, whenever a new release is created in GitHub, to update the documentation to the **gh-pages** branch which will, in turn, refresh the documentation website configured (hypothetically) for that repo.

```yaml
name: Publish documentation on New Release
on:
  release:
    types: [ published ]

jobs:
  publish:
    name: Assemble and publish docs
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v2

      - uses: actions/setup-dotnet@v1
        with:
          dotnet-version: 5.0.x

      - uses: retypeapp/action-build

      - uses: retypeapp/action-github-pages
        with:
          branch: gh-pages
          update-branch: true
```

Rules will be:
- **target branch: gh-pages**
- **root directory in branch:** branch's root directory
- **if branch exists:** make changes directly to the branch
- **pull request policy:** never create pull requests; will push branch with modifications directly to GitHub

So in this case, the documentation should be fully updated once a Release is created in GitHub. See [Managing Releases in a Repository at GitHub docs](https://docs.github.com/en/github/administering-a-repository/managing-releases-in-a-repository).
