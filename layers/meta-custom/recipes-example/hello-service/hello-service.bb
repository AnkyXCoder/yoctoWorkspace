SUMMARY = "Hello World C++ systemd service"
DESCRIPTION = "Prints Hello World and PID as a systemd service"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

python do_display_banner() {
    bb.plain("***********************************************");
    bb.plain("*                                             *");
    bb.plain("*            Hello World recipe               *");
    bb.plain("*        created by bitbake-layers            *");
    bb.plain("*                                             *");
    bb.plain("***********************************************");
}

addtask display_banner before do_build

SRC_URI = " \
    file://CMakeLists.txt \
    file://hello.cpp \
    file://hello.service \
"

S = "${WORKDIR}"

inherit cmake systemd

TARGET_CC_ARCH += "${LDFLAGS}"
SYSTEMD_SERVICE:${PN} = "hello.service"

do_compile() {
    install -d ${B}
    ${CXX} ${CXXFLAGS} ${S}/hello.cpp -o ${B}/hello-service
}

do_install:append() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${S}/hello.service \
        ${D}${systemd_system_unitdir}
}

FILES:${PN} += " \
    ${bindir}/hello-service \
    ${systemd_system_unitdir}/hello.service \
"
