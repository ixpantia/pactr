library(RSQLite)

#' Conecta con la base de datos SQLite del proyecto
#'
#' @return Una conexión DBI abierta.
conectar_db <- function() {
  db_path <- here("{{ruta_db}}") # Asume que libreria.db está en el directorio raíz o ajusta la ruta
  if (!file.exists(db_path)) {
    stop("Base de datos SQLite no encontrada en: ", db_path)
  }
  dbConnect(RSQLite::SQLite(), db_path)
}

#' Obtiene el esquema de una tabla
#'
#' SQLite expone el esquema con `PRAGMA table_info`.
#'
#' @param con Conexión DBI a la base de datos.
#' @param tabla Nombre de la tabla.
#' @return Un data frame con las columnas `name` y `type`.
obtener_esquema_tabla <- function(con, tabla) {
  query <- paste0("PRAGMA table_info(", tabla, ")")
  result <- dbGetQuery(con, query)
  # Retornar solo las columnas name y type como espera el contrato
  result[, c("name", "type")]
}
