#!/bin/bash
#
# Helper script to launch QEMU for OpenBMC with pre-configured port forwarding.
#

# Check if the build environment is initialized
if [ -z "$BUILDDIR" ]; then
	echo "Error: Build environment not detected. Please run '. setup <machine>' first."
	exit 1
fi

# QB_SLIRP_OPT: Configures QEMU networking to forward host ports:
# - 10443 -> 443 (HTTPS/WebUI)
# - 10022 -> 22  (SSH)
export QB_SLIRP_OPT="-netdev user,id=net0,hostfwd=tcp::10443-:443,hostfwd=tcp::10022-:22"

echo "Starting QEMU with port forwarding..."
echo "HTTPS: https://localhost:10443"
echo "SSH:   ssh -p 10022 root@localhost"

# Launch QEMU:
# - nographic: Redirect serial output to console
# - slirp: Use user-mode networking
runqemu nographic slirp
