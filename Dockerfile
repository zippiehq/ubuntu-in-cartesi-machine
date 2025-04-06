ARG UBUNTU_TAG=noble-20250127
ARG APT_UPDATE_SNAPSHOT=20250127T030400Z


FROM ubuntu:${UBUNTU_TAG}@sha256:72297848456d5d37d1262630108ab308d3e9ec7ed1c3286a32fe09856619a782 AS base-build
ARG APT_UPDATE_SNAPSHOT
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates
RUN apt-get update --snapshot=${APT_UPDATE_SNAPSHOT}
RUN apt-get install --snapshot=${APT_UPDATE_SNAPSHOT} -y --no-install-recommends ca-certificates curl git debootstrap patch libarchive13 e2tools lua5.4 libslirp0

ENV TZ=UTC
ENV LC_ALL=C
ENV LANG=C.UTF-8
ENV LC_CTYPE=C.UTF-8
ENV SOURCE_DATE_EPOCH=1743924079

# XXX this does all sorts of weird apt-get installs and should be a separate build
RUN git clone https://github.com/cartesi/genext2fs /genext2fs && cd /genext2fs && git checkout v1.5.2 && ./make-debian
RUN dpkg -i /genext2fs/genext2fs.deb

RUN debootstrap --include=wget,busybox-static --foreign --arch riscv64 noble /replicate/release https://snapshot.ubuntu.com/ubuntu/${APT_UPDATE_SNAPSHOT}
RUN rm -rf /replicate/release/debootstrap/debootstrap.log
RUN touch /replicate/release/debootstrap/debootstrap.log
RUN echo -n "ubuntu" > /replicate/release/etc/hostname
RUN echo "nameserver 127.0.0.1" > /replicate/release/etc/resolv.conf
RUN rm -df /replicate/release/proc
RUN mkdir -p /replicate/release/proc
RUN chmod 555 /replicate/release/proc

COPY bootstrap /replicate/release/debootstrap/bootstrap
RUN chmod 755 /replicate/release/debootstrap/bootstrap
COPY copy /replicate/release/debootstrap/copy
RUN chmod 755 /replicate/release/debootstrap/copy

RUN find "/replicate/release" \
	-newermt "@$SOURCE_DATE_EPOCH" \
	-exec touch --no-dereference --date="@$SOURCE_DATE_EPOCH" '{}' +
RUN tar --sort=name -C /replicate/release -vcf - . > /replicate/release.tar
RUN HOSTNAME=linux SOURCE_DATE_EPOCH=$SOURCE_DATA_EPOCH genext2fs -z -v -v -f -a /replicate/release.tar -B 4096 /replicate/source.ext2 2>&1
RUN sha256sum /replicate/source.ext2
RUN curl -OL https://github.com/cartesi/machine-linux-image/releases/download/v0.20.0/linux-6.5.13-ctsi-1-v0.20.0.bin && mkdir -p /usr/share/cartesi-machine/images && mv linux-6.5.13-ctsi-1-v0.20.0.bin /usr/share/cartesi-machine/images/linux.bin
RUN curl -OL https://github.com/cartesi/machine-emulator/releases/download/v0.19.0-alpha3/cartesi-machine-v0.19.0_$(dpkg --print-architecture).deb && apt-get install --snapshot=${APT_UPDATE_SNAPSHOT} -y --no-install-recommends ./cartesi-machine-v0.19.0_arm64.deb && rm -f cartesi-machine-v0.19.0_$(dpkg --print-architecture).deb

RUN truncate -s 2G /image.ext2
# first we make a new file system within the machine and copy all the debootstrap content to it
RUN cartesi-machine --skip-root-hash-check --append-bootargs="loglevel=8 init=/debootstrap/copy ro" --flash-drive=label:root,filename:/replicate/source.ext2 --flash-drive=label:dest,filename:/image.ext2,shared --ram-length=2Gi || true

# then we actually debootstrap
RUN cartesi-machine --skip-root-hash-check --append-bootargs="loglevel=8 init=/debootstrap/bootstrap ro" --flash-drive=label:root,filename:/image.ext2,shared --ram-length=2Gi
RUN sha256sum /image.ext2

COPY run-machine /run-machine
RUN chmod 755 /run-machine

