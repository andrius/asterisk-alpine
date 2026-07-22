# Validation Report

> **Historical: describes the original single-package layout.** This report
> covers `packages/asterisk/` (asterisk 20.11.1-r6 on Alpine 3.22, 19
> subpackages, a `repository/v3.22/` tree) - the state before the repository
> became a multi-line matrix. That directory was deleted in 2026-07 (superseded
> by `packages/20/`); the base is now Alpine 3.24 with ten lines, and packages
> are published to Cloudsmith rather than a local tree.
>
> **Do not follow the commands below as current instructions** - `make build`,
> `make build-packages` and `make repo-index` still exist but now drive one line
> (default 20) on 3.24. For current testing use `make test-<line>` (e.g.
> `make test-23`), and see [README](README.md) + `CLAUDE.md`. Retained as a
> historical pre-flight record.

## ✅ Pre-Flight Checks (Completed)

### File Integrity
- ✅ All 10 required source files present in `packages/asterisk/`
  *(historical: that directory was removed 2026-07-22; each line now carries its
  own set under `packages/<line>/`)*
- ✅ All shell scripts have valid bash syntax
- ✅ APKBUILD structure is valid (pkgname, pkgver, pkgrel defined)
- ✅ Docker configurations exist (builder, asterisk, compose)
- ✅ Build scripts are executable (755 permissions)
- ✅ Git repository initialized and pushed

### APKBUILD Validation
- ✅ Package: asterisk 20.11.1-r6 (matches Alpine 3.22)
- ✅ Source files declared correctly
- ✅ All patches present locally
- ✅ Subpackages defined (19 packages)
- ✅ Init scripts included

### Scripts Syntax Check
- ✅ `scripts/init-keys.sh` - Syntax OK
- ✅ `scripts/build.sh` - Syntax OK
- ✅ `scripts/build-repo-index.sh` - Syntax OK

## ⚠️ Not Tested (Requires Docker)

The following **have NOT been executed** and need testing on a system with Docker:

### 1. Docker Image Build
```bash
cd /home/user/asterisk-alpine
make build-docker
```
**Expected**: Builder image builds successfully (~2-3 minutes)
**Potential issues**:
- Network access to Alpine mirrors
- Disk space (need ~1GB for image)

### 2. Key Generation
```bash
make init-keys
```
**Expected**: RSA keys generated in `keys/` directory
**Potential issues**:
- OpenSSL availability in container
- File permissions on mounted volumes

### 3. Package Build
```bash
make build-packages
```
**Expected**: All 19 Asterisk packages built (~30-60 minutes)
**Potential issues**:
- Download failures for Asterisk source (from asterisk.org)
- Download failures for opus patch (from github.com)
- Missing build dependencies in Alpine 3.22
- Compilation errors with musl libc
- Checksum mismatches

### 4. Repository Index
```bash
make repo-index
```
**Expected**: APKINDEX.tar.gz created in repository/
**Potential issues**:
- apk-tools not available
- Signing key path incorrect

### 5. Asterisk Runtime
```bash
make test-asterisk
```
**Expected**: Asterisk container starts and responds
**Potential issues**:
- Port conflicts (5060, 5061)
- Permission issues with asterisk user
- Missing runtime dependencies

## 🧪 Recommended Testing Procedure

### Phase 1: Basic Build (30-60 min)
```bash
# On a system with Docker installed:
git clone <repo-url>
cd asterisk-alpine

# Test 1: Docker image build
make build-docker
# Expected output: "✅ Builder image ready"

# Test 2: Key generation
make init-keys
ls -la keys/
# Expected: packages@asterisk-alpine.rsa and .rsa.pub present

# Test 3: Open builder shell (verify environment)
make shell
# Inside container:
abuild --version
whoami  # Should be 'builder', not 'root'
ls /home/builder/asterisk
exit

# Test 4: Build packages (LONG - 30-60 min)
make build-packages 2>&1 | tee build.log
# Watch for errors in compilation

# Test 5: Check output
find repository -name "*.apk" -type f
# Expected: 19 asterisk*.apk files

# Test 6: Create repository index
make repo-index
ls -lh repository/v3.22/main/x86_64/APKINDEX.tar.gz
```

### Phase 2: Runtime Testing (5 min)
```bash
# Test 7: Start Asterisk
make test-asterisk

# In another terminal:
docker exec -it asterisk-pbx asterisk -rvvv
# Expected: Asterisk CLI prompt

# At Asterisk CLI:
core show version
module show
# Verify version and modules loaded

# Test 8: Stop
docker compose --profile runtime down
```

### Phase 3: Repository Server (2 min)
```bash
# Test 9: Start repository server
make repo-server

# Test 10: Access repository
curl -I http://localhost:8080/v3.22/main/x86_64/APKINDEX.tar.gz
# Expected: HTTP 200 OK

# Test 11: Browse packages
curl http://localhost:8080/v3.22/main/x86_64/ | grep asterisk
```

### Phase 4: Package Installation (On Alpine 3.22)
```bash
# Test 12: Install from custom repository
# On an Alpine 3.22 system:

# Copy signing key
sudo cp keys/packages@asterisk-alpine.rsa.pub /etc/apk/keys/

# Add repository
echo "http://your-server:8080/v3.22/main" | sudo tee -a /etc/apk/repositories

# Update and install
sudo apk update
sudo apk add asterisk asterisk-opus asterisk-prometheus

# Verify installation
asterisk -V
apk info asterisk
```

## 🐛 Known Potential Issues

### Issue 1: Checksums May Fail
**Symptom**: `abuild checksum` fails
**Cause**: APKBUILD checksums are for specific source versions
**Fix**: Run `abuild checksum` to regenerate (already handled in build.sh)

### Issue 2: Download Failures
**Symptom**: Can't download asterisk-20.11.1.tar.gz
**Cause**: Network issues or asterisk.org unavailable
**Fix**:
- Check network connectivity from container
- Use Alpine mirror if available
- Download sources manually to the `packages/<line>/` directory

### Issue 3: Compilation Errors
**Symptom**: Build fails during compilation
**Cause**: Missing dependencies or incompatibilities
**Fix**: Check build.log for specific error, may need to adjust APKBUILD

### Issue 4: Volume Permission Issues
**Symptom**: Can't write to mounted volumes
**Cause**: Docker volume permission mismatch
**Fix**: Check docker-compose.yml volume mounts, may need to adjust UID/GID

### Issue 5: Port Conflicts
**Symptom**: Can't start Asterisk container
**Cause**: Port 5060 already in use
**Fix**: Edit docker-compose.yml to use different ports

## 📊 Success Criteria

A fully successful build should produce:

```
repository/v3.22/main/x86_64/
├── APKINDEX.tar.gz                          (~50 KB, signed)
├── asterisk-20.11.1-r6.apk                 (~3-5 MB)
├── asterisk-alsa-20.11.1-r6.apk            (~50 KB)
├── asterisk-curl-20.11.1-r6.apk            (~50 KB)
├── asterisk-dbg-20.11.1-r6.apk             (~10-20 MB)
├── asterisk-dev-20.11.1-r6.apk             (~500 KB)
├── asterisk-doc-20.11.1-r6.apk             (~5-10 MB)
├── asterisk-fax-20.11.1-r6.apk             (~100 KB)
├── asterisk-ldap-20.11.1-r6.apk            (~30 KB)
├── asterisk-mobile-20.11.1-r6.apk          (~50 KB)
├── asterisk-odbc-20.11.1-r6.apk            (~50 KB)
├── asterisk-openrc-20.11.1-r6.apk          (~10 KB)
├── asterisk-opus-20.11.1-r6.apk            (~50 KB)
├── asterisk-pgsql-20.11.1-r6.apk           (~50 KB)
├── asterisk-prometheus-20.11.1-r6.apk      (~30 KB)
├── asterisk-sample-config-20.11.1-r6.apk   (~100 KB)
├── asterisk-sounds-en-20.11.1-r6.apk       (~5-10 MB)
├── asterisk-sounds-moh-20.11.1-r6.apk      (~2-5 MB)
├── asterisk-speex-20.11.1-r6.apk           (~50 KB)
├── asterisk-srtp-20.11.1-r6.apk            (~50 KB)
└── asterisk-tds-20.11.1-r6.apk             (~30 KB)
```

**Total:** 19 packages, ~30-50 MB total size

## 🔍 Validation Commands Summary

```bash
# Quick validation (no Docker required)
make info          # Show package info
make validate      # Validate APKBUILD (needs Docker)

# Full build test
make build         # Complete build process

# Runtime test
make test-asterisk # Start Asterisk
docker logs asterisk-pbx  # Check logs

# Repository test
make repo-server
curl http://localhost:8080/v3.22/main/x86_64/
```

## ⚡ Quick Fix Script

If you encounter issues, try this diagnostic script:

```bash
#!/bin/bash
# Save as: test-buildchain.sh

echo "=== Asterisk Alpine Buildchain Diagnostics ==="
echo ""

echo "1. Checking Docker..."
docker --version || echo "ERROR: Docker not found"

echo ""
echo "2. Checking files..."
[ -f packages/20/APKBUILD ] && echo "✓ APKBUILD exists" || echo "✗ APKBUILD missing"
[ -x scripts/build.sh ] && echo "✓ build.sh executable" || echo "✗ build.sh not executable"

echo ""
echo "3. Checking disk space..."
df -h . | tail -1

echo ""
echo "4. Testing Docker build..."
docker compose build builder --dry-run 2>&1 | head -5

echo ""
echo "=== End Diagnostics ==="
```

## 📝 Next Steps

1. **On a system with Docker**, run the testing procedure above
2. Report any errors with the build.log
3. If successful, document any adjustments needed
4. Add CI/CD workflow for automated testing

## 🆘 Support

If you encounter issues during testing:
1. Save the build log: `make build-packages 2>&1 | tee build-$(date +%Y%m%d).log`
2. Check specific error messages
3. Compare APKBUILD with Alpine upstream
4. Test on a clean Alpine 3.22 container first
