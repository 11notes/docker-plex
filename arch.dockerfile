# ╔═════════════════════════════════════════════════════╗
# ║                       SETUP                         ║
# ╚═════════════════════════════════════════════════════╝
# GLOBAL
  ARG BUILD_BIN=/plex.deb \
      APP_VERSION=1.42.1


# :: FOREIGN IMAGES
  FROM 11notes/util:bin AS util-bin
  FROM 11notes/util AS util
  FROM 11notes/distroless:localhealth AS distroless-localhealth

# ╔═════════════════════════════════════════════════════╗
# ║                       BUILD                         ║
# ╚═════════════════════════════════════════════════════╝
# :: PLEX PACKAGE
  FROM alpine AS package
  COPY --from=util-bin / /
  COPY ./key.txt /
  ARG APP_VERSION \
      BUILD_BIN \
      TARGETARCH \
      TARGETVARIANT

  RUN set -ex; \
    apk --update --no-cache add \
      curl \
      jq \
      wget \
      gpg \
      gpg-agent;
 
  RUN set -ex; \
    gpg --import /key.txt;

  RUN set -ex; \
    BUILD_VERSION=$(curl -s https://plex.tv/api/downloads/5.json | jq -r '.computer.Linux.version'); \
    eleven log info "found build ${BUILD_VERSION}"; \
    if echo ${BUILD_VERSION} | grep -q ${APP_VERSION}; then \
      case "${TARGETARCH}${TARGETVARIANT}" in \
        "armv7") \
          export TARGETVARIANT=hf; \
        ;; \
      esac; \
      wget -q --show-progress --progress=bar:force -O ${BUILD_BIN} https://downloads.plex.tv/plex-media-server-new/${BUILD_VERSION}/debian/plexmediaserver_${BUILD_VERSION}_${TARGETARCH}${TARGETVARIANT}.deb; \
      gpg --verify ${BUILD_BIN}; \
    else \
      eleven log error "${APP_VERSION} and ${BUILD_VERSION} do not match!"; \
      exit 1; \
    fi;

# :: FILE SYSTEM
  FROM alpine AS file-system
  COPY --from=util / /
  ARG APP_ROOT

  RUN set -ex; \
    eleven mkdir /distroless${APP_ROOT}/{etc,tmp};

# :: PLEX
  FROM 11notes/debian:stable AS build
  ARG BUILD_BIN
  COPY --from=util / /
  COPY --from=distroless-localhealth / /
  COPY --from=package ${BUILD_BIN} /
  COPY ./rootfs /

  USER root

  RUN set -ex; \
    dpkg -i ${BUILD_BIN};

  RUN set -ex; \
    rm ${BUILD_BIN}; \
    apt-get clean; \
    chmod +x -R \
      /usr/local/bin;

  RUN set -ex; \
    for FOLDER in /tmp/* /root/*; do \
      rm -rf ${FOLDER}; \
    done;

# ╔═════════════════════════════════════════════════════╗
# ║                       IMAGE                         ║
# ╚═════════════════════════════════════════════════════╝
# :: HEADER
  FROM scratch

  # :: default arguments
    ARG TARGETPLATFORM \
        TARGETOS \
        TARGETARCH \
        TARGETVARIANT \
        APP_IMAGE \
        APP_NAME \
        APP_VERSION \
        APP_ROOT \
        APP_UID \
        APP_GID \
        APP_NO_CACHE

  # :: default environment
    ENV APP_IMAGE=${APP_IMAGE} \
        APP_NAME=${APP_NAME} \
        APP_VERSION=${APP_VERSION} \
        APP_ROOT=${APP_ROOT}

  # :: app specific environment
    ENV HOME=${APP_ROOT}/etc \
        PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR="${APP_ROOT}/etc/Library/Application Support" \
        PLEX_MEDIA_SERVER_HOME=/usr/lib/plexmediaserver \
        PLEX_MEDIA_SERVER_MAX_PLUGIN_PROCS=6 \
        PLEX_MEDIA_SERVER_INFO_VENDOR="Docker" \
        PLEX_MEDIA_SERVER_INFO_DEVICE="Container" \
        NVIDIA_DRIVER_CAPABILITIES="compute,video,utility,graphics" \
        TMPDIR=${APP_ROOT}/tmp

  # :: multi-stage
    COPY --from=build / /
    COPY --from=file-system --chown=${APP_UID}:${APP_GID} /distroless/ /

# :: PERSISTENT DATA
  VOLUME ["${APP_ROOT}/etc"]

# :: HEALTH
  HEALTHCHECK --interval=5s --timeout=2s --start-interval=5s \
    CMD ["/usr/local/bin/localhealth", "http://127.0.0.1:32400/identity"]

# :: EXECUTE
  USER ${APP_UID}:${APP_GID}
  ENTRYPOINT ["/usr/local/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]