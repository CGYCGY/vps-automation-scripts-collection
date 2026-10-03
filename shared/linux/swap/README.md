# Tailscale Setup Scripts - RAM-Based Swap Configuration

## 📊 Quick Reference Table

| RAM    | Swap Size | Swappiness | vfs_cache_pressure | Use Case                          |
|--------|-----------|------------|--------------------|-----------------------------------|
| 16GB+  | 4GB       | 10         | 50                 | Optimal performance, minimal swap |
| 12GB+  | 4GB       | 10         | 60                 | Good performance, light swap      |
| 8GB+   | 4GB       | 20         | 80                 | Balanced, moderate swap           |
| <8GB   | 4GB       | 30         | 100 (default)      | Survival mode, active swap        |

## ✅ Skip Conditions

The script will **skip swap creation** when:
- ✓ Existing swap ≥ 2GB
- ✓ Available disk space < 8GB

## 🎯 Example Outputs

### Example 1: Server with 16GB RAM (Optimal Performance)

```bash
[Step 2/9] Configuring Swap...
System Memory:
  RAM: 16384MB
  Current Swap: 0MB
  Available disk space: 40GB

Recommended: 4GB swap file with RAM-optimized settings
  • Swap size: 4GB (suitable for 1GB-16GB RAM)
  • Profile: Optimal performance (16GB+ RAM)
  • Swappiness: 10, Cache pressure: 50

Create optimized swap configuration? [Y/n]: y
Creating 4GB swap file...
  Allocating 4GB swap file (this may take a moment)...
  ✓ Swap file allocated
  ✓ Permissions set
  ✓ Swap activated
  ✓ Added to /etc/fstab (persists on reboot)

Optimizing swap settings based on RAM size...
  Profile: Optimal performance, minimal swap
  ✓ Swappiness set to 10
  ✓ Cache pressure set to 50

✓ Swap configuration complete!
  Total swap: 4096MB
  Profile: Optimal performance, minimal swap
  Swappiness: 10
  Cache pressure: 50
```

### Example 2: Server with 4GB RAM (Survival Mode)

```bash
[Step 2/9] Configuring Swap...
System Memory:
  RAM: 4096MB
  Current Swap: 0MB
  Available disk space: 25GB

Recommended: 4GB swap file with RAM-optimized settings
  • Swap size: 4GB (suitable for 1GB-16GB RAM)
  • Profile: Survival mode (<8GB RAM)
  • Swappiness: 30, Cache pressure: 100

Create optimized swap configuration? [Y/n]: y
Creating 4GB swap file...
  Allocating 4GB swap file (this may take a moment)...
  ✓ Swap file allocated
  ✓ Permissions set
  ✓ Swap activated
  ✓ Added to /etc/fstab (persists on reboot)

Optimizing swap settings based on RAM size...
  Profile: Survival mode, active swap
  ✓ Swappiness set to 30
  ✓ Cache pressure set to 100

✓ Swap configuration complete!
  Total swap: 4096MB
  Profile: Survival mode, active swap
  Swappiness: 30
  Cache pressure: 100
```

### Example 3: Sufficient Swap Already Exists

```bash
[Step 2/9] Configuring Swap...
System Memory:
  RAM: 8192MB
  Current Swap: 2048MB
✓ Sufficient swap already exists (2048MB)
  Skipping swap creation.

Press Enter to continue...
```

### Example 4: Insufficient Disk Space

```bash
[Step 2/9] Configuring Swap...
System Memory:
  RAM: 2048MB
  Current Swap: 0MB
  Available disk space: 6GB
⚠ Insufficient disk space (< 8GB free)
  Skipping swap creation for safety.

Press Enter to continue...
```

## 🔧 Technical Details

### What Gets Modified

**Files Created/Modified:**
- `/swapfile` - 4GB swap file (600 permissions)
- `/etc/fstab` - Swap persistence on reboot
- `/etc/sysctl.conf` - Kernel parameters

**Kernel Parameters Set:**
- `vm.swappiness` - How aggressively to use swap
- `vm.vfs_cache_pressure` - Inode/dentry cache retention

### Safety Features

1. **Existing Swap Detection**: Won't create swap if ≥2GB already exists
2. **Disk Space Check**: Won't create swap if <8GB free space
3. **Graceful Fallback**: Uses `dd` if `fallocate` fails
4. **Clean Removal**: Safely removes old `/swapfile` if it exists
5. **Idempotent**: Safe to run multiple times

### RAM-Based Optimization Logic

```bash
if RAM ≥ 16GB:
    swappiness=10, cache_pressure=50  # Minimal swap usage
elif RAM ≥ 12GB:
    swappiness=10, cache_pressure=60  # Light swap usage
elif RAM ≥ 8GB:
    swappiness=20, cache_pressure=80  # Moderate swap usage
else:
    swappiness=30, cache_pressure=100 # Active swap usage
```

## 🎭 Integration with Management Service Detection

The swap configuration works seamlessly with management service detection:

1. **Step 1**: Management service detection
   - Determines if Tailscale SSH should be enabled
   
2. **Step 2**: Swap configuration (THIS STEP)
   - Optimizes swap based on RAM
   
3. **Step 3**: System update
   - Updates packages
   
4. **Steps 4-9**: Continue with Tailscale setup

## 💡 Why These Settings?

### High RAM (16GB+): Minimal Swap
- **Swappiness 10**: Only swap when RAM is 90% full
- **Cache Pressure 50**: Keep more inodes/dentries in cache
- **Use Case**: Development servers, high-performance applications

### Medium RAM (8-12GB): Balanced
- **Swappiness 10-20**: Swap moderately when needed
- **Cache Pressure 60-80**: Balanced cache behavior
- **Use Case**: General-purpose servers, web applications

### Low RAM (<8GB): Active Swap
- **Swappiness 30**: Swap more aggressively
- **Cache Pressure 100**: Default cache behavior
- **Use Case**: Resource-constrained VPS, multi-service servers

## 🚀 Benefits

✅ **Automatic Optimization**: No manual tuning needed
✅ **RAM-Aware**: Settings adapt to your server's resources
✅ **Safe Defaults**: Conservative disk space requirements
✅ **Production-Ready**: Based on industry best practices
✅ **Persistent**: Configuration survives reboots

## 📝 Manual Verification

After script completion, verify swap is working:

```bash
# Check swap status
free -h
swapon --show

# Check kernel parameters
sysctl vm.swappiness
sysctl vm.vfs_cache_pressure

# Check fstab entry
grep swapfile /etc/fstab

# Check sysctl.conf
grep "vm\." /etc/sysctl.conf
```

## 🔄 To Manually Adjust Later

If you want to change settings after script completion:

```bash
# Change swappiness (0-100)
sudo sysctl vm.swappiness=20
sudo sed -i 's/^vm.swappiness=.*/vm.swappiness=20/' /etc/sysctl.conf

# Change cache pressure (0-∞, typically 50-200)
sudo sysctl vm.vfs_cache_pressure=75
sudo sed -i 's/^vm.vfs_cache_pressure=.*/vm.vfs_cache_pressure=75/' /etc/sysctl.conf
```

## 🎓 Understanding the Parameters

### vm.swappiness
- **Range**: 0-100
- **0**: Swap only to avoid OOM (Out of Memory)
- **10**: Minimal swap, keep in RAM as long as possible
- **60**: Default Linux behavior (balanced)
- **100**: Swap aggressively, prefer swap over RAM

### vm.vfs_cache_pressure
- **Range**: 0-∞ (typically 50-200)
- **50**: Retain inodes/dentries more (better for metadata-heavy workloads)
- **100**: Default balanced behavior
- **200+**: Reclaim inodes/dentries more aggressively (free more RAM)

---

**Note**: This configuration is automatically integrated into both:
- `tailscale-vps-setup-improved.sh` (Generic VPS)
- `tailscale-vps-setup-oracle-improved.sh` (Oracle Cloud)