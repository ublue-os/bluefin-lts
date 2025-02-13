alias toggle-devmode := change-image
alias rebase-helper := change-image

# Allows selection of Bluefin LTS images
change-image:
    #!/bin/bash

    # Function to display the menu and get user selection using gum
    select_image() {
    image=$(gum choose --header "Please select a image:" "lts-DX" "lts-HWE" "lts-GDX" "lts-$(date +%Y%m%d)")

    if [[ -z "$image" ]]; then # Handle cancelation
            echo "No image selected."
            exit 1
    fi

    if [[ "$image" == "lts-GDX" ]]; then
            echo -e "\e[32mYou have selected image: lts-GDX\e[0m"
            echo -e "\e[34mBluefin GDX is designed to be an AI Workstation by providing Nvidia drivers and CUDA in one image. It combines Bluefin LTS with the Bluefin Developer Experience. It is designed for AI and Machine Learning professionals.\e[0m"
            echo -e "\e[33mRead more at: \e[4mhttps://docs.projectbluefin.io/gdx\e[0m"
            image="-gdx"
    elif [[ "$image" == "lts-HWE" ]]; then
            echo -e "\e[32mYou have selected image: lts-HWE\e[0m"
            echo -e "\e[34mBluefin lts-HWE is Bluefin LTS with a more up-to-date kernel, maintained by the the CentOS Hyperscale SIG\e[0m"
            echo -e "\e[33mRead more at: \e[4mhttps://docs.projectbluefin.io/lts\e[0m"
            image="-hwe"
    elif [[ "$image" == "lts-DX" ]]; then
            echo -e "\e[32mYou have selected image: lts-DX\e[0m"
            echo -e "\e[34mBluefin LTS DX is designed for developers, providing a comprehensive development environment out of the box. Based on a CentOS 10\e[0m"
            echo -e "\e[33mRead more at: \e[4mhttps://docs.projectbluefin.io/bluefin-dx\e[0m"
            image="-dx"
    fi

    # Consider Base as empty string
    if [[ "$image" == "lts-$(date +%Y%m%d)" ]]; then
            image=""
            echo -e "\e[32mYou have selected image: lts-$(date +%Y%m%d)\e[0m"
            echo -e "\e[34mBluefin LTS is based on CentOS 10, for people who prefer Long Term Support.\e[0m"
            echo -e "\e[33mRead more at: \e[4mhttps://docs.projectbluefin.io/lts\e[0m"
    fi

    # take image to lower case
    image=$(echo "$image" | tr '[:upper:]' '[:lower:]')

    # Corrected confirmation logic: Proceed if confirmed, cancel otherwise.
    if ! gum confirm --prompt.bold "Are you sure you want to proceed?"; then
            echo "Operation cancelled."
            exit 1
    fi

    skopeo inspect docker://ghcr.io/ublue-os/bluefin${image}:lts
    sudo bootc switch --enforce-container-sigpolicy "ghcr.io/ublue-os/bluefin${image}:lts"
    if [[ $? -ne 0 ]]; then
            echo "Error: Failed to switch boot configuration."
            exit 1
    fi

    # Show a window informing the user that the operation is complete and they will need to reboot
    action=$(gum notify --title "Operation Complete" --message "The operation is complete. You will need to reboot your system for the changes to take effect." --actions "Reboot Now" "Reboot Later")

    if [[ "$action" == "Reboot Now" ]]; then
            systemctl reboot
    else
            echo "Please reboot your system later to apply the changes."
    fi
    }

    # Run the function
    select_image
