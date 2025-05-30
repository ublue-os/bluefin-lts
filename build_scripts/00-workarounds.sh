#!/bin/bash

set -xeuo pipefail

# This is a bucket list. We want to not have anything in this file at all.

# Enable the same compose repos during our build that the centos-bootc image
# uses during its build.  This avoids downgrading packages in the image that
# have strict NVR requirements.
# curl --retry 3 -Lo "/etc/yum.repos.d/compose.repo" "https://gitlab.com/redhat/centos-stream/containers/bootc/-/raw/c${MAJOR_VERSION_NUMBER}s/cs.repo"
# sed -i \
# 	-e "s@- (BaseOS|AppStream)@& - Compose@" \
# 	-e "s@\(baseos\|appstream\)@&-compose@" \
# 	/etc/yum.repos.d/compose.repo
# cat /etc/yum.repos.d/compose.repo


dnf() {
    # Intercept 'dnf config-manager --set-disabled REPO [REPO...]'
    if [[ "$1" == "config-manager" && \
          "$2" == "--set-disabled" && \
          -n "$3" ]]; then # Check if $3 (first repo name) is non-empty
        
        local repos_to_process=()
        local opts_to_set=()
        local display_repo_names=()
        # Arguments from $3 onwards are potential repository names
        local potential_repos=("${@:3}") 

        if [[ ${#potential_repos[@]} -eq 0 ]]; then
             echo "--- Custom DNF Interceptor ---"
             echo "No repository specified after '--set-disabled'."
             command dnf "$@" 
             return $?
        fi

        for repo_arg in "${potential_repos[@]}"; do
            local repo_name="$repo_arg"
            repo_name="${repo_name#\"}"; repo_name="${repo_name%\"}"
            repo_name="${repo_name#\'}"; repo_name="${repo_name%\'}"
            
            if [[ -n "$repo_name" ]]; then
                repos_to_process+=("$repo_name")
                opts_to_set+=("${repo_name}.enabled=0")
                display_repo_names+=("'$repo_name'")
            fi
        done

        if [[ ${#repos_to_process[@]} -eq 0 ]]; then
             echo "--- Custom DNF Interceptor ---"
             echo "No valid repository names found after '--set-disabled'."
             command dnf "$@" 
             return $?
        fi

        echo "--- Custom DNF Interceptor ---"
        echo "You typed: dnf config-manager --set-disabled ${potential_repos[*]}"
        echo "Executing transformed command:"
        echo "  sudo command dnf config-manager setopt ${opts_to_set[*]}"
        echo "For repositories: ${display_repo_names[*]}"
        echo "------------------------------"
        
        sudo command dnf config-manager setopt "${opts_to_set[@]}"
        local exit_status=$?
        if [[ $exit_status -eq 0 ]]; then
            echo "Successfully executed: Repositories ${display_repo_names[*]} should now have enabled=0."
        else
            echo "The dnf command failed with exit status $exit_status."
        fi
        return $exit_status

    # Intercept 'dnf config-manager --add-repo="URL"'
    elif [[ "$1" == "config-manager" && "$2" == --add-repo=* ]]; then
        local repo_url_arg_full="$2" 
        local repo_url_value="${repo_url_arg_full#--add-repo=}"

        local repo_url
        if [[ "${repo_url_value:0:1}" == "\"" && "${repo_url_value: -1}" == "\"" ]] || \
           [[ "${repo_url_value:0:1}" == "'" && "${repo_url_value: -1}" == "'" ]]; then
            repo_url="${repo_url_value:1:${#repo_url_value}-2}"
        else
            repo_url="$repo_url_value"
        fi

        if [[ -z "$repo_url" ]]; then
            echo "--- Custom DNF Interceptor ---"
            echo "Error: No URL found in '$repo_url_arg_full'."
            echo "Expected format: --add-repo=\"<URL>\" or --add-repo=<URL>"
            return 1
        fi

        local remaining_args_for_display=()
        if [[ -n "$3" ]]; then 
            remaining_args_for_display=("${@:3}")
        fi
        
        echo "--- Custom DNF Interceptor ---"
        if [[ ${#remaining_args_for_display[@]} -gt 0 ]]; then
            echo "You typed: dnf $1 $repo_url_arg_full ${remaining_args_for_display[*]}"
            echo "Warning: Additional arguments (${remaining_args_for_display[*]}) after '$repo_url_arg_full' are being ignored by this specific transformation."
        else
            echo "You typed: dnf $1 $repo_url_arg_full"
        fi
        echo "Executing transformed command:"
        echo "  sudo command dnf config-manager addrepo \"$repo_url\""
        echo "------------------------------"

        sudo command dnf config-manager addrepo "$repo_url"
        local exit_status=$?
        if [[ $exit_status -eq 0 ]]; then
            echo "Successfully executed: Repository from '$repo_url' should now be added."
        else
            echo "The dnf command 'addrepo $repo_url' failed with exit status $exit_status."
        fi
        return $exit_status
    
    # Fallback for all other 'dnf' commands
    else
        command dnf "$@"
        return $?
    fi
}



mkdir -p /var/roothome
chmod 0700 /var/roothome
