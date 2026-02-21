# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [4.0.0] - 2025-02-21

### Added
- 🎨 Fancy progress bars with animated completion indicators
- 🔄 Spinner animations for indefinite operations
- 🐛 Debug mode (`DEBUG=1` environment variable)
- 🔐 Single password authentication (SSH key auto-setup)
- 📦 Automatic image download with integrity verification
- 🧠 Smart flash method detection (kexec vs initramfs)
- 🎯 Initramfs hook flash method for maximum compatibility
- 📊 Beautiful ASCII art banners and status messages
- ✅ Comprehensive error handling and recovery
- 📝 Detailed logging with color-coded output
- ⏱️ Total duration tracking

### Changed
- Complete rewrite from scratch for reliability
- Improved SSH connection handling
- Better error messages and user guidance
- Enhanced progress visualization
- Optimized upload process with rsync support

### Fixed
- Image download corruption (0 bytes issue)
- Multiple password prompts after SSH key setup
- kexec compatibility on kernels without support
- RAM limitations (now works with ~100MB free)
- SSH connection timeout handling

### Removed
- Dependency on sshpass (now uses SSH keys)
- pivot_root method (unreliable with limited RAM)
- kexec-only approach (added fallback methods)

## [3.0.0] - 2025-02-21

### Added
- kexec boot method for direct kernel loading
- Alpine Linux netboot integration
- Automatic Flash method selection

### Issues
- kexec not supported on many Pi kernels
- Required ~1.5GB RAM
- Complex setup

## [2.0.0] - 2025-02-21

### Added
- Direct flash method with minimal impact
- Service shutdown approach
- Read-only remount strategy

### Issues
- Unstable during flash (system crashes)
- Boot configuration often failed
- Not reliable for production use

## [1.0.0] - 2025-02-21

### Added
- Initial release
- pivot_root to RAM approach
- Basic SSH functionality
- Manual password entry

### Issues
- Required too much RAM (1.2GB+)
- pivot_root failed on most Pi models
- macOS grep compatibility issues
- sshpass dependency problems

---

## Legend

- 🎨 UI/UX improvements
- 🔄 Performance enhancements
- 🐛 Bug fixes
- 🔐 Security improvements
- 📦 Dependencies
- 🧠 Intelligence/automation
- 🎯 New features
- 📊 Visualization
- ✅ Testing/validation
- 📝 Documentation
- ⏱️ Performance
