FROM debian:bookworm-slim AS build
WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl xz-utils ca-certificates binutils && \
    rm -rf /var/lib/apt/lists/*

# Grab Zig toolchain (0.15.2)
RUN curl -L https://ziglang.org/download/0.15.2/zig-aarch64-linux-0.15.2.tar.xz -o zig.tar.xz && \
    mkdir -p /opt/zig && \
    tar -xf zig.tar.xz -C /opt/zig --strip-components=1 && \
    rm zig.tar.xz

ENV PATH="/opt/zig:${PATH}"

COPY . .
COPY .env .env

# Build static binary with musl
RUN zig build -Doptimize=ReleaseFast && \
    strip zig-out/bin/bme688_sensor

# Use scratch (empty image) since we have a static binary
FROM scratch
COPY --from=build /app/zig-out/bin/bme688_sensor /bme688_sensor
COPY --from=build /app/public/ /public/
COPY --from=build /app/.env /.env
ENTRYPOINT ["/bme688_sensor"]