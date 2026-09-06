# Foremost Recovery Toolkit — Basic Recovery

**Basic Recovery** is an interactive data recovery workflow for Linux, designed primarily for **Kali Linux** and built around `dd`, `SHA256`, and `Foremost`.

Instead of running file carving directly against the original source device, Basic Recovery first creates a complete disk image. The image is then hashed and verified before Foremost performs file recovery.

> **Warning:** Always verify the source and destination devices carefully before starting a recovery.

---

## Features

- Interactive source device selection
- SMART health analysis before recovery
- Physical disk identity verification
- Protection against using the same physical disk as source and destination
- Mounted source devices are rejected
- Source devices are never automatically unmounted
- exFAT and NTFS destination support
- Automatic mounting of supported destination filesystems
- Destination write test
- Available-space verification
- File type selection by category
- Full source imaging with `dd`
- Read-error handling using `conv=noerror,sync`
- SHA256 generation
- Automatic SHA256 verification
- Foremost file carving on the image
- Additional MP4 recovery handling
- Recovered-file counting by type
- Runtime logging
- Final recovery report
- Final source/destination safety verification immediately before recovery

---

## Recovery Workflow

Basic Recovery uses a seven-step workflow:

1. Select the source device
2. Perform SMART health analysis
3. Select the destination device
4. Select file types
5. Review the configuration and confirm
6. Create the image and verify its SHA256 hash
7. Run Foremost and generate the final report

The basic recovery chain is:

```text
SOURCE DEVICE
      |
      v
FULL DISK IMAGE
      |
      +---- SHA256 generation
      |
      +---- SHA256 verification
      |
      v
   FOREMOST
      |
      v
RECOVERED FILES
```

This image-first approach avoids running Foremost directly against the original recovery source.

---

## Requirements

Basic Recovery is designed for Linux and has primarily been developed and tested on **Kali Linux**.

Required tools include:

```text
bash
util-linux
smartmontools
foremost
python3
coreutils
exfatprogs
```

Root privileges are required for raw disk access and SMART operations.

---

## Installation

Clone the repository:

```bash
git clone <repository-url>
cd <repository-directory>
```

Make the script executable:

```bash
chmod +x BASIC_RECOVERY.sh
```

Run Basic Recovery:

```bash
sudo ./BASIC_RECOVERY.sh
```

It is recommended to inspect all connected storage devices first:

```bash
lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,LABEL,MOUNTPOINTS
```

---

## Source Device Selection

The recovery source can be an entire disk or an individual partition.

Examples:

```text
sdb
```

or:

```text
sdb1
```

Before continuing, Basic Recovery checks:

- whether the selected block device exists;
- which physical disk contains the selected device;
- available disk identity information;
- whether the source or any underlying partitions are mounted;
- whether the device identity changes during the workflow.

### Mounted Sources

A mounted recovery source is rejected.

Basic Recovery deliberately does **not** automatically unmount source devices.

This prevents the script from unexpectedly disconnecting active filesystems.

---

## Stable Device Identity

Linux device names such as:

```text
/dev/sdb
/dev/sdc
/dev/sdd
```

can change when storage devices are disconnected, reconnected, or detected in a different order.

Basic Recovery therefore stores additional identity information, including where available:

```text
Serial Number
WWN
Model
Disk Size
/dev/disk/by-id entries
PARTUUID
UUID
```

The identity is checked again immediately before the recovery starts.

If the selected device no longer matches the original identity, the recovery is stopped.

---

## SMART Health Analysis

Basic Recovery attempts to read SMART information from the physical source disk using:

```bash
smartctl
```

The analysis examines indicators including:

```text
Reallocated_Sector_Ct
Reported_Uncorrect
Current_Pending_Sector
Offline_Uncorrectable
UDMA_CRC_Error_Count
```

### Low Risk

No critical SMART indicators were detected.

### Warning

One or more indicators suggest that additional caution may be required.

### High Risk

Serious indicators such as pending or uncorrectable sectors were detected.

In high-risk situations, Basic Recovery warns the user before continuing.

> For unstable or physically damaged storage devices, a GNU `ddrescue` based workflow is generally more appropriate.

---

## Destination Device

The recovery destination must be located on a **different physical disk** from the source.

A separate partition on the same physical disk is not considered a safe destination.

### Supported Destination Filesystems

| Filesystem | Status |
|---|---|
| exFAT | Recommended |
| NTFS | Supported |
| FAT32 / VFAT | Rejected |
| ext2 / ext3 / ext4 | Rejected for this workflow |
| XFS / Btrfs | Rejected for this workflow |

### Why FAT32 Is Rejected

FAT32 has a maximum individual file size of approximately **4 GB**.

Recovery images can easily be tens, hundreds, or thousands of gigabytes in size.

### Why exFAT Is Recommended

exFAT provides convenient read/write compatibility between **Linux and Windows**, making it suitable for portable recovery storage.

---

## Destination Safety Checks

Before the recovery starts, Basic Recovery verifies that:

- the destination is a partition;
- the destination is on a different physical disk;
- the filesystem is supported;
- the destination is mounted;
- the mountpoint belongs to the selected destination;
- the filesystem is writable;
- a real test file can be created and removed;
- sufficient free space is available.

Basic Recovery never automatically formats the destination.

---

## File Type Selection

Basic Recovery provides an interactive file type menu.

### All Supported Types

```text
jpg,jpeg,gif,png,bmp,tif
avi,mp4,mov,mpg,wmv
doc,pdf,htm
wav,mp3,wma,ra
zip,rar
pst,ost,dbx,mbx
```

### Photos

```text
jpg,jpeg,gif,png,bmp,tif
```

### Videos

```text
avi,mp4,mov,mpg,wmv
```

### Documents

```text
doc,pdf,htm
```

### Audio

```text
wav,mp3,wma,ra
```

### Archives

```text
zip,rar
```

### Email

```text
pst,ost,dbx,mbx
```

### Custom Selection

Individual file types can also be entered manually.

Example:

```text
jpg,pdf,mp4
```

---

## Image Creation

Basic Recovery creates a complete image of the selected source before file carving begins.

Conceptually, the imaging operation uses:

```bash
dd if=/dev/SOURCE of=image.img bs=4M status=progress conv=noerror,sync
```

`conv=noerror,sync` allows imaging to continue when certain read errors are encountered while preserving block alignment.

Detected read problems are recorded in the recovery logs.

---

## SHA256 Verification

After the image has been created, Basic Recovery calculates a SHA256 hash.

Example output:

```text
image_sdc.img
image_sdc.img.sha256
```

The generated checksum is then verified:

```bash
sha256sum -c image_sdc.img.sha256
```

This provides an integrity reference for the created recovery image.

---

## Foremost File Carving

After imaging and SHA256 verification, Foremost performs file carving against the image.

Conceptually:

```bash
foremost -t jpg,pdf,mp4 -i image.img -o result/
```

Foremost therefore processes:

```text
image.img
```

instead of the original physical recovery source.

---

## MP4 Recovery

MP4 recovery can be more complicated than carving simpler file formats such as JPEG.

Basic Recovery includes additional MP4 handling that can inspect ISO Base Media File Format structures.

Recognized box types include:

```text
ftyp
free
mdat
moov
wide
skip
uuid
pdin
meta
```

Candidate files are checked before being accepted as recovered MP4 files.

---

## Pre-Start Safety Verification

Immediately before imaging begins, Basic Recovery performs another safety check.

It verifies:

- source device presence;
- destination device presence;
- physical source disk;
- physical destination disk;
- stored source identity;
- stored destination identity;
- source mount status;
- destination mount status;
- destination mountpoint;
- source size;
- available destination space.

If an important condition has changed since device selection, the recovery is stopped.

---

## Recovery Output

Each recovery receives its own timestamped directory.

Example:

```text
recovery_20260906_201500/
├── image_sdc.img
├── image_sdc.img.sha256
├── dd_read_errors.log
├── verslag_foremost.txt
└── resultaat/
    ├── jpg/
    ├── pdf/
    ├── mp4/
    └── ...
```

The exact directory structure depends on the selected file types and recovered data.

---

## Recovery Report

The final recovery report contains information such as:

- recovery date and time;
- source device;
- physical source disk;
- destination device;
- physical destination disk;
- destination filesystem;
- destination mountpoint;
- selected recovery category;
- selected file types;
- SMART status;
- detected imaging read errors;
- recovery image location;
- SHA256 location;
- Foremost result location;
- number of recovered files;
- total recovery duration.

---

## Safety Principles

### Never Automatically Format the Source

The recovery source is never formatted by Basic Recovery.

### Never Automatically Unmount the Source

If the source is mounted, the script stops and asks the user to resolve the situation manually.

### Never Automatically Format the Destination

An unsupported or unformatted destination is rejected instead of being automatically reformatted.

### Source and Destination Must Be Physically Separate

Using another partition on the same physical disk is not permitted.

### Device Identity Is Rechecked

Basic Recovery does not rely exclusively on `/dev/sdX` device names.

### Image First

File carving is performed against the recovery image instead of directly against the original source.

---

## Damaged or Unstable Drives

Basic Recovery is primarily intended for healthy or reasonably stable storage devices.

Use additional caution if a drive:

- makes clicking or unusual mechanical noises;
- repeatedly disconnects;
- disappears from the operating system;
- becomes extremely slow;
- contains large numbers of bad sectors;
- reports pending sectors;
- reports uncorrectable sectors;
- reports serious SMART warnings.

Repeated reads can place additional stress on failing hardware.

For these situations, a recovery workflow based on **GNU ddrescue** with persistent mapfiles, resume support, and controlled retry passes is generally more appropriate.

---

## Basic vs Advanced Recovery

### Basic Recovery

Designed for normal or reasonably stable recovery sources.

```text
SOURCE
   |
   v
  dd
   |
   v
IMAGE
   |
   +---- SHA256
   |
   v
FOREMOST
```

### Advanced Recovery

Intended for more difficult or unstable storage devices.

The Advanced workflow can use GNU `ddrescue` functionality such as:

```text
mapfile
resume
controlled retries
multiple recovery passes
extended logging
```

---

## Important Warning

Data recovery is never completely risk-free.

Before starting any recovery, always verify:

1. which device is the **source**;
2. which device is the **destination**;
3. that the source is not actively mounted or in use;
4. that source and destination are physically separate;
5. that sufficient destination space is available.

A wrong device selection can result in data loss.

If the storage device contains irreplaceable or highly valuable data and appears to be physically failing, consider using a professional data recovery service instead of repeatedly powering or reading the device.

---

## Project Status

### Basic Recovery

**Status: Completed and tested**

Basic Recovery is the stable image-first recovery workflow of the **Foremost Recovery Toolkit**.

Development of the Basic workflow is considered complete.

### Advanced Recovery

Advanced Recovery is intended to extend the toolkit with more sophisticated recovery capabilities for problematic storage devices.

---

## Disclaimer

This software is provided for data recovery and educational purposes.

The user is responsible for selecting the correct source and destination devices and for understanding the disk operations being performed.

The author accepts no responsibility for data loss, hardware damage, accidental overwrites, incorrect device selection, or other damage resulting from the use or misuse of this software.

---

## License

Choose a license before publicly distributing the project.

Common open-source options include:

- MIT License
- GNU General Public License v3.0

Add the selected license as:

```text
LICENSE
```

in the root of the repository.

---

## Foremost Recovery Toolkit

**Image first. Verify the image. Recover from the copy.**