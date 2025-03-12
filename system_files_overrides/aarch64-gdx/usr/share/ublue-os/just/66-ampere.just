export model := env("model", "deepseek-r1:70b")
export threads := env("threads", "64")

demo-deepseekserver:
    just llama-server "deepseek-r1:70b" "96"

demo-llama-server $model $threads:
    #!/usr/bin/env bash
    echo "Server will be available at http://localhost:8080/"
    sleep 2
    podman run --rm -i --label ai.ramalama --name ramalama_okQhesH2uf \
    --env=HOME=/tmp --init --security-opt=label=disable --cap-drop=all \
    --security-opt=no-new-privileges --label ai.ramalama.model=${model} \
    --label ai.ramalama.engine=podman --label ai.ramalama.runtime=llama.cpp \
    --label ai.ramalama.port=8080 --label ai.ramalama.command=serve --pull=newer \
    -t --env LLAMA_ARG_THREADS=${threads} -p 8080:8080 --device /dev/dri \
    --mount=type=bind,src=/var/home/adalovelace/.local/share/ramalama/models/ollama/${model},destination=/mnt/models/model.file,ro \
    quay.io/ramalama/ramalama:latest llama-server \
    --port 8080 -m /mnt/models/model.file -c 2048 --temp 0.8 -ngl 0 --host 0.0.0.0

demo-ai-server:
    #!/usr/bin/env bash
    #!/bin/bash

    # Get the list of models and extract the names
    models=$(ramalama list --json | jq -r '.[].name')

    # Check if any models were found
    if [[ -z "$models" ]]; then
    echo "No models found."
    exit 1
    fi

    models_newline=$(echo "$models" | tr ' ' '\n'| sed 's/^ollama:\/\///')

    # Use glow to display the model names and allow selection
    selected_model=$(echo "$models" | fzf --height 40% --border --ansi --prompt="Select a model: ")

    # Check if a model was selected
    if [[ -z "$selected_model" ]]; then
        echo "No model selected."
        exit 1
    fi

    # Run the just llama-server command with the selected model
    just llama-server "$selected_model" "64"

    echo "Started llama-server with model: $selected_model"
