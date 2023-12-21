# Cloudinit

Use Carvel `ytt` to generate Cloudinit user data files from a common base and VM-specific parameters

## Usage

1. Upload the `cloudinit` and `proxmox` directories to the Proxmox node
2. Configure and run the generate.sh scripts in the subdirectories to create cloudinit user data configuration files
3. Run `proxmox/newvm` referencing the appropriate cloudinit configuration