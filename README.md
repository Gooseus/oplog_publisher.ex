# OplogPublisher

A MongoDB oplog publisher that streams changes to NATS.


## Working environment

### Elixir

```zsh
$ iex -v 
Erlang/OTP 27 [erts-15.2.3] [source] [64-bit] [smp:8:8] [ds:8:8:10] [async-threads:1] [jit] [dtrace]

IEx 1.18.3 (compiled with Erlang/OTP 27)
```

### Docker

```zsh
$ docker -v
Docker version 28.0.4, build b8034c0
```

```zsh
$ cat docker-compose.yml
```

```yaml
services:
  mongo:
    image: mongo:latest # v8.x
    container_name: mongo
    restart: always
    ports:
      - "27017:27017"
    # Mount the init script to initiate the single‑node replica set
    volumes:
      - ./mongo-init.js:/docker-entrypoint-initdb.d/mongo-init.js:ro
    # Enable replica‑set mode and bind on all interfaces
    command: ["--replSet", "rs0", "--bind_ip_all"]

  nats:
    image: nats:latest # v2.11.x
    container_name: nats
    restart: always
    ports:
      - "4222:4222"   # client port
      - "8222:8222"   # monitoring port
    # Mount a custom server config that turns on JetStream and defines our stream
    volumes:
      - ./nats-server.conf:/etc/nats/nats-server.conf:ro
    command: ["-c", "/etc/nats/nats-server.conf"]
```

## Setup

1. Clone the repository:
```bash
git clone <repository-url>
cd oplog_publisher
```

2. Install dependencies:
```bash
mix deps.get
```

3. Start the required services using Docker Compose:
```bash
docker-compose up -d
```

This will start:
- MongoDB instance
- NATS server


## Issue


