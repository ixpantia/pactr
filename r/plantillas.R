# plantillas.R
#
# Escribe los archivos que el generador produce y que no dependen del LLM:
# `helpers.R`, `run_tests.R` y la meta-prueba de cobertura.
#
# El contenido de esos archivos vive en `plantillas/` como código R real, no
# como literales dentro de este script: así el editor los formatea y revisa, y
# un error de sintaxis se detecta antes de generar nada. Solo los fragmentos que
# dependen del motor de base de datos llevan marcadores `{{clave}}`.

library(here)
library(readr)

#' Ruta absoluta de un archivo del directorio `plantillas/`
#'
#' @param nombre Nombre del archivo de plantilla, con extensión.
#' @return La ruta absoluta al archivo, resuelta desde la raíz del proyecto.
ruta_plantilla <- function(nombre) {
  ruta <- here("plantillas", nombre)
  if (!file.exists(ruta)) {
    stop("No se encontró la plantilla: ", ruta, call. = FALSE)
  }
  ruta
}

#' Lee una plantilla y sustituye sus marcadores
#'
#' Los marcadores tienen la forma `{{clave}}` y se reemplazan de forma literal,
#' sin interpretar el valor como expresión regular.
#'
#' @param nombre Nombre del archivo en `plantillas/`.
#' @param valores Lista nombrada; cada nombre `clave` reemplaza a `{{clave}}`.
#' @return El texto de la plantilla con los valores sustituidos.
renderizar_plantilla <- function(nombre, valores = list()) {
  texto <- read_file(ruta_plantilla(nombre))

  for (clave in names(valores)) {
    texto <- gsub(
      paste0("{{", clave, "}}"),
      valores[[clave]],
      texto,
      fixed = TRUE
    )
  }

  pendientes <- regmatches(texto, gregexpr("\\{\\{[^}]+\\}\\}", texto))[[1]]
  if (length(pendientes) > 0) {
    stop(
      "La plantilla ",
      nombre,
      " quedó con marcadores sin sustituir: ",
      paste(unique(pendientes), collapse = ", "),
      call. = FALSE
    )
  }

  texto
}

#' Fragmento de `helpers.R` con las funciones propias del motor
#'
#' Cada motor aporta su `conectar_db()` y su `obtener_esquema_tabla()`, que
#' consultan el catálogo de forma distinta (`PRAGMA table_info` en SQLite,
#' `information_schema.columns` en PostgreSQL y SQL Server).
#'
#' @param db_type Motor de base de datos: "sqlite", "postgres" o "sql_server".
#' @return El texto del fragmento, con los datos de conexión ya sustituidos.
helpers_del_motor <- function(db_type) {
  switch(
    db_type,
    sqlite = renderizar_plantilla(
      "helpers_sqlite.R",
      list(ruta_db = basename(sqlite_db_path))
    ),
    postgres = renderizar_plantilla(
      "helpers_postgres.R",
      list(
        host = host,
        puerto = puerto,
        usuario = user,
        base_de_datos = dbname,
        var_entorno_contrasena = password_env_var
      )
    ),
    sql_server = renderizar_plantilla(
      "helpers_sql_server.R",
      list(
        host = host,
        usuario = user,
        base_de_datos = dbname,
        var_entorno_contrasena = password_env_var
      )
    ),
    stop(
      "Tipo de base de datos no soportado en config.R. ",
      "Actualmente solo 'sqlite', 'postgres' o 'sql_server'",
      call. = FALSE
    )
  )
}

#' Escribe `helpers.R` en el directorio de pruebas
#'
#' El archivo se arma con tres piezas: un preámbulo común, las funciones de
#' conexión y esquema del motor en uso, y las funciones de validación genéricas
#' (`comparar_tipo_sql()`, `validar_unicidad()`, etc.).
#'
#' @param db_type Motor de base de datos: "sqlite", "postgres" o "sql_server".
#' @param dir_destino Directorio de pruebas donde se escribe el archivo.
#' @return La ruta del archivo escrito, de forma invisible.
escribir_helpers <- function(db_type, dir_destino) {
  contenido <- paste0(
    read_file(ruta_plantilla("helpers_base.R")),
    helpers_del_motor(db_type),
    read_file(ruta_plantilla("helpers_generico.R"))
  )

  ruta <- file.path(dir_destino, "helpers.R")
  cat("Creando archivo helpers.R dinámico para", db_type, "\n")
  write_file(contenido, ruta)
  invisible(ruta)
}

#' Escribe `run_tests.R` en la raíz del proyecto
#'
#' Es el script que ejecuta las pruebas generadas contra la base de datos y
#' escribe los resultados a parquet. No depende del motor, así que se copia tal
#' cual desde la plantilla.
#'
#' @return La ruta del archivo escrito, de forma invisible.
escribir_run_tests <- function() {
  ruta <- here("run_tests.R")
  cat("Creando archivo run_tests.R en el directorio raíz\n")
  write_file(read_file(ruta_plantilla("run_tests.R")), ruta)
  invisible(ruta)
}

#' Escribe la meta-prueba de cobertura del contrato
#'
#' Se escribe como un archivo de prueba más para que la cobertura quede
#' registrada en el parquet junto al resto de resultados, y no solo en la salida
#' del generador.
#'
#' @param dir_destino Directorio de pruebas donde se escribe el archivo.
#' @return La ruta del archivo escrito, de forma invisible.
escribir_meta_prueba_cobertura <- function(dir_destino) {
  ruta <- file.path(dir_destino, "test_cobertura_contrato.R")
  cat("Creando meta-prueba de cobertura:", ruta, "\n")
  write_file(read_file(ruta_plantilla("test_cobertura_contrato.R")), ruta)
  invisible(ruta)
}
