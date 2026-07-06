# Asterisk Alpine Linux Buildchain

A complete Docker-based buildchain for compiling Asterisk PBX packages for Alpine Linux.

[![Hosted By: Cloudsmith](https://img.shields.io/badge/OSS%20hosting%20by-cloudsmith-blue?logo=cloudsmith&style=for-the-badge)](https://cloudsmith.com)

Package repository hosting is graciously provided by [Cloudsmith](https://cloudsmith.com).
Cloudsmith is the only fully hosted, cloud-native, universal package management solution, that
enables your organization to create, store and share packages in any format, to any place, with total confidence.

## Overview

This repository provides:
- **Docker-based build environment** for creating APK packages
- **Official Alpine APKBUILD** for Asterisk 20.11.1-r6 (Alpine 3.22)
- **19 Asterisk subpackages** (core, codecs, database connectors, etc.)
- **Custom APK repository** infrastructure
- **Automated build scripts** and Makefile

## Features

### Asterisk Packages Built

All 19 official Alpine Asterisk subpackages are built from a single APKBUILD:

**Core:**
- `asterisk` - Main PBX package (20.11.1-r6)
- `asterisk-dev` - Development headers
- `asterisk-doc` - Documentation
- `asterisk-sample-config` - Sample configurations

**Codecs:**
- `asterisk-opus` - Opus codec support
- `asterisk-speex` - Speex codec support

**Database & Directory:**
- `asterisk-pgsql` - PostgreSQL support
- `asterisk-ldap` - LDAP directory integration
- `asterisk-odbc` - ODBC database connectivity
- `asterisk-tds` - FreeTDS (MS SQL/Sybase)

**Features:**
- `asterisk-curl` - HTTP/HTTPS support
- `asterisk-fax` - Fax support (SpanDSP)
- `asterisk-mobile` - Bluetooth mobile channels
- `asterisk-srtp` - Secure RTP (AES-256)
- `asterisk-alsa` - ALSA sound support
- `asterisk-prometheus` - Prometheus metrics

**Media:**
- `asterisk-sounds-moh` - Music on hold
- `asterisk-sounds-en` - English prompts

**System:**
- `asterisk-openrc` - OpenRC init scripts

## Quick Start

### Prerequisites

- Docker or Podman
- Make
- 2GB+ free disk space

### Build All Packages

```bash
# Complete build process
make build

# Or step by step:
make build-docker      # Build Docker image
make init-keys         # Generate signing keys
make build-packages    # Build all APK packages
make repo-index        # Generate repository index
```

### Test Asterisk

```bash
# Run Asterisk in Docker
make test-asterisk
```

## Directory Structure

```
asterisk-alpine/
├── docker/
│   ├── builder.Dockerfile     # Build environment
│   ├── asterisk.Dockerfile    # Runtime image
│   └── repository.Dockerfile  # Repository server (optional)
├── packages/
│   └── asterisk/
│       ├── APKBUILD            # Package build recipe
│       ├── *.patch             # Alpine patches
│       └── *.initd/confd       # Init scripts
├── scripts/
│   ├── build.sh                # Build orchestration
│   ├── init-keys.sh            # Key generation
│   └── build-repo-index.sh     # Repository index generator
├── repository/                 # Built packages output
│   └── v3.22/
│       └── main/
│           └── x86_64/
│               ├── APKINDEX.tar.gz
│               └── asterisk*.apk (all 19 packages)
├── keys/                       # RSA signing keys (not in git)
├── docker-compose.yml
├── Makefile
└── README.md
```

## Build Process Details

### 1. Initialize Signing Keys

Generate RSA keys for signing packages:

```bash
make init-keys
```

This creates:
- `keys/packages@asterisk-alpine.rsa` - Private key (keep secure!)
- `keys/packages@asterisk-alpine.rsa.pub` - Public key (distribute to users)

**IMPORTANT:** Never commit private keys to git!

### 2. Build Packages

The build process:

1. Starts Alpine 3.22 builder container
2. Installs ~35 build dependencies
3. Downloads Asterisk 20.11.1 source
4. Applies Alpine's musl compatibility patches
5. Configures with all features enabled
6. Compiles Asterisk
7. Splits into 19 subpackages
8. Signs all packages with your key

```bash
make build-packages
```

**Build time:** ~30-60 minutes depending on hardware

### 3. Create Repository Index

Generate APKINDEX for APK package manager:

```bash
make repo-index
```

### 4. Test Repository (Optional)

Start a local nginx server hosting your repository:

```bash
make repo-server
# Access at http://localhost:8080/v3.22/main/x86_64/
```

## Using Your Custom Repository

### Add Repository to Alpine System

1. Trust the repository public key:
   ```bash
   wget -O /etc/apk/keys/packages@asterisk-alpine.rsa.pub \
     https://andrius.github.io/asterisk-alpine/packages@asterisk-alpine.rsa.pub
   ```
2. Add the repository:
   ```bash
   echo "https://andrius.github.io/asterisk-alpine/v3.24/main" >> /etc/apk/repositories
   ```
3. Install (pin a major by version, e.g. Asterisk 20):
   ```bash
   apk update
   apk add "asterisk=~20"
   ```

### Self-Signed Packages (Testing)

For testing without distributing keys:

```bash
apk add --allow-untrusted asterisk-20.11.1-r6.apk
```

## Makefile Targets

```bash
make help            # Show all available targets
make build           # Complete build (docker + keys + packages + index)
make build-docker    # Build Docker builder image
make init-keys       # Generate RSA signing keys
make build-packages  # Build all Asterisk APK packages
make repo-index      # Generate repository index
make test-asterisk   # Build and run Asterisk container
make repo-server     # Start repository HTTP server
make shell           # Open shell in builder container
make clean           # Clean build artifacts
make clean-all       # Clean everything including keys
make info            # Show package information
make validate        # Validate APKBUILD syntax
```

## Customization

### Modify Package Configuration

Edit `packages/asterisk/APKBUILD` to:
- Change Asterisk version
- Add/remove configure flags
- Enable/disable features
- Add custom patches

After changes:
```bash
make validate        # Check syntax
make build-packages  # Rebuild
```

### Add Custom Patches

1. Place patch file in `packages/asterisk/`
2. Add to `source=` in APKBUILD
3. Update checksums: `make build-packages`

## Advanced Usage

### Manual Build (Without Docker)

If you're on Alpine Linux:

```bash
cd packages/asterisk
abuild checksum    # Generate checksums
abuild -r          # Build packages
```

### Multi-Architecture Builds

Modify `docker/builder.Dockerfile` and add QEMU support for ARM builds.

### Continuous Integration

Example GitHub Actions workflow:

```yaml
name: Build Asterisk Packages
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: make build
      - uses: actions/upload-artifact@v3
        with:
          name: asterisk-packages
          path: repository/
```

## Repository Hosting Options

### Option 1: GitHub Releases
Upload built packages to GitHub releases (free, reliable)

### Option 2: Self-Hosted Nginx
```bash
make repo-server  # Local testing
# Deploy to production server
rsync -av repository/ server:/var/www/apk/
```

### Option 3: Cloud Storage
Upload to S3, Google Cloud Storage, or Azure Blob with CDN

### Option 4: Alpine Repository Manager
Use [APK server](https://gitlab.alpinelinux.org/alpine/apk-tools) for advanced repository management

## Security Considerations

1. **Private Key Security**
   - Never commit `keys/*.rsa` to version control
   - Store securely (vault, secrets manager)
   - Rotate keys periodically

2. **Package Signing**
   - Always sign packages for production
   - Distribute public key securely
   - Verify signatures on installation

3. **Build Environment**
   - Review APKBUILD before building
   - Use trusted source tarballs
   - Scan built packages for vulnerabilities

## Troubleshooting

### Build Fails with "Permission Denied"
- Ensure scripts are executable: `chmod +x scripts/*.sh`
- Check Docker daemon is running

### "Signing Keys Not Found"
- Run `make init-keys` first

### Packages Not Found After Build
- Check `repository/v3.22/main/x86_64/` directory
- Ensure build completed successfully
- Run `make info` to see package count

### Docker Not Available
- Install Docker: `curl -fsSL https://get.docker.com | sh`
- Or use Podman: `alias docker=podman`

## Long-Term Roadmap

### Phase 2: Multi-Version Support
- Support Alpine 3.20, 3.21, 3.22, edge
- Support multiple Asterisk versions (18.x, 20.x, 21.x)
- Automated version matrix builds

### Phase 3: CI/CD Integration
- GitHub Actions / GitLab CI
- Automated testing
- Nightly builds for edge
- Security vulnerability scanning

### Phase 4: Production Repository
- CDN-backed distribution
- Multiple architecture support (aarch64, armv7)
- Repository mirroring
- Package statistics and metrics

## Contributing

1. Fork the repository
2. Create feature branch
3. Make changes
4. Test builds: `make build`
5. Submit pull request

## Resources

- [Alpine Linux Packages](https://pkgs.alpinelinux.org/)
- [Alpine APKBUILD Reference](https://wiki.alpinelinux.org/wiki/APKBUILD_Reference)
- [Asterisk Documentation](https://docs.asterisk.org/)
- [abuild Manual](https://wiki.alpinelinux.org/wiki/Abuild_and_Helpers)

## License

This buildchain configuration is provided as-is for building Asterisk packages.
- Asterisk is GPL-2.0-only WITH OpenSSL-Exception
- Alpine Linux APKBUILD files maintain their original licenses
- Build scripts in this repository: MIT License

## Support

For issues:
1. Check troubleshooting section above
2. Review Alpine aports: https://gitlab.alpinelinux.org/alpine/aports
3. Asterisk community: https://community.asterisk.org/

---

**Built with ❤️ for the Asterisk and Alpine Linux communities**
