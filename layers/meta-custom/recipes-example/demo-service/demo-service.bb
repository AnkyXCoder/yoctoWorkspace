SUMMARY = "Demo systemd service example"
DESCRIPTION = "Simple systemd service for Yocto learning"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

python do_display_banner() {
    bb.plain("***********************************************");
    bb.plain("*                                             *");
    bb.plain("*           Demo Service recipe               *");
    bb.plain("*        created by bitbake-layers            *");
    bb.plain("*                                             *");
    bb.plain("***********************************************");
}

addtask display_banner before do_build

SRC_URI = " \
    file://demo.sh \
    file://demo.service \
"

S = "${WORKDIR}"

inherit systemd

SYSTEMD_SERVICE:${PN} = "demo.service"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 demo.sh ${D}${bindir}/demo-service

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 demo.service ${D}${systemd_system_unitdir}
}

FILES:${PN} += " \
    ${bindir}/demo-service \
    ${systemd_system_unitdir}/demo.service \
"
