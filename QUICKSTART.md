# Quick Start Guide

## Prerequisites

Install Docker on your system:

```bash
# Ubuntu/Debian
sudo apt update && sudo apt install docker.io docker-compose
sudo usermod -aG docker $USER
# Log out and back in

# Or use the official installer
curl -fsSL https://get.docker.com | sh
```

## Build Asterisk Packages (5 Minutes)

```bash
# Clone this repository
git clone <your-repo-url>
cd asterisk-alpine

# Complete build
make build
```

This will:
1. Build Docker builder image (~2 min)
2. Generate signing keys (~5 sec)
3. Build all 19 Asterisk packages (~30-60 min)
4. Create repository index (~5 sec)

## Test Asterisk

```bash
# Run Asterisk in Docker
make test-asterisk

# In another terminal, connect to Asterisk CLI
docker exec -it asterisk-pbx asterisk -rvvv
```

## Use Your Custom Packages

### On Alpine Linux

```bash
# Copy public key
sudo cp keys/packages@asterisk-alpine.rsa.pub /etc/apk/keys/

# Add repository (replace with your server URL)
echo "http://your-server/v3.22/main" | sudo tee -a /etc/apk/repositories

# Install
sudo apk update
sudo apk add asterisk asterisk-opus asterisk-prometheus
```

### Local Testing

```bash
# Start repository server
make repo-server

# Access at http://localhost:8080/v3.22/main/x86_64/
```

## Common Commands

```bash
make help            # Show all targets
make shell           # Open builder shell
make clean           # Clean builds
make info            # Show package info
```

## Next Steps

- Read [README.md](README.md) for detailed documentation
- Customize `packages/<line>/APKBUILD` (e.g. `packages/20/APKBUILD`) for your needs
- Set up CI/CD for automated builds
- Deploy repository to production server

## Troubleshooting

**Docker not found:**
```bash
# Install Docker first (see Prerequisites above)
```

**Permission denied:**
```bash
# Add user to docker group
sudo usermod -aG docker $USER
# Log out and back in
```

**Build takes too long:**
- First build takes 30-60 minutes (downloads and compiles Asterisk)
- Subsequent builds are faster with Docker layer caching

**Need help?**
- Check the [Troubleshooting](README.md#troubleshooting) section
- Review Alpine's [APKBUILD docs](https://wiki.alpinelinux.org/wiki/APKBUILD_Reference)
