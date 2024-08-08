#!/usr/bin/env bash
set -e

cd /home/sketu/rising

primary_repo_url="https://github.com/RisingOSS-devices/android_device_${BRAND}_${CODENAME}.git"
fallback_repo_url="https://github.com/LineageOS/android_device_${BRAND}_${CODENAME}.git"

function repo_exists {
  local repo_url=$1
  git ls-remote --exit-code "$repo_url" &> /dev/null
  return $?
}

function find_repo {
  local repo_name=$1
  local orgs=("RisingOSS-devices" "LineageOS")
  
  for org in "${orgs[@]}"; do
    local repo_url="https://github.com/$org/$repo_name.git"
    if repo_exists "$repo_url"; then
      echo "$repo_url"
      return
    fi
  done
  
  echo ""
}

function clone_and_check_dependencies {
  local repo_url=$1
  local dest_dir=$2

  if [[ -d "$dest_dir" ]]; then
    rm -rf "$dest_dir"
  fi

  git clone "$repo_url" --depth=1 "$dest_dir" || {
    echo "Error: Failed to clone the repository $repo_url."
    exit 1
  }

  if [[ -f "$dest_dir/vendorsetup.sh" ]]; then
    echo "Error: vendorsetup.sh found in $dest_dir. Please remove it and add to rising.dependencies."
    exit 1
  fi

  local dependencies_file
  if [[ -f "$dest_dir/rising.dependencies" ]]; then
    dependencies_file="$dest_dir/rising.dependencies"
  elif [[ -f "$dest_dir/lineage.dependencies" ]]; then
    dependencies_file="$dest_dir/lineage.dependencies"
  else
    return 0
  fi

  echo "Found dependencies file: $dependencies_file"
  jq -c '.[]' "$dependencies_file" | while read -r dependency; do
    local dependency_repository=$(echo "$dependency" | jq -r '.repository')
    local dependency_branch=$(echo "$dependency" | jq -r '.branch // "fourteen"')
    local dependency_target_path=$(echo "$dependency" | jq -r '.target_path')
    local dependency_url

    if [[ "$dependency_repository" =~ ^https?:// ]]; then
      dependency_url="$dependency_repository"
    else
      local remote_name=$(echo "$dependency" | jq -r '.remote // empty')
      if [[ -n "$remote_name" ]]; then
        dependency_url="https://github.com/$dependency_repository.git"
      else
        dependency_url=$(find_repo "$dependency_repository")
        
        if [[ -z "$dependency_url" ]]; then
          echo "Error: Repository $dependency_repository not found in RisingOSS-devices or LineageOS."
          continue
        fi
      fi
    fi

    if ! clone_and_check_dependencies "$dependency_url" "$dependency_target_path"; then
      echo "Warning: Failed to clone dependency $dependency_url. Continuing with next dependency."
    fi
  done
}

if repo_exists "$primary_repo_url"; then
  clone_and_check_dependencies "$primary_repo_url" "device/$BRAND/$CODENAME"
else
  echo "Warning: Device tree not found in RisingOSS-devices ($primary_repo_url). Cloning from LineageOS."
  if repo_exists "$fallback_repo_url"; then
    clone_and_check_dependencies "$fallback_repo_url" "device/$BRAND/$CODENAME"
  else
    echo "Error: Neither the primary nor fallback repository exists."
    exit 1
  fi
fi

echo "Setup completed successfully."