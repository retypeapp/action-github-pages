# Retype APP GitHub Actions (RAGHA) - GitHub

GitHub action to push built Retype documentation websites back to GitHub and optionally create a pull request.

## Introduction

This action will commit and push back Retype documentation previously assembled by the **Retype Build Action**. It is possible to specify the target branch (`branch`), top-level directory (relative to the repository, `directory`), whether a new branch should be created if it already exists (`update-branch`), and a github API access token to allow the action to also make pull request to the specified branch when needed (`github-token`).

## Prerequisites

This action should only be called in the same job the **Retype Build Action** run. In other words it should be another step in a same job the **Retype Build Action** is in. And this action should be a step run **after** the build one.

For the target branch or branch-directory to actually serve the pages, the GitHub Pages feature should be available and configured accordingly to your repository. Read more at https://docs.github.com/en/github/working-with-github-pages/getting-started-with-github-pages.

## Inputs

### `branch`

Specifies a target branch to push the documentation to.

If **the branch does not exist**, will create a new, orphan branch, copy over the files, commit and push.

If **the branch exists** and `update-branch` input (see below) **is not specified or is specified as something other than** `true`, the action will fork from it into a new, non-conflicting branch. It will then wipe clean the branch (or branch's subdirectory) and copy over the Retype output files, commit and push. This branch can then be merged or used as pull request to the target branch (see `github-token` input below).

Similar to above, if **the branch exists** but `update-branch` **is** `true`, the action will wipe clean the branch (or directory), copy over Retype output files, commit and push, updating the target branch.

If the argument is the `HEAD` keyword, `update-branch` is implied `true` and the generated documentation will be committed to the current branch. The action will fail if no `directory` input is specified.

- **Default:** `retype`
- **Accepts:** A string or the `HEAD` keyword. (`gh-pages`, `main`, `website`, `HEAD`)

**Note:** When wiping a branch or directory, if there is a **CNAME** file in the top-level location it is handling, the file will be preserved. This is useful when you have a GitHub Pages enabled repository and use a custom host redirection in it. In case Retype output has the file, it will be overwritten (Retype output takes precedence).

**Note:** If the `HEAD` keyword is used here and `.`, `/`, or any path coinciding with the repository root is specified to `directory` input, then the whole repository data will be replaced with the generated documentation. Likewise, if the path passed as input conflicts with any existing path within the repository, it will be wiped clean by the commit, replaced recursively by only and only the Retype output files.

### `directory`

Specifies a root directory, relative to the repository, where to place the Retype output files in.

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

Specifies a GitHub Access Token that enables the action to make pull request whenever it pushes a new branch forked from the (existing) target branch. Read more about using and passing GitHub Access Tokens to actions at https://docs.github.com/en/actions/reference/authentication-in-a-workflow#using-the-github_token-in-a-workflow.

- **Default:** empty
- **Accepts:** A string representing a valid GitHub Access Token either for User, Repository, or Action.

**Note:** The action will never use the access token either if the branch does not exist or if `update-branch` is in effect.

**Note:** When `branch: HEAD` no pull request will be possible and this input will be ignored, as there will be no reference of an actual target branch to send pull requests to.

## Examples

For most examples below we will assume this workflow context:

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
- uses: retypeapp/action-github
```

This will simply use the defaults, which are:
- **target branch: retype**
- **root directory in branch:** branch's root directory
- **if branch exists:** fork off to a branch called **retype-_<github.run_id>_-_<github.run_number>_** (see [github context](https://docs.github.com/en/actions/reference/context-and-expression-syntax-for-github-actions#github-context) for placeholders meaning),
- **pull request policy:** never create pull requests

### Push to a custom branch and use action's own GitHub Token to create pull requests

In this example we'll push to the **gh-pages** and allow the action to use its own access token to create the pull request whenever the branch exists.

```yaml
- uses: retypeapp/action-github
  with:
    branch: gh-pages
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

Now, the rules will be:
- **target branch: gh-pages**
- **root directory in branch:** branch's root directory
- **if branch exists:** fork off **gh-pages** to a branch called **gh-pages-_<github.run_id>_-_<github.run_number>_** (see [github context](https://docs.github.com/en/actions/reference/context-and-expression-syntax-for-github-actions#github-context) for placeholders meaning),
- **pull request policy:** if it forked off the target branch, then make a pull request from **gh-pages-<github.run_id>-<github.run_number>** into **gh-pages**

**Note:** Regarding pull requests, the first time the action runs will probably be the only time the **gh-pages** branch does not exist. So from the second time onwards, where the branch will already be in the repository, pull requests should be created.

**Note:** Just pushing the **gh-pages** branch from an action won't automatically enable the GitHub Pages feature
 to the repository as it does when a repository admin pushes it. The feature must be manually enabled from the repository settings.

### Place documentation to `main` branch within `docs` folder

This example assumes GitHub Pages was configured to serve pages in the **main** branch, under the **docs/** subfolder.

```yaml
- uses: retypeapp/action-github
  with:
    branch: main
    directory: docs
```

Now, the rules will be:
- **target branch: main**
- **root directory in branch:** branch's root directory
- **if branch exists:** fork off **main** to a branch called **main-_<github.run_id>_-_<github.run_number>_**,
- **pull request policy:** given the **main** branch always exist, it will always make a pull request from **main-<github.run_id>-<github.run_number>** into **main** when triggered

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

      - uses: retypeapp/action-github
        with:
          branch: main
          directory: docs
```

**Note:** In this case if the `branch: HEAD` argument is used, although it would always push to **main** as intended, it would always update the branch directly instead of making pull requests.

### Update GitHub Pages on release

The following example will take a full YAML example as it depends on a different context. Here we want, whenever a new release is created in GitHub, to update the documentation to the **gh-pages** branch which will, in turn, refresh the documentation website configured (hypothetically) for that repo.

```yaml
name: Publish documentation on Release
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

      - uses: retypeapp/action-github
        with:
          branch: gh-pages
          update-branch: true
```

Rules will be:
- **target branch: gh-pages**
- **root directory in branch:** branch's root directory
- **if branch exists:** make changes directly to the branch
- **pull request policy:** never create pull requests; will push branch with modifications directly to GitHub

So in this case, the documentation should be fully updated once a Release is created in GitHub. See more about GitHub releases here: https://docs.github.com/en/github/administering-a-repository/managing-releases-in-a-repository
