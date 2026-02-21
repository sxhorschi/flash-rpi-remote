# 🚀 Raspberry Pi Remote Reflash Tool

> **Flash your Raspberry Pi SD card completely remote via SSH - no physical access needed!**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform: macOS/Linux](https://img.shields.io/badge/Platform-macOS%20%7C%20Linux-blue.svg)]()
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash-green.svg)]()

## ✨ Features

- 🌐 **Fully Remote** - Flash your Pi over the network without physical access
- 🔐 **Secure** - Uses SSH key authentication (password only needed once)
- 📊 **Beautiful UI** - Fancy progress bars and animated spinners
- 🐛 **Debug Mode** - Detailed logging for troubleshooting
- 🧠 **Smart** - Automatically detects best flash method (kexec or initramfs)
- 💾 **Low RAM** - Works even with limited RAM (~100MB free is enough)
- ⚡ **Fast** - Complete reflash in ~10-15 minutes
- 🛡️ **Safe** - Robust error handling and verification

## 🎬 Demo

```bash
$ ./reflash-pi.sh 192.168.1.100 mypassword pi

╔═══════════════════════════════════════════════════════════╗
║     🚀  RASPBERRY PI REMOTE REFLASH TOOL  🚀              ║
╚═══════════════════════════════════════════════════════════╝

[⠋] Generiere temporären SSH-Schlüssel...
[✓] SSH-Schlüssel generiert
[✓] Ab jetzt keine Passwort-Eingabe mehr!

[⠙] Raspberry Pi OS Image
[████████████████████████████████████] 100% Download abgeschlossen

[✓] Flash-Methode: initramfs hook (sicher, ~10 Min)
[✓] Upload auf Pi abgeschlossen
[✓] Flash-Script vorbereitet

╔═══════════════════════════════════════════════════════════╗
║          ✓✓✓  REFLASH ERFOLGREICH!  ✓✓✓                  ║
╚═══════════════════════════════════════════════════════════╝
```

## 📋 Requirements

### On your Mac/Linux computer:
- `bash` 4.0+
- `ssh`, `scp`
- `openssl`
- `curl`
- `xz` (for decompression)

Install on macOS:
```bash
brew install bash openssh openssl curl xz
```

### On your Raspberry Pi:
- Raspberry Pi OS (or compatible Debian-based OS)
- SSH enabled
- Network connection
- ~500MB free space in `/home`

## 🚀 Quick Start

### 1. Download the script

```bash
git clone https://github.com/yourusername/pi-remote-reflash.git
cd pi-remote-reflash
chmod +x reflash-pi.sh
```

### 2. Run the script

```bash
./reflash-pi.sh <PI_IP> <PASSWORD> [USERNAME]
```

**Examples:**

```bash
# Default user 'pi'
./reflash-pi.sh 192.168.1.100 raspberry

# Custom user
./reflash-pi.sh 192.168.1.100 mypassword georgws

# With debug mode
DEBUG=1 ./reflash-pi.sh 192.168.1.100 mypassword pi
```

### 3. Wait for completion

The script will:
1. Set up SSH key authentication (password required once)
2. Download latest Raspberry Pi OS Lite (ARM64)
3. Upload to your Pi
4. Prepare flash script
5. Reboot and flash automatically
6. Verify new system

**Total time: ~10-15 minutes**

## 🔧 How It Works

The tool uses an **initramfs hook** approach:

```
┌─────────────────────────────────────────────────────┐
│ 1. Script creates hook in initramfs                 │
│    ↓                                                 │
│ 2. Pi reboots                                        │
│    ↓                                                 │
│ 3. Hook runs BEFORE main system                     │
│    → SD card is not mounted yet = free!             │
│    ↓                                                 │
│ 4. Hook flashes new image to SD card                │
│    ↓                                                 │
│ 5. System boots normally with fresh OS              │
└─────────────────────────────────────────────────────┘
```

**Why this works:**
- Hook runs in early boot (initramfs) before root filesystem is mounted
- SD card is completely free during flash
- Works with minimal RAM (~50MB for initramfs)
- Safe and reliable

## 📖 Advanced Usage

### Debug Mode

Enable verbose logging:

```bash
DEBUG=1 ./reflash-pi.sh 192.168.1.100 mypassword
```

This shows:
- All SSH commands executed
- Detailed error messages
- Timing information
- Internal state

### Custom Image

To use a specific Raspberry Pi OS image instead of auto-downloading:

```bash
# Download your preferred image
curl -L -o ./raspbian-images/raspios-lite-arm64.img.xz \
  https://downloads.raspberrypi.org/raspios_lite_arm64/images/.../image.img.xz

# Run script (will use existing image)
./reflash-pi.sh 192.168.1.100 mypassword
```

### Multiple Pis

Flash multiple Pis in sequence:

```bash
#!/bin/bash
for ip in 192.168.1.{10..15}; do
  ./reflash-pi.sh "$ip" "password" "pi"
done
```

## 🛠️ Troubleshooting

### "SSH connection failed"

**Problem:** Can't connect to Pi

**Solutions:**
- Verify Pi is powered on and connected to network
- Check IP address: `ping 192.168.1.100`
- Ensure SSH is enabled on Pi
- Try: `ssh pi@192.168.1.100` manually to test

### "Image download failed"

**Problem:** Can't download Raspberry Pi OS

**Solutions:**
- Check internet connection
- Try manual download: https://www.raspberrypi.com/software/operating-systems/
- Place downloaded `.img.xz` file in `./raspbian-images/`

### "Pi doesn't come back online"

**Problem:** After flash, Pi is unreachable

**Solutions:**
- Wait longer (first boot can take 2-3 minutes)
- Check power supply and network cable
- Try ping: `ping 192.168.1.100`
- Check router DHCP table for Pi's IP
- Connect monitor/keyboard to Pi to see boot logs

### "Permission denied"

**Problem:** SSH authentication fails

**Solutions:**
- Ensure password is correct
- Check if password authentication is enabled on Pi: `sudo nano /etc/ssh/sshd_config` → `PasswordAuthentication yes`
- Restart SSH service: `sudo systemctl restart ssh`

### Still having issues?

Run with debug mode and [open an issue](https://github.com/yourusername/pi-remote-reflash/issues) with the output:

```bash
DEBUG=1 ./reflash-pi.sh 192.168.1.100 password > debug.log 2>&1
```

## 🔒 Security Considerations

- **Temporary SSH Key**: The script generates a temporary SSH key and removes it after completion
- **No Password Storage**: Password is only used for initial connection
- **Local Network**: Best used on trusted local networks
- **Backup Data**: Always backup important data before reflashing

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### Development

```bash
# Clone repo
git clone https://github.com/yourusername/pi-remote-reflash.git
cd pi-remote-reflash

# Make changes
nano reflash-pi.sh

# Test with debug mode
DEBUG=1 ./reflash-pi.sh <test-pi-ip> <password>

# Submit PR
git checkout -b feature/my-feature
git commit -am "Add new feature"
git push origin feature/my-feature
```

## 📜 License

MIT License - see [LICENSE](LICENSE) file for details

## 🙏 Credits

Created with ❤️ using [Claude Code](https://claude.ai/code)

## ⚠️ Disclaimer

This tool will **completely erase** the target Raspberry Pi's SD card. Always backup important data before use. Use at your own risk.

## 🗺️ Roadmap

- [ ] Support for Raspberry Pi OS Full (not just Lite)
- [ ] Support for other Pi models (32-bit)
- [ ] GUI version
- [ ] Pre-configured WiFi setup
- [ ] Batch reflash for multiple Pis
- [ ] Docker support
- [ ] Recovery mode if flash fails

## 📞 Support

- 🐛 **Bug Reports**: [GitHub Issues](https://github.com/yourusername/pi-remote-reflash/issues)
- 💡 **Feature Requests**: [GitHub Issues](https://github.com/yourusername/pi-remote-reflash/issues)
- 📧 **Email**: your.email@example.com

---

**Star ⭐ this repo if you find it useful!**
