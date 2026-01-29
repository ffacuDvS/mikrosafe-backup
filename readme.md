<p align="center">
  <img src="assets/logo.png" alt="MikroSafe Backup" width="200">
</p>

Automated backup system for MikroTik devices using SSH/SCP, password fallback, compression, and email reporting.

---

## 📌 Overview

**MikroSafe** is a Bash-based automation tool designed for NOC / ISP environments to reliably extract configuration backups from MikroTik devices, package them, and distribute the results via email.

The script is designed with:

* Fail-fast execution
* Clear separation of configuration and logic
* Support for password-based authentication (with optional SSH keys)
* Audit-friendly logging

---

## 🎯 Key Features

* Batch backup of multiple MikroTik devices
* Supports grouped devices (for organization)
* Password rotation fallback (`sshpass`)
* Automatic ZIP compression
* Email delivery with attachment
* Log retention and cleanup policy
* Non-interactive, cron-friendly execution

---

## ⚡ Quick Start

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/ffacuDvS/mikrosafe-backup
    cd mikrosafe-backup
    ```

2.  **Configure the environment:**
    ```bash
    cp database/credentials.env.example database/credentials.env
    nano database/credentials.env
    # Edit SSH_USER, SSH_PASSWORDS, FROM_EMAIL, etc.
    ```

3.  **Add your devices:**
    ```bash
    nano database/mikrosafe-mkts.list
    # Add lines in NAME:IP:GROUP format
    ```

4.  **Set up email (optional but recommended):**
    ```bash
    nano ~/.msmtprc
    # Configure your SMTP settings
    chmod 600 ~/.msmtprc
    ```

5.  **Deploy the backup script to MikroTik devices (one-time):**
    ```bash
    ./deploy_backup_script.sh
    ```

6.  **Run a manual backup test:**
    ```bash
    ./mikrosafe.sh
    ```
    Check the `outbox/` directory and your email.

7.  **Schedule automatic execution:**
    Add a cron job (see example in [Cron Job](#-example-cron-job) section).

---

## 📂 Project Structure

```
mikrosafe-backup
├── assets
│   ├── backup_script.rsc
│   ├── email_template.html
│   └── logo.png
├── database
│   ├── credentials.env
│   ├── emails.list
│   ├── mikrosafe-mkts.list
│   ├── error-log.txt
│   └── activity-log.txt
├── deploy_backup_script.sh
├── LICENSE
├── mikrosafe.sh
└── readme.md
```

---

## ⚙️ Requirements

* Bash >= 4.0
* `scp`
* `sshpass` (for password fallback)
* `zip`
* `msmtp`
* `base64`

---

## 🔐 Security Model

### Authentication Priority

1. SSH keys (if configured and accepted by MikroTik)
2. Password-based authentication using `sshpass`

> If SSH keys are not available or supported, the script works **fully** using passwords defined in `credentials.env`.

---

## 🧩 Configuration Files

### `deploy_backup_script.sh`

Deploys `assets/backup_script.rsc` to all MikroTik devices listed in `database/mikrosafe-mkts.list` using credentials from `database/credentials.env`.

### `credentials.env`

Environment-based secret storage.

Example:

```
SSH_USER=admin
SSH_PASSWORDS="pass1 pass2 pass3"
SSH_TIMEOUT=10
SSH_PORT=22
FROM_EMAIL=mikrosafe@localhost
```

Notes:

* Passwords are space-separated
* Multiple passwords allow credential rotation

---

### `mikrosafe-mkts.list`

List of MikroTik devices to back up.

Format:

```
NAME:IP:GROUP
```

Example:

```
core01:192.168.1.1:core
edge02:192.168.2.1:edges
```

---

### `emails.list`

List of recipients for backup reports.

Example:

```
noc@example.com
admin@example.com
```

---

### `.msmtprc`

This is the configuration file used by msmtp, an SMTP client, to define how email messages should be sent.
It is typically located at `~/.msmtprc`.

Example:

```
account default
host <HOST_MAIL> # EXAMPLE: smtp.gmail.com
port 587
from <YOUR_MAIL> # EXAMPLE: example@domain.com
auth on
user <YOUR_MAIL> # EXAMPLE: example@domain.com
password <YOUR_MAIL_PASSWORD> # EXAMPLE: superpassword_123!
tls on
tls_certcheck off
```

After that, I recommend typing: `chmod 600 ~/.msmtprc`

---

### `backup_script.rsc`

This file, located at `assets/backup_script.rsc`, contains the RouterOS commands required to create and enable both the backup script and the scheduler responsible for generating daily configuration exports on each MikroTik device.

The script performs the following actions:

1. Generates a /export of the running configuration
2. Creates a /system backup save
3. Schedules a daily execution via RouterOS scheduler

```bash
/system script
remove [find name=mikrosafe_backup]
add name=mikrosafe_backup dont-require-permissions=yes source={
    /export file=mikrosafebackup;
    /system backup save name=mikrosafebackup password=
}
run mikrosafe_backup

/system scheduler
remove [find name=mikrosafe_scheduler]
add name=mikrosafe_scheduler interval=1d start-time=00:05:00 on-event="/system script run mikrosafe_backup" policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon
```

When running `deploy_backup_script.sh` (located at the project root), the script performs a full sweep of all devices listed in `database/mikrosafe-mkts.list`, automatically deploying the required RouterOS script and scheduler on each MikroTik device.
If only a single new device needs to be added and a full sweep is not desired, the contents of `backup_script.rsc` can be manually copied and executed directly on the target MikroTik via its terminal.

---

## 🚀 How It Works

### 1. Environment Validation

* Verifies required files
* Loads `.env` securely
* Enforces strict Bash mode:

  * `-e` exit on error
  * `-u` undefined variable protection
  * `pipefail` error propagation

---

### 2. Backup Execution

For each device:

* Attempts SCP without password (SSH key)
* Falls back to password attempts sequentially
* Logs failures without stopping the run

Backups are stored as:

```
<GROUP>_<NAME>_<DATE>.rsc
```

---

### 3. Compression

* All backups + error log are zipped
* Output stored in `outbox/`

---

### 4. Email Reporting

* Sends ZIP file as attachment
* Uses MIME multipart
* Compatible with `msmtp`

---

### 5. Cleanup Policy

* Keeps last **3 ZIP files** in `outbox/`
* Clears temporary backup directory

---

## 🧪 Example Cron Job

```
0 2 * * * /path/to/mikrosafe/mikrosafe.sh >/dev/null 2>&1
```

---

## 📜 Logging

### Error Log

`database/error-log.txt`

Contains:

* Timestamp
* Device name
* Failure reason

---

### Activity Log

`database/activity-log.txt`

Contains:

* Execution timestamps
* Successful run confirmation

---

## 📄 License

MIT License

You are free to:

* Use
* Modify
* Distribute

You are **not protected** from misuse, illegal usage, or commercial forks.

---

## ⚠️ Disclaimer

This tool is intended for **authorized auditing and backup operations only**.

The author assumes no responsibility for:

* Unauthorized access
* Misuse
* Damage caused by improper deployment

---

## 🧠 Target Audience

* ISPs
* NOC teams
* Network administrators
* Security auditors

---

## 🔮 Roadmap (Suggested)

* Encrypted backup storage
* Per-device credentials
* Web dashboard
* GPG-signed backups

---

## 👤 Author

**Facundo Alarcón ( @ffacu.dvs )**
