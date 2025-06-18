#!/bin/bash

# Initialize status arrays
declare -a successful_pulls=()
declare -a failed_pulls=()
declare -a rebased_repos=()

# Function to get current branch
get_current_branch() {
  git -C "$1" rev-parse --abbrev-ref HEAD 2>/dev/null
}

# Function to list all branches
list_branches() {
  local repo_path="$1"
  local repo_name="$2"
  echo "Branches for $repo_name:"
  git -C "$repo_path" branch -a | grep -v "HEAD detached" | sed 's/^/  /'
}

# Function to handle fetching and pulling
handle_repo() {
  local repo_path="$1"
  local repo_name="$2"
  local current_branch
  
  current_branch=$(get_current_branch "$repo_path")
  echo "[$repo_name] Current branch: $current_branch"
  
  # Fetch latest changes
  echo "[$repo_name] Fetching latest changes..."
  git -C "$repo_path" fetch --quiet
  
  # Try to pull
  echo "[$repo_name] Attempting to pull latest changes..."
  if git -C "$repo_path" pull --quiet; then
    echo "[$repo_name] Successfully pulled latest changes."
    successful_pulls+=("$repo_name")
  else
    echo "[$repo_name] Pull failed. Changes may conflict with local modifications."
    failed_pulls+=("$repo_name")
    
    # Ask for rebase
    read -p "[$repo_name] Would you like to rebase? (y/n): " answer
    if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
      echo "[$repo_name] Rebasing..."
      if git -C "$repo_path" rebase; then
        echo "[$repo_name] Rebase successful."
        rebased_repos+=("$repo_name")
      else
        echo "[$repo_name] Rebase failed. Please resolve conflicts manually."
        git -C "$repo_path" rebase --abort
        echo "[$repo_name] Rebase aborted."
      fi
    else
      echo "[$repo_name] Skipping rebase."
    fi
  fi
  
  # List branches
  list_branches "$repo_path" "$repo_name"
  echo
}

echo "=== Starting Git Repository Update ==="
echo

# Handle main repository
handle_repo "." "Main repository"

# Handle all submodules recursively
echo "=== Processing Submodules ==="
while read -r path; do
  handle_repo "$path" "Submodule $path"
done < <(git submodule --quiet foreach --recursive 'echo $path')

# Print summary report
echo "=== Update Summary ==="
echo "Repositories successfully pulled (${#successful_pulls[@]}):"
for repo in "${successful_pulls[@]}"; do
  echo "  - $repo"
done

echo
echo "Repositories that needed rebasing (${#rebased_repos[@]}):"
for repo in "${rebased_repos[@]}"; do
  echo "  - $repo"
done

echo
echo "Repositories with failed pulls (${#failed_pulls[@]}):"
for repo in "${failed_pulls[@]}"; do
  echo "  - $repo"
done

echo
echo "=== Update Completed ==="