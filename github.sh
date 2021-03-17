#!/bin/bash

_ifs="${IFS}"
orgwd="$(pwd)"

if [ ! -e "${GITHUB_ACTION_PATH}/functions.inc.sh" ]; then
  echo "::error file=${BASH_SOURCE},line=${LINENO}::Unable to locate functions.inc.sh file."
  exit 1
fi

source "${GITHUB_ACTION_PATH}"/functions.inc.sh || {
  echo "::error file=${BASH_SOURCE},line=${LINENO}::Error including functions.inc.sh."
  exit 1
}

if [ -z "${RETYPE_OUTPUT_ROOT}" ]; then
  fail "Retype's output root is not defined. Have you built it using Retype Build Action?"
fi

bldroot="${RETYPE_OUTPUT_ROOT}"
outdir="${bldroot}/output"
targetbranch="${INPUT_BRANCH-retype}"
targetdir="${INPUT_DIRECTORY}"

function wipe_wd() {
  local keepcname=false rootdir rootdirs

  if [ -e CNAME ]; then
    keepcname=true
  fi

  git rm -r --quiet . || fail_nl "unable to git-rm checked out repository."

  if ${keepcname}; then
    git checkout -- CNAME || fail_nl "unable to check out CNAME file after git-rm."
    git reset HEAD -- CNAME || fail_nl "unable to reset CNAME file to previous branch HEAD."
  fi

  IFS=$'\n'
  rootdirs=($(git ls-files --other . | cut -f1 -d/ | sort -u))
  IFS="${_ifs}"

  for rootdir in "${rootdirs[@]}"; do
    git rm -r --quiet "${rootdir}" || fail_nl "unable to remove directory at root: ${rootdir}"
  done
}

if [ "${OSTYPE}" == "msys" ]; then
  # MSYS's git will insist in turning LF files into CRLF.
  # We don't need to touch them.
  git config core.autocrlf false
  git config core.eol native
  git reset --quiet --hard HEAD -- .
  git checkout --quiet -- .
fi

if [ ! -d "${outdir}" ]; then
  echo "::error::In order to locate previously built retype files, a previous step in the same job sould reference the Retype Build Action."
  fail "Unable to locate retype built path: ${outdir}"
fi

echo "Retype built documentation path: ${RETYPE_OUTPUT_ROOT}
Target branch: ${targetbranch}
Target directory: ${targetdir}"

branchname="${targetbranch}"
echo -n "Target branch to publish to: ${branchname}"

echo -n "Fetching remote for existing branches: "
result="$(git fetch 2>&1)" || \
  fail_cmd true "unable to fetch remote repository for existing branches" "git fetch" "${result}"
echo "done."

needpr=false
if [ "${branchname}" == "HEAD" ]; then
  if [ -z "${INPUT_DIRECTORY}" ]; then
    fail "Refusing to deploy the documentation to the root of the branch where documentation source is."
  fi

  echo -n "Cleaning up target directory: "

  if [ -d "./${targetdir}" ]; then
    cd "./${targetdir}"
  elif [ -e "./${targetdir}" ]; then
    fail_nl "target path exists but is not a directory: ${targetdir}"
  else
    mkdir -p "./${targetdir}" || fail_nl "unable to create directory: ${targetdir}"
    cd "./${targetdir}" || fail_nl "unable to change to target dir: ${targetdir}"
  fi

  wipe_wd
  echo "done."
elif git branch --list --remotes --format="%(refname)" | egrep -q "^refs/remotes/origin/${branchname}\$"; then
  echo "Branch '${branchname}' already exists."

  if [ "${INPUT_UPDATE_BRANCH}" == "true" ]; then
    echo -n "Switching to the '${branchname}' branch: "
    update_branch=true
  else
    echo -n "Creating a new branch off '${branchname}': "
    needpr=true
    update_branch=false
  fi

  git checkout --quiet "${branchname}" || fail_nl "unable to checkout the '${branchname}' branch."

  if ! ${update_branch}; then
    branchname="${targetbranch}-${GITHUB_RUN_ID}_${GITHUB_RUN_NUMBER}"

    uniquer=0
    while git branch --list --remotes --format="%(refname)" | egrep -q "^refs/remotes/origin/${branchname}\$"; do
      branchname="${targetbranch}-${GITHUB_RUN_ID}_${GITHUB_RUN_NUMBER}_${uniquer}"
      uniquer=$(( 10#${uniquer} + 1 ))
      if [ ${uniquer} -gt 100 ]; then
        fail_nl "unable to get a non-existing branch name based on '${targetbranch}-${GITHUB_RUN_ID}_${GITHUB_RUN_NUMBER}'."
      fi
    done

    echo -n "${branchname}, "
    git checkout --quiet -b "${branchname}" || fail_nl "unable to switch to new branch '${branchname}'."
  fi
  echo "done."

  echo -n "Cleaning up "

  if [ ! -z "${targetdir}" ]; then
    echo -n "target directory: "
    if [ -d "./${targetdir}" ]; then
      cd "./${targetdir}"
    elif [ -e "./${targetdir}" ]; then
      fail_nl "target path exists but is not a directory: ${targetdir}"
    else
      mkdir -p "./${targetdir}" || fail_nl "unable to create directory: ${targetdir}"
      cd "./${targetdir}" || fail_nl "unable to change to target dir: ${targetdir}"
    fi
  else
    echo -n "branch: "
  fi

  wipe_wd
  echo "done."
else
  echo -n "Creating new, orphan, '${branchname}' branch: "
  git checkout --quiet --orphan "${branchname}" || fail_nl "unable to checkout to a new, orphan branch called '${branchname}'."

  echo -n "cleanup"
  git reset --quiet HEAD -- . || fail_nl "unable to remove original files from staging."

  git clean -x -q -f || fail_nl "unable to clean-up repository from non-website-related files."

  IFS=$'\n'
  rootdirs=($(git ls-files --other | cut -f1 -d/ | sort -u))
  IFS="${_ifs}"

  for rootdir in "${rootdirs[@]}"; do
    git clean -x -q -f "${rootdir}" || fail_nl "unable to clean up root directory: ${rootdir}"
  done

  if [ ! -z "${targetdir}" ]; then
    mkdir -p "./${targetdir}" || fail_nl "unable to create directory: ${targetdir}"
    cd "./${targetdir}" || fail_nl "unable to change to target dir: ${targetdir}"
  fi

  echo ", done."
fi

echo -n "Deploying files: "
result="$(cp -pPR "${outdir}/." . 2>&1)" || \
  fail_cmd true "error copying files from retype output directory: ${outdir}" "cp -pPR \"${outdir}/.\" ." "${result}"
echo "done."

echo -n "Committing files: "
git add . > /dev/null || fail_nl "unable to stage changes in the repository."

git config user.email hello+retype-gitpush@object.net
git config user.name "Retype GitHub Action"

commitmsg="Refreshes Retype-generated documentation.

Process triggered by ${GITHUB_ACTOR}."

cmdln=(git commit --quiet -m "${commitmsg}")

result="$("${cmdln[@]}" 2>&1)" || \
  fail_cmd true "unable to commit changes to repository" "${cmdln[@]}" "${result}"
echo "done."

echo -n "Pushing website to GitHub: "
result="$(git push --quiet origin HEAD 2>&1)" || \
  fail_cmd true "unable to push branch to GitHub" "git push origin HEAD" "${result}"
echo "done."

if [ ! -z "${INPUT_GITHUB_TOKEN}" -a "${needpr}" ]; then
  pr_title="$(echo "${commitmsg}" | head -n1)"
  # body's newlines must be converted to the '\n' string.
  pr_body="$(echo "${commitmsg}" | sed -E ":a; N; \$!ba; s/\n/\\\\n/g")"

  echo -n "Creating request to merge branch '${branchname}' into '${targetbranch}': "
  result="$(curl --silent --include --request POST \
    --header 'accept: application/vnd.github.v3+json' \
    --header 'authorization: Bearer '"${INPUT_GITHUB_TOKEN}" \
    "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/pulls" \
    --data '{
      "head": "'"${branchname}"'",
      "base": "'"${targetbranch}"'",
      "owner": "'"${GITHUB_ACTOR}"'",
      "title": "'"${pr_title}"'",
      "body": "'"${pr_body}"'",
      "maintainer_can_modify": true,
      "draft": false
    }' 2>&1)"
 retstat="${?}"

  if [ ${retstat} -ne 0 ]; then
    echo "failed."
    echo "::warning::Unable to send HTTP request to GitHub to create pull request.
Command output:
${result}
-----
Proceeding without pull request."
  else
    retstat="$(echo "${result}" | head -n 1 | cut -f2 -d" ")"
    if [ "${retstat}" != "201" ]; then
      echo "failed."
      echo "::warning::Non-success return status from GitHub API create-pr request: ${retstat}.
GitHub response:
${result}
-----
Proceeding but pull request was probably not issued."
      pr_number="(unknown)"
    else
      pr_number="$(echo "${result}" | egrep "^  \"number\":" | head -n1 | sed -E "s/^[^:]+: *([0-9]+),.*\$/\1/")"
    fi
  fi

  echo "done, pr #${pr_number}."
fi

echo "Retype GitHub Action finished successfully."