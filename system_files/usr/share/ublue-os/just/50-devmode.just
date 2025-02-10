
alias devmode := change-edition
# Allows selection of Bluefin LTS editions
change-edition:
    #!/bin/bash

    # Function to display the menu and get user selection using gum
    select_edition() {
    edition=$(gum choose --header "Please select a edition:" "HWE" "GDX" "DX" "Base")

    if [[ -z "$edition" ]]; then # Handle cancelation
        echo "No Edition selected."
        exit 1
    fi

    echo "You have selected edition: $edition"

    # Consider Base as empty string
    if [[ "$edition" == "Base" ]]; then
        edition=""
    fi

    # take edition to lower case
    edition=$(echo "$edition" | tr '[:upper:]' '[:lower:]')

    confirm=$(gum confirm --prompt.bold "Are you sure you want to proceed?")

    if [[ "$confirm" = "true" ]]; then
        echo "Operation cancelled."
        exit 1
    fi

    sudo bootc switch --enforce-container-sigpolicy "ghcr.io/ublue-os/bluefin${edition:+-$edition}:lts"
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to switch boot configuration."
        exit 1
    fi

    # Show a window informing the user that the operation is complete and they will need to reboot, give the option to reboot now or later
    action=$(gum notify --title "Operation Complete" --message "The operation is complete. You will need to reboot your system for the changes to take effect." --actions "Reboot Now" "Reboot Later")

    if [[ "$action" == "Reboot Now" ]]; then
        systemctl reboot
    else
        echo "Please reboot your system later to apply the changes."
    fi
    }

    # Run the function
    select_edition
