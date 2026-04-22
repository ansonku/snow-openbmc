KBRANCH = "aspeed-master-v6.18"
LINUX_VERSION ?= "6.18"

# Tag for v00.08.02
SRCREV = "2b36757eed3c195c219bc8ae12b7c4501d1990d9"
LIC_FILES_CHKSUM = "file://COPYING;md5=6bc538ed5bd9a7fc9398086aedcd7e46"

require linux-aspeed.inc

DEPENDS += "lzop-native"

SRC_URI:append = " file://ipmi_ssif.cfg "
SRC_URI:append = " file://mtd_test.cfg "
SRC_URI:append = " file://crpyto_manager.cfg "
SRC_URI:append:spi-nor-ecc = " file://jffs2_writebuffer.cfg "
