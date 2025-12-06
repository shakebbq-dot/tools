# Linux System Information Script

A comprehensive Bash script to view system properties, network parameters, and monitor resources on Linux systems.

## Features

- **System Properties**:
  - OS Version & Kernel
  - CPU Model & Cores
  - Memory Usage
  - Disk Usage & Mount Points
  - System Uptime & Load
- **Network Parameters**:
  - Network Interfaces (IP/MAC)
  - Current Connections (Listening Ports)
  - Routing Table
  - Network Latency Test
  - Real-time Bandwidth Monitoring (`iftop`/`nload`)
- **Automatic Dependency Management**:
  - Detects package manager (`apt`, `yum`, `dnf`, `pacman`)
  - Installs missing tools automatically
- **Logging**:
  - Saves reports to `/var/log/system_info.log`
- **Interactive Menu**: Easy-to-use text interface.

## Compatibility

Tested/Designed for:
- Ubuntu / Debian
- CentOS / RHEL
- Arch Linux

## Usage

1. **Download or Create the Script**:
   Save the script content to `system_info.sh`.

2. **Make Executable**:
   ```bash
   chmod +x system_info.sh
   ```

3. **Run as Root**:
   ```bash
   sudo ./system_info.sh
   ```

## Requirements

- Root privileges (sudo) are required for:
  - Installing dependencies
  - Accessing certain network stats (`ss -p`, `iftop`)
  - Writing to `/var/log`

## Output

- **Screen**: Displays color-coded information.
- **Log**: Appends detailed output to `/var/log/system_info.log`.
