FROM registry.astralinux.ru/library/astra/ubi18:latest AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake git ca-certificates libpq-dev \
    && rm -rf /var/lib/apt/lists/*


WORKDIR /tmp
RUN git clone --branch 7.7.5 https://github.com/jtv/libpqxx.git && \
    cd libpqxx && mkdir build && cd build && \
    cmake .. -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_BUILD_TYPE=Release && \
    make -j$(nproc) && make install && rm -rf /tmp/libpqxx

WORKDIR /app
COPY CMakeLists.txt .
COPY src/ ./src/

RUN cmake -B build -S . -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build -j$(nproc)

FROM registry.astralinux.ru/library/astra/ubi18:latest

RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 postgresql-client \
    && rm -rf /var/lib/apt/lists/* && ldconfig

COPY --from=builder /app/build/tag_writer /usr/local/bin/tag_writer

CMD ["/usr/local/bin/tag_writer"]
