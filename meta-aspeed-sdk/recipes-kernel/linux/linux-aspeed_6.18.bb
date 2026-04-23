KBRANCH = "aspeed-master-v6.18"
LINUX_VERSION ?= "6.18"

# Tag for v00.08.02
SRCREV = "2ce38b090092614cc8789af67b30c73e5d7e13d1"
LIC_FILES_CHKSUM = "file://COPYING;md5=6bc538ed5bd9a7fc9398086aedcd7e46"

require linux-aspeed.inc

DEPENDS += "lzop-native"

SRC_URI:append = " file://ipmi_ssif.cfg "
SRC_URI:append = " file://mtd_test.cfg "
SRC_URI:append = " file://crpyto_manager.cfg "
SRC_URI:append:spi-nor-ecc = " file://jffs2_writebuffer.cfg "
