# Contributing to Raspberry Pi Remote Reflash Tool

First off, thanks for taking the time to contribute! 🎉

The following is a set of guidelines for contributing to this project. These are mostly guidelines, not rules. Use your best judgment, and feel free to propose changes to this document in a pull request.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
  - [Reporting Bugs](#reporting-bugs)
  - [Suggesting Enhancements](#suggesting-enhancements)
  - [Pull Requests](#pull-requests)
- [Development Setup](#development-setup)
- [Coding Guidelines](#coding-guidelines)
- [Testing](#testing)

## Code of Conduct

This project and everyone participating in it is governed by a simple principle: **Be respectful and constructive**.

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check existing issues to avoid duplicates.

**When submitting a bug report, include:**

- **Use a clear and descriptive title**
- **Describe the exact steps to reproduce**
- **Provide specific examples** (command you ran, output you got)
- **Describe the behavior you observed and expected**
- **Include debug output**: Run with `DEBUG=1` and include relevant logs
- **System information**:
  - OS version (macOS/Linux version)
  - Raspberry Pi model and OS version
  - Bash version: `bash --version`

**Example:**

```markdown
**Bug**: Flash fails with "kexec not supported"

**Steps to reproduce:**
1. Run `./reflash-pi.sh 192.168.1.100 password`
2. Script reaches Step 6
3. Error: "kexec_load failed: Function not implemented"

**Expected:** Should fall back to initramfs method

**System:**
- macOS 14.2
- Raspberry Pi 4B, 4GB RAM
- Raspberry Pi OS Bullseye

**Debug output:**
```
[DEBUG] Gewählte Methode: kexec
...
```
```

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues.

**When suggesting an enhancement, include:**

- **Clear and descriptive title**
- **Detailed description** of the suggested enhancement
- **Use cases**: Why would this be useful?
- **Possible implementation**: If you have ideas on how to implement it

**Example:**

```markdown
**Enhancement**: Add WiFi configuration support

**Description:**
Allow configuring WiFi credentials during reflash so the Pi can connect to wireless network on first boot.

**Use case:**
Headless Pi setups where Ethernet is not available.

**Possible implementation:**
- Add `wpa_supplicant.conf` to boot partition
- Accept WiFi SSID and password as optional parameters
```

### Pull Requests

**Process:**

1. **Fork** the repo
2. **Create a branch** from `main`: `git checkout -b feature/my-feature`
3. **Make your changes**
4. **Test thoroughly** on real hardware
5. **Update documentation** if needed
6. **Commit** with clear messages
7. **Push** to your fork
8. **Open a Pull Request**

**PR Guidelines:**

- Include a clear description of the problem and solution
- Reference any related issues: "Fixes #123"
- Include test results
- Keep PRs focused (one feature/fix per PR)
- Update CHANGELOG.md

**Example PR description:**

```markdown
## Description
Adds support for custom WiFi configuration during reflash.

## Changes
- Added `--wifi-ssid` and `--wifi-password` parameters
- Creates `wpa_supplicant.conf` on boot partition
- Updated README with WiFi setup instructions

## Testing
- ✅ Tested on Raspberry Pi 4B
- ✅ Tested on Raspberry Pi Zero W
- ✅ Verified WiFi connection on first boot
- ✅ Works with special characters in password

## Related Issues
Closes #42
```

## Development Setup

### Prerequisites

```bash
# macOS
brew install bash openssh openssl curl xz

# Linux (Debian/Ubuntu)
sudo apt-get install bash openssh-client openssl curl xz-utils
```

### Testing Environment

**You need:**
- A Raspberry Pi for testing (don't use production Pi!)
- Network connection between your computer and Pi
- Backup of important data (script will erase SD card!)

**Recommended:**
- Use a dedicated test Pi
- Have a spare SD card for quick recovery
- Test on multiple Pi models if possible

### Running Tests

```bash
# Enable debug mode
DEBUG=1 ./reflash-pi.sh <test-pi-ip> <password>

# Test with dry-run (if implementing)
DRY_RUN=1 ./reflash-pi.sh <test-pi-ip> <password>
```

## Coding Guidelines

### Shell Script Style

**Follow these conventions:**

```bash
# Use descriptive variable names
PI_IP="192.168.1.100"  # Good
IP="192.168.1.100"     # Avoid

# Use functions for reusable code
download_image() {
    # Function body
}

# Comment complex logic
# Calculate progress percentage for visual feedback
local percent=$((current * 100 / total))

# Use proper error handling
if ! ssh_cmd "test -f /boot/config.txt"; then
    log_error "Configuration file not found"
    return 1
fi

# Consistent indentation (4 spaces)
if [ "$DEBUG" = "1" ]; then
    log_debug "Debug message"
fi
```

### Logging

Use the provided logging functions:

```bash
log_info "Informational message"
log_success "Success message"
log_warning "Warning message"
log_error "Error message"
log_debug "Debug message (only shown in DEBUG mode)"
log_step "Major step header"
```

### Error Handling

```bash
# Always check return values
if ! some_command; then
    log_error "Command failed"
    return 1
fi

# Use proper cleanup
cleanup() {
    # Remove temporary files
    rm -f "$TEMP_FILE"
}
trap cleanup EXIT
```

### Documentation

- **Comment complex code blocks**
- **Update README.md** for new features
- **Add examples** for new functionality
- **Update CHANGELOG.md**

## Testing

### Manual Testing Checklist

Before submitting a PR, test:

- [ ] Fresh install works
- [ ] Script completes successfully
- [ ] Pi boots with new system
- [ ] SSH access works after reflash
- [ ] User configuration is correct
- [ ] Error handling works (test with wrong IP, wrong password, etc.)
- [ ] Debug mode provides useful output
- [ ] Works on different Pi models (if possible)

### Test Scenarios

**Success paths:**
1. Normal reflash with default user
2. Reflash with custom username
3. Reflash when image already downloaded
4. Reflash with debug mode enabled

**Error paths:**
1. Wrong IP address (should fail gracefully)
2. Wrong password (should show clear error)
3. Network interruption during upload
4. Pi runs out of disk space
5. Corrupted image file

## Questions?

Feel free to open an issue with the label `question` if you need help or clarification.

## Recognition

Contributors will be listed in the README. Thank you for your contributions! 🙏

---

**Happy coding!** 🚀
