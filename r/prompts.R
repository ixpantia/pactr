# prompts.R
#
# Arma los dos prompts que recibe el LLM: el de sistema, común a toda la
# corrida, y el de usuario, uno por tabla del contrato.
#
# El texto vive en `prompts/` y no en este script, para que ajustar la redacción
# de un prompt no obligue a tocar código R. `r/plantillas.R` define
# `renderizar_plantilla()`, que aquí se reutiliza sobre el directorio `prompts/`.

library(here)
library(readr)

#' Ruta absoluta de un archivo del directorio `prompts/`
#'
#' @param nombre Nombre del archivo de prompt, con extensión.
#' @return La ruta absoluta al archivo, resuelta desde la raíz del proyecto.
ruta_prompt <- function(nombre) {
  ruta <- here("prompts", nombre)
  if (!file.exists(ruta)) {
    stop("No se encontró el prompt: ", ruta, call. = FALSE)
  }
  ruta
}

#' Lee un prompt y sustituye sus marcadores `{{clave}}`
#'
#' @param nombre Nombre del archivo en `prompts/`.
#' @param valores Lista nombrada; cada nombre `clave` reemplaza a `{{clave}}`.
#' @return El texto del prompt con los valores sustituidos.
renderizar_prompt <- function(nombre, valores = list()) {
  texto <- read_file(ruta_prompt(nombre))

  for (clave in names(valores)) {
    texto <- gsub(
      paste0("{{", clave, "}}"),
      valores[[clave]],
      texto,
      fixed = TRUE
    )
  }

  texto
}

#' Descripción del motor de base de datos para el LLM
#'
#' Le explica al modelo con qué motor trabaja, cómo se llaman los helpers
#' disponibles y qué devuelve `obtener_esquema_tabla()` en ese motor, que
#' difiere entre SQLite (`PRAGMA table_info`) y el resto
#' (`information_schema.columns`).
#'
#' @param db_type Motor de base de datos: "sqlite", "postgres" o "sql_server".
#' @return El texto descriptivo, con los datos de conexión ya sustituidos.
describir_db_para_llm <- function(db_type) {
  switch(
    db_type,
    sqlite = renderizar_prompt(
      "db_sqlite.md",
      list(ruta_db = basename(sqlite_db_path))
    ),
    postgres = renderizar_prompt(
      "db_postgres.md",
      list(
        host = host,
        puerto = puerto,
        usuario = user,
        base_de_datos = dbname,
        var_entorno_contrasena = password_env_var
      )
    ),
    sql_server = renderizar_prompt(
      "db_sql_server.md",
      list(
        host = host,
        usuario = user,
        base_de_datos = dbname,
        var_entorno_contrasena = password_env_var
      )
    ),
    stop(
      "Tipo de base de datos no soportado en config.R. ",
      "Actualmente solo 'sqlite' ,'postgres' o sql_server",
      call. = FALSE
    )
  )
}

#' Construye el system prompt completo de la corrida
#'
#' Encadena tres piezas: el system prompt base escrito a mano, la descripción
#' del motor en uso y las instrucciones sobre robustez de las pruebas y el
#' patrón obligatorio de validación de esquema.
#'
#' @param prompt_base Texto de `prompts/system_prompt.md`, ya leído.
#' @param db_type Motor de base de datos: "sqlite", "postgres" o "sql_server".
#' @return El system prompt completo como una única cadena.
construir_system_prompt <- function(prompt_base, db_type) {
  paste0(
    prompt_base,
    "\n\n",
    "--- Información Adicional sobre la Base de Datos y Helpers ---\n",
    describir_db_para_llm(db_type),
    read_file(ruta_prompt("instrucciones_pruebas.md"))
  )
}

#' Construye el prompt de usuario para una tabla del contrato
#'
#' Incluye la lista de identificadores canónicos que las pruebas deben declarar.
#' `r/verificar_cobertura.R` comprueba después que estén todos, así que el
#' prompt advierte al modelo de esa verificación automática.
#'
#' @param tabla Nombre de la tabla, tal como aparece en el contrato.
#' @param seccion Texto markdown de la sección del contrato de esa tabla.
#' @param ids Identificadores canónicos que las pruebas deben cubrir.
#' @return El prompt de usuario como una única cadena.
construir_user_prompt <- function(tabla, seccion, ids) {
  renderizar_prompt(
    "prompt_tabla.md",
    list(
      tabla = tabla,
      seccion = seccion,
      primer_id = ids[1],
      lista_ids = paste0("- ", ids, collapse = "\n")
    )
  )
}
