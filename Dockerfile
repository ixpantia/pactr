# Generador de pruebas del contrato de datos.
#
# El punto de entrada es r/validar_contrato.R: lee el contrato, consulta al LLM,
# escribe las pruebas en TEST_OUTPUT_DIR y verifica que cubran todas las reglas.
# No ejecuta las pruebas ni abre la base de datos; de eso se encarga run_tests.R.
#
# La imagen base debe ser R 4.5.x sobre Ubuntu noble: rproject.toml fija
# r_version = "4.5" y, si no coincide, rv/scripts/activate.R entra en modo seguro
# y apunta la librería a un directorio temporal vacío.

ARG R_VERSION=4.5.1
ARG RV_VERSION=0.19.0

# --- Etapa 1: resolver las dependencias de R con rv ------------------------
FROM rocker/r-ver:${R_VERSION} AS builder

ARG RV_VERSION

# Dependencias de compilación según `rv sysdeps`. P3M sirve binarios para noble,
# así que normalmente no se compila nada; están aquí como red de seguridad por si
# algún paquete del lockfile no tuviera binario disponible.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        cmake \
        curl \
        libcurl4-openssl-dev \
        libicu-dev \
        libpq-dev \
        libssl-dev \
        libuv1-dev \
        libx11-dev \
        libxml2-dev \
        make \
        pandoc \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL \
      "https://github.com/A2-ai/rv/releases/download/v${RV_VERSION}/rv-v${RV_VERSION}-x86_64-unknown-linux-gnu.tar.gz" \
      | tar -xz -C /tmp \
    && find /tmp -name rv -type f -perm -u+x -exec install -m 0755 {} /usr/local/bin/rv \; \
    && rv --version

WORKDIR /app

# Solo lo que rv necesita para resolver, y antes que el código fuente: así
# editar un .R no invalida la capa de `rv sync`, que es la cara de construir.
COPY rproject.toml rv.lock ./

RUN rv sync

# --- Etapa 2: imagen de ejecución -----------------------------------------
FROM rocker/r-ver:${R_VERSION}

# Únicas bibliotecas del sistema que rocker/r-ver no trae ya y que la librería
# necesita en ejecución: libpq5 para RPostgres, libxml2 y libuv1 para xml2 y
# languageserver. El resto son dependencias transitivas de libcurl, libssl y
# libicu, contra las que R ya está enlazado.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libpq5 \
        libuv1t64 \
        libxml2 \
    && rm -rf /var/lib/apt/lists/*

# El .Rprofile del proyecto ejecuta rv/scripts/activate.R, que llama a `rv info`
# para fijar .libPaths(). Sin el binario en la imagen final, R arrancaría sin la
# librería del proyecto.
COPY --from=builder /usr/local/bin/rv /usr/local/bin/rv

# Usuario sin privilegios: el contenedor recibe la clave del LLM por el entorno.
# El UID 1000 coincide con el usuario habitual del host, para que el volumen
# montado sobre /app/tests sea escribible. Si tu UID es otro, ejecuta con
# `--user "$(id -u):$(id -g)"`.
#
# Se crea ANTES de copiar y la propiedad se fija con `COPY --chown`. Un
# `chown -R` posterior reescribiría cada archivo en una capa nueva y duplicaría
# la librería de R entera: son 100 MB de más en la imagen final.
RUN useradd --uid 1000 --create-home --shell /bin/bash app

WORKDIR /app

# /app debe pertenecer a `app`, no solo su contenido: el generador escribe
# run_tests.R en la raíz del proyecto.
RUN mkdir -p /app/tests && chown app:app /app /app/tests

COPY --from=builder --chown=app:app /app/rv/library ./rv/library
COPY --chown=app:app rv/scripts ./rv/scripts
COPY --chown=app:app rproject.toml rv.lock .Rprofile ./
COPY --chown=app:app r/ ./r/
COPY --chown=app:app plantillas/ ./plantillas/
COPY --chown=app:app prompts/ ./prompts/
COPY --chown=app:app contrato/ ./contrato/

# Ancla para here(). Dentro de la imagen no hay .git ni .Rproj, así que sin este
# archivo here() no tendría ningún criterio que reconocer para fijar la raíz.
RUN touch .here

USER app

# La configuración llega en tiempo de ejecución (`--env-file`). El generador usa
# LLM_BASE_URL, LLM_API_KEY, LLM_MODEL (y LLM_STREAM, opcional), DB_TYPE, BASE_DE_DATOS, CONTRACT_FILE_PATH,
# SYSTEM_PROMPT_PATH y TEST_OUTPUT_DIR. No necesita credenciales de base de datos
# ni TEST_RESULTS_DIR.
ENTRYPOINT ["Rscript", "r/validar_contrato.R"]
