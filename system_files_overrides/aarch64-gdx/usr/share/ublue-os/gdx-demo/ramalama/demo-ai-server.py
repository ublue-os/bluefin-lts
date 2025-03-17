#!/usr/bin/env python3

import subprocess
import json
import os
import argparse

def demo_ai_server():
    """Interactively select an AI model and start llama-server."""

    parser = argparse.ArgumentParser(description="Interactively select an AI model and start llama-server.",
                                     formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument("--image", type=str, default=os.environ.get("ramalama_image", "quay.io/ramalama/vulkan:latest"),
                        help="Docker image to use for llama-server (default: quay.io/ramalama/vulkan:latest, can also be set via RAMALAMA_IMAGE environment variable)")
    parser.add_argument("--threads", type=int, default=None,
                        help="Number of threads to use (default: number of cores / 2, can also be set via THREADS environment variable)")
    parser.add_argument("--ngl", type=int, default=None,
                        help="Number of layers to offload to GPU (default: 0, can also be set via NGL environment variable)")
    args = parser.parse_args()

    try:
        # Get the list of models in JSON format using ramalama
        process = subprocess.run(["ramalama", "list", "--json"], capture_output=True, text=True, check=True)
        models_json_str = process.stdout
    except subprocess.CalledProcessError as e:
        print("Error: Failed to get model list from 'ramalama list --json'.")
        print(f"Return code: {e.returncode}")
        print(f"Stdout: {e.stdout}")
        print(f"Stderr: {e.stderr}")
        print("Please check ramalama installation and model setup.")
        return 1
    except FileNotFoundError:
        print("Error: 'ramalama' command not found. Please ensure ramalama CLI is installed and in your PATH.")
        return 1

    if not models_json_str:
        print("No models found by ramalama. Please add models using 'ramalama pull ...'.")
        return 1

    try:
        models_json = json.loads(models_json_str)
    except json.JSONDecodeError as e:
        print("Error: Failed to parse JSON output from 'ramalama list --json'.")
        print(f"JSONDecodeError: {e}")
        print("Output from ramalama list --json was:")
        print(models_json_str)
        return 1

    if not models_json:
        print("No models found by ramalama (after JSON parsing). Please add models using 'ramalama pull ...'.")
        return 1

    model_array = []
    for item in models_json:
        model_name_full = item.get("name")
        if not model_name_full:
            print("Error: Model entry missing 'name' field in ramalama list output.")
            return 1

        source = "ollama"  # Default source
        model_name = model_name_full

        if model_name_full.startswith("huggingface://"):
            source = "huggingface"
            model_name = model_name_full[len("huggingface://"):]
        elif model_name_full.startswith("ollama://"):
            source = "ollama"
            model_name = model_name_full[len("ollama://"):]
        elif model_name_full.startswith("oci://"):
            source = "oci"
            model_name = model_name_full[len("oci://"):]

        model_array.append({"source": source, "model_name": model_name, "original_name": model_name_full})

    if not model_array:
        print("No valid models found with recognized source prefixes (huggingface://, ollama://, oci://) or default source.")
        return 1

    selected_original_name = None
    if subprocess.run(["command", "-v", "fzf"], capture_output=True).returncode == 0:
        # Use fzf for interactive selection
        print("Using fzf for interactive model selection.")
        display_models = "\n".join([model["original_name"] for model in model_array])
        try:
            fzf_process = subprocess.run(["fzf", "--height", "40%", "--border", "--ansi", "--prompt", "Select a model: "],
                                        input=display_models, capture_output=True, text=True, check=True)
            selected_original_name = fzf_process.stdout.strip()
        except subprocess.CalledProcessError as e:
            if e.returncode == 130: # fzf returns 130 when user exits with Ctrl+C
                print("No model selected using fzf.")
                return 1
            else:
                print(f"Error running fzf: Return code: {e.returncode}, Stderr: {e.stderr}")
                # Fallback to list selection instead of exiting, if fzf fails for other reasons.
                print("Falling back to simple list selection due to fzf error.")
                selected_original_name = None # Ensure fallback happens
        except FileNotFoundError:
            print("Error: fzf command not found, but command -v fzf succeeded earlier. This is unexpected.")
            print("Falling back to simple list selection.")
            selected_original_name = None # Ensure fallback happens


    if not selected_original_name:
        # Fallback to simple numbered list selection
        print("fzf not found or failed. Falling back to simple list selection.")
        print("Available models:")
        for index, model in enumerate(model_array):
            print(f"{index + 1}) {model['original_name']}")

        while True:
            try:
                selected_index = int(input(f"Select model number (1-{len(model_array)}): "))
                if 1 <= selected_index <= len(model_array):
                    selected_original_name = model_array[selected_index - 1]["original_name"]
                    break
                else:
                    print("Invalid selection number. Please try again.")
            except ValueError:
                print("Invalid input. Please enter a number.")

        if not selected_original_name:
            print("No model selected.")
            return 1

    selected_model_source = None
    selected_model_name = None
    for model in model_array:
        if model["original_name"] == selected_original_name:
            selected_model_source = model["source"]
            selected_model_name = model["model_name"]
            break

    if not selected_model_source or not selected_model_name:
        print("Error: Could not find selected model details in parsed model array.")
        return 1

    threads = str(args.threads) if args.threads is not None else os.environ.get("threads")
    if not threads:
        try:
            nproc_output = subprocess.run(["nproc"], capture_output=True, text=True, check=True).stdout.strip()
            num_cores = int(nproc_output)
            threads = str(num_cores // 2)
        except (subprocess.CalledProcessError, ValueError, FileNotFoundError):
            threads = "4" # Default threads if nproc fails

    ngl = str(args.ngl) if args.ngl is not None else os.environ.get("ngl")
    if not ngl:
        ngl = "0" # Default to 0 so to show off CPU

    ramalama_image = args.image

    print(f"Starting llama-server with image: {ramalama_image} source: {selected_model_source}, model: {selected_model_name}, threads: {threads} ngl: {ngl}")

    try:
        subprocess.run(["just", "_demo-llama-server", ramalama_image, selected_model_source, selected_model_name, threads, ngl], check=True, cwd=os.getcwd())
        print(f"Started llama-server with source: {selected_model_source}, model: {selected_model_name}.")
    except subprocess.CalledProcessError as e:
        print("Error: Failed to start llama-server using 'just _demo-llama-server'.")
        print(f"Return code: {e.returncode}")
        print(f"Stdout: {e.stdout}")
        print(f"Stderr: {e.stderr}")
        print("Please check the error messages and podman logs (if applicable).")
        return 1
    except FileNotFoundError:
        print("Error: 'just' command not found. Please ensure just is installed and in your PATH.")
        return 1

    return 0 # Success

if __name__ == "__main__":
    exit(demo_ai_server())