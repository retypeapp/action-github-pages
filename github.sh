#!/bin/bash

_ifs="${IFS}"
orgwd="$(pwd)"
configjs_path="resources/js/config.js"
configjs_varname="__DOCS_CONFIG__"

if [ ! -e "${GITHUB_ACTION_PATH}/functions.inc.sh" ]; then
  echo "::error file=${BASH_SOURCE},line=${LINENO}::Unable to locate functions.inc.sh file."
  exit 1
fi

source "${GITHUB_ACTION_PATH}"/functions.inc.sh || {
  echo "::error file=${BASH_SOURCE},line=${LINENO}::Error including functions.inc.sh."
  exit 1
}

if [ -z "${RETYPE_OUTPUT_PATH}" ]; then
  fail "Retype's output path is not defined. Have you built it using Retype Build Action?"
fi

bldroot="${RETYPE_OUTPUT_PATH}"
outdir="${bldroot}"

if [ -z "${INPUT_BRANCH}" ]; then
  targetbranch="retype"
else
  targetbranch="${INPUT_BRANCH}"
fi

targetdir="${INPUT_DIRECTORY}"
if [ -z "${INPUT_DIRECTORY}" ]; then
  targetdir="."
else
  targetdir="${INPUT_DIRECTORY}"
  while [ "${targetdir: -1}" == "/" ]; do
    targetdir="${targetdir::-1}"
  done

  # in case INPUT_DIRECTORY contains only / characters.
  if [ -z "${targetdir}" ]; then
    targetdir="."
  fi
fi

# If current working directory is not repository root, git-rm will erase it.
function ensure_wd() {
  if [ ! -d "$(pwd)" ]; then
    mkdir -p "$(pwd)" || fail_nl "unable to re-create current working directory after git-rm cleanup."

    # in linux and darwin, when the directory is re-created it will likely lie under a
    # different filesystem entry, so it is necessary to move again within it.
    cd "$(pwd)" || fail_nl "unable to chdir to re-created working directory."
  fi
}

function get_config_id() {
  local id

  if [ -e "${configjs_path}" ]; then
    id="$(cat << EOF | node 2>&1
$(cat "${configjs_path}")
console.log(${configjs_varname}.id);
EOF
)" || return 1

   echo "${id}"
  fi
}

function replace_config_id() {
  local new_id="${1}" escaped_nid
  local current_id

  if [ ! -z "${new_id}" -a -e "${configjs_path}" ]; then
    current_id="$(get_config_id)"

    if [ "${current_id}" != "${new_id}" ]; then
      escaped_nid="${new_id//\"/\\\"}"

      echo "$(cut -f1 -d\{ "${configjs_path}")$(cat << EOF | node --require=fs 2>&1
$(cat "${configjs_path}")
${configjs_varname}.id = "${escaped_nid}";
console.log(JSON.stringify(${configjs_varname}) + ";");
EOF
      )" > "${configjs_path}" || return 1
      echo "${current_id}"
    fi

    return 0
  fi

  return 1
}

function wipe_wd() {
  local keepcname=false rootdir rootdirs

  if [ -e CNAME ]; then
    keepcname=true
  fi

  git rm -r --quiet . || fail_nl "unable to git-rm checked out repository."
  ensure_wd

  if ${keepcname}; then
    git reset HEAD -- CNAME || fail_nl "unable to reset CNAME file to previous branch HEAD."
    git checkout -- CNAME || fail_nl "unable to check out CNAME file after git-rm."
  fi

  IFS=$'\n'
  rootdirs=($(git ls-files --other . | cut -f1 -d/ | sort -u))
  IFS="${_ifs}"

  for rootdir in "${rootdirs[@]}"; do
    git rm -r --quiet "${rootdir}" || fail_nl "unable to remove directory at root: ${rootdir}"
  done
  ensure_wd
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

echo "Retype built documentation path: ${RETYPE_OUTPUT_PATH}
Target branch: ${targetbranch}
Target directory: ${targetdir}/"

# We assign the name here because 'branchname' will point to the temporary
# branch if we need to fork off the target one.
branchname="${targetbranch}"
echo -n "Fetching remote for existing branches: "
result="$(git fetch 2>&1)" || \
  fail_cmd true "unable to fetch remote repository for existing branches" "git fetch" "${result}"
echo "done."

needpr=false
config_id=""
if [ "${branchname}" == "HEAD" ]; then
  if [ -z "${INPUT_DIRECTORY}" ]; then
    fail "Refusing to deploy the documentation to the root of the branch where documentation source is."
  fi

  echo -n "Cleaning up target directory: "

  if [ -d "./${targetdir}" ]; then
    cd "./${targetdir}"

    config_id="$(get_config_id)" || fail_nl "unexpected error trying to get config ID from '${configjs_path}'."
    if [ ! -z "${config_id}" ]; then
      echo -n "found config.js's ID, "
    fi

    wipe_wd
  elif [ -e "./${targetdir}" ]; then
    fail_nl "target path exists but is not a directory: ${targetdir}"
  else
    mkdir -p "./${targetdir}" || fail_nl "unable to create directory: ${targetdir}"
    cd "./${targetdir}" || fail_nl "unable to change to target dir: ${targetdir}"
  fi

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

  # explicitly using -B <branch> and --track origin/<branch> ensures no
  # ambiguity when a local path matches the branch name.
  git checkout --quiet -B "${branchname}" --track origin/"${branchname}" || fail_nl "unable to checkout the '${branchname}' branch."

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
    # this should _always_ be a new branch off the current one, thus -b.
    git checkout --quiet -b "${branchname}" || fail_nl "unable to switch to new branch '${branchname}'."
  fi
  echo "done."

  echo -n "Cleaning up "

  existing_dir=true
  if [ ! -z "${INPUT_DIRECTORY}" ]; then
    echo -n "target directory: "
    if [ -d "./${targetdir}" ]; then
      cd "./${targetdir}"
    elif [ -e "./${targetdir}" ]; then
      fail_nl "target path exists but is not a directory: ${targetdir}"
    else
      mkdir -p "./${targetdir}" || fail_nl "unable to create directory: ${targetdir}"
      cd "./${targetdir}" || fail_nl "unable to change to target dir: ${targetdir}"
      existing_dir=false
    fi
  else
    echo -n "branch: "
  fi

  if ${existing_dir}; then
    config_id="$(get_config_id)" || fail_nl "unexpected error trying to get config ID from '${configjs_path}'."
    if [ ! -z "${config_id}" ]; then
      echo -n "found config.js's ID, "
    fi

    wipe_wd
  fi

  echo "done."
else
  echo -n "Creating new, orphan, '${branchname}' branch: "
  git checkout --quiet --orphan "${branchname}" || fail_nl "unable to checkout to a new, orphan branch called '${branchname}'."

  echo -n "cleanup"
  git reset --quiet HEAD -- . || fail_nl "unable to remove original files from staging."

  git clean -d -x -q -f || fail_nl "unable to clean-up repository from non-website-related files."

  IFS=$'\n'
  rootdirs=($(git ls-files --other | cut -f1 -d/ | sort -u))
  IFS="${_ifs}"

  for rootdir in "${rootdirs[@]}"; do
    git clean -d -x -q -f "${rootdir}" || fail_nl "unable to clean up root directory: ${rootdir}"
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

echo -n "Staging deployed files for commit: "
git add . > /dev/null 2>&1 || fail_nl "unable to stage changes in the repository."
echo "done."

echo -n "Checking for changes in repository: "
result="$(git status --porcelain . 2>&1)"

if [ "${#result}" -eq 0 ]; then
  echo "no change.
No changes in working directory after documentation deploy."
  exit 0
fi

# Check if the only change is config.js's random ID.
if [ ! -z "${config_id}" -a \
    $(echo "${result}" | wc -l) -eq 1 -a \
    "${result: -${#configjs_path}}" == "${configjs_path}" ]; then
  new_cid="$(replace_config_id "${config_id}")" || \
    fail_nl "unexpected error while trying to fetch new ID from '${configjs_path}'."

  git add "${configjs_path}" > /dev/null 2>&1 || \
    fail_nl "unable to stage '${configjs_path}' while checking for changes in repository."

  if [ -z "$(git status --porcelain . 2>&1)" ]; then
    echo "config.js ID change only.
The only change in repository is the '${configjs_path}' file's id. Ignoring it."
    exit 0
  else
    temp="$(replace_config_id "${new_cid}")" || \
      fail_nl "unexpected error while trying revert ID change in '${configjs_path}'."
    git add "${configjs_path}" > /dev/null 2>&1 || \
      fail_nl "unable to stage config.js while reverting changes to it."
  fi
fi
echo "changes found."

echo -n "Committing files: "
git config user.email retype@object.net
git config user.name "Retype GitHub Action"

commitmsg="Refreshes Retype-generated documentation.

Process triggered by ${GITHUB_ACTOR}."
cmdln=(git commit --quiet -m "${commitmsg}")
result="$("${cmdln[@]}" 2>&1)" || \
  fail_cmd true "unable to commit changes to repository" "${cmdln[@]}" "${result}"
echo "done."

echo -n "Pushing '${branchname}' branch back to GitHub: "
result="$(git push --quiet origin HEAD 2>&1)" || \
  fail_cmd true "unable to push the '${branchname}' branch back to GitHub" "git push origin HEAD" "${result}"
echo "done."

if [ ! -z "${INPUT_GITHUB_TOKEN}" -a "${needpr}" == "true" ]; then
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