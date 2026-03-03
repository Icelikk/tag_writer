FROM registry.astralinux.ru/library/astra/ubi18:latest AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    ca-certificates \
    libpq-dev \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*


WORKDIR /tmp
RUN git clone --branch 7.7.5 https://github.com/jtv/libpqxx.git && \
    cd libpqxx && \
    mkdir build && cd build && \
    cmake .. -DCMAKE_INSTALL_PREFIX=/usr/local \
             -DCMAKE_BUILD_TYPE=Release && \
    make -j$(nproc) && \
    make install

WORKDIR /app
COPY . .

RUN mkdir -p build && cd build && \
    cmake .. -DCMAKE_PREFIX_PATH=/usr/local && \
    make -j$(nproc)


FROM registry.astralinux.ru/library/astra/ubi18:latest

RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/lib/libpqxx* /usr/local/lib/
COPY --from=builder /app/build/TagsWriter /usr/local/bin/tag_writer

RUN ldconfig

CMD ["/usr/local/bin/tag_writer"]