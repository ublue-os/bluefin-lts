FROM ubuntu:24.04@sha256:6015f66923d7afbc53558d7ccffd325d43b4e249f41a6e93eef074c9505d2233

RUN apt-get update && apt-get install -y --no-install-recommends \
    sysbench \
    stress-ng \
    p7zip-full \
    git \
    build-essential \
    gfortran \
    wget \
    libssl-dev \
    ca-certificates \
    libsdl1.2-dev \
    && rm -rf /var/lib/apt/lists/*  # Clean up apt cache

# c-ray
WORKDIR /opt
RUN git clone https://github.com/jtsiomb/c-ray.git && \
    cd c-ray && \
    make -j$(nproc)

# x264 (optional, but good) - example of compiling from source
RUN git clone --depth 1 https://code.videolan.org/videolan/x264.git && \
    cd x264 && \
    ./configure --enable-static --enable-shared --enable-pic --enable-lto --extra-cflags="-march=armv8-a" --extra-ldflags="-march=armv8-a" && \
    make -j$(nproc) && \
    make install

# Stream (optional)
WORKDIR /opt
RUN wget https://www.cs.virginia.edu/stream/FTP/Code/stream.c && \
    gcc -O3 -fopenmp -DSTREAM_ARRAY_SIZE=100000000 -march=armv8-a -mtune=neoverse-n1 -o stream stream.c -lm

CMD ["bash"]