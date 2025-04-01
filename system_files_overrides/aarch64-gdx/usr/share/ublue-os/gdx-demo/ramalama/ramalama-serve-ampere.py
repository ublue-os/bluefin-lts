#!/usr/bin/env python3

import subprocess
import argparse
import re

def main():
    parser = argparse.ArgumentParser(description="Run ramalama serve, extract podman command, remove GPU options, and execute.")
    parser.add_argument("model", help="Model to serve (e.g., huggingface://...)")
    parser.add_argument("--image", help="Image to use for the container")
    parser.add_argument("--authfile", help="Path of the authentication file")
    parser.add_argument("--device", help="Device to leak into the running container")
    parser.add_argument("-n", "--name", help="Name of container in which the Model will be run")
    parser.add_argument("--ngl", type=int, help="Number of layers to offload to the GPU, if available")
    parser.add_argument("--privileged", action="store_true", help="Give extended privileges to container")
    parser.add_argument("--pull", choices=["always", "missing", "never", "newer"], default="newer", help="Pull image policy")
    parser.add_argument("--seed", type=int, help="Override random seed")
    parser.add_argument("--temp", type=float, default=0.8, help="Temperature of the response from the AI model")
    parser.add_argument("--tls-verify", action="store_true", help="Require HTTPS and verify certificates when contacting registries")
    parser.add_argument("-c", "--ctx-size", type=int, default=2048, help="Size of the prompt context (0 = loaded from model)")
    parser.add_argument("--network", "--net", help="Set the network mode for the container")
    parser.add_argument("-d", "--detach", action="store_true", help="Run the container in detached mode")
    parser.add_argument("--host", default="0.0.0.0", help="IP address to listen")
    parser.add_argument("--generate", choices=["quadlet", "kube", "quadlet/kube"], help="Generate configuration format")
    parser.add_argument("-p", "--port", type=int, help="Port for AI Model server to listen on")
    parser.add_argument("-t", "--threads", type=int, help="Number of threads for llama.cpp")

    args = parser.parse_args()

    ramalama_args = ["ramalama", "--dryrun"]
    if args.image:
        ramalama_args.extend(["--image", args.image])
    ramalama_args.extend(["serve"])
    if args.authfile:
        ramalama_args.extend(["--authfile", args.authfile])
    if args.device:
        ramalama_args.extend(["--device", args.device])
    if args.name:
        ramalama_args.extend(["--name", args.name])
    if args.ngl:
        ramalama_args.extend(["--ngl", str(args.ngl)])
    if args.privileged:
        ramalama_args.append("--privileged")
    if args.pull:
        ramalama_args.extend(["--pull", args.pull])
    if args.seed:
        ramalama_args.extend(["--seed", str(args.seed)])
    if args.temp:
        ramalama_args.extend(["--temp", str(args.temp)])
    if args.tls_verify:
        ramalama_args.append("--tls-verify")
    if args.ctx_size:
        ramalama_args.extend(["-c", str(args.ctx_size)])
    if args.network:
        ramalama_args.extend(["--network", args.network])
    if args.detach:
        ramalama_args.append("-d")
    if args.host:
        ramalama_args.extend(["--host", args.host])
    if args.generate:
        ramalama_args.extend(["--generate", args.generate])
    if args.port:
        ramalama_args.extend(["-p", str(args.port)])
    if args.threads:
        ramalama_args.extend(["--threads", str(args.threads)])
    if args.threads:
        ramalama_args.extend(["-t", str(args.threads)])

    ramalama_args.append(args.model)

    try:
        result = subprocess.run(ramalama_args, capture_output=True, text=True, check=True)
        output = result.stdout
    except subprocess.CalledProcessError as e:
        print(f"Error running ramalama: {e.stderr}")
        return

    podman_command_match = re.search(r"podman run.*", output)
    if not podman_command_match:
        print("Error: Could not extract podman command.")
        return

    podman_command = podman_command_match.group(0)
    modified_command = re.sub(r" --device nvidia.com/gpu=all -e CUDA_VISIBLE_DEVICES=0", "", podman_command)

    print("Executing modified podman command:")
    print(modified_command)

    try:
        subprocess.Popen(["xdg-open", "http://localhost:8080"])
        subprocess.run(modified_command, shell=True)
    except subprocess.CalledProcessError as e:
        print(f"Error running podman: {e}")

if __name__ == "__main__":
    main()