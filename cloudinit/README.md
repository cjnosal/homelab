# Cloudinit

VM setup scripts

## Usage

1. Upload the `base` and VM-specific directories to the VM under /home/ubuntu/init
2. Upload the step CA to the VM under /home/ubuntu/init/certs
3. Upload the required credentials to the VM under /home/ubuntu/init/creds
4. Configure and run VM's `runcmd` script