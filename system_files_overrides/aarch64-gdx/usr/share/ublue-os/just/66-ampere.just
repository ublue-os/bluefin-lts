export model_name := env("MODEL_NAME", "deepseek-r1:70b")
export model_source := env("SOURCE", "ollama")
export threads := env("THREADS", `sh -c 'echo $(( $(nproc) / 2 ))'`)
export ngl := env("NGL", "0")
export ramalama_image := env("RAMALAMA_IMAGE", "quay.io/ramalama/vulkan:latest")
export script_dir := env("SCRIPT_DIR", "/usr/share/ublue-os/gdx-demo")

demo-ai-server $ramalama_image=ramalama_image $threads=threads $ngl=ngl:
    #!/usr/bin/env bash
    python3 ${script_dir}/ramalama/demo-ai-server.py --image $ramalama_image --threads $threads --ngl $ngl

[group('Just')]
check:
    #!/usr/bin/bash
    echo "Checking syntax: Justfile"
    find . -type f -name "*.just" | while read -r file; do
    echo "Checking syntax: $file"
    just --unstable --fmt --check -f $file
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt --check -f Justfile

[group('Just')]
fix:
    #!/usr/bin/bash
    echo "Fixing syntax: Justfile"
    find . -type f -name "*.just" | while read -r file; do
    echo "Fixing syntax: $file"
    just --unstable --fmt -f $file
    done
    echo "Fixing syntax: Justfile"
    just --unstable --fmt -f Justfile || { echo "Error: Failed to fix Justfile syntax."; exit 1; }

_demo-llama-server $ramalama_image=ramalama_image $model_source=model_source $model_name=model_name $threads=threads $ngl=ngl:
    #!/usr/bin/env bash
    cd ~/demo
    python3 ${script_dir}/ramalama/ramalama-serve-ampere.py --image $ramalama_image --threads $threads --ngl $ngl $model_source://$model_name

demo-deepseek-server:
    just _demo-llama-server ramalama_image="quay.io/ramalama/vulkan:latest" model_source="ollama" model_name="deepseek-coder:6.7b-base" threads="96" ngl="0"

demo-benchmark-sysbench:
    #!/usr/bin/env bash
    podman image inspect localhost/ampere-benchmarks || podman build -t localhost/ampere-benchmarks -f Dockerfile ${script_dir}/bench-container
    echo "Running sysbench cpu benchmark for 60 seconds"
    podman run -it --rm localhost/ampere-benchmarks sysbench cpu --threads=$(nproc) run --time=60

demo-benchmark-stress-ng:
    #!/usr/bin/env bash
    podman image inspect localhost/ampere-benchmarks || podman build -t localhost/ampere-benchmarks -f Dockerfile ${script_dir}/bench-container
    echo "Running stress-ng cpu benchmark for 60 seconds"
    podman run -it --rm localhost/ampere-benchmarks stress-ng --cpu $(nproc) --cpu-method all --timeout 60s --metrics-brief

demo-benchmark-7zip:
    #!/usr/bin/env bash
    podman image inspect localhost/ampere-benchmarks || podman build -t localhost/ampere-benchmarks -f Dockerfile ${script_dir}/bench-container
    echo "Running 7zip benchmark for 60 seconds"
    podman run -it --rm localhost/ampere-benchmarks 7z b -mmt$(nproc)

demo-btop:
    #!/usr/bin/env bash
    btop 
