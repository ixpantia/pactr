library(RPostgres)

#' Conecta con la base de datos PostgreSQL
#'
#' La contraseña se lee de la variable de entorno indicada, nunca del código.
#'
#' @return Una conexión DBI abierta.
conectar_db <- function() {
  # Asegúrate de que las variables de entorno para PostgreSQL estén configuradas
  dbConnect(RPostgres::Postgres(),
            host = "{{host}}",
            port = {{puerto}},
            user = "{{usuario}}",
            password = Sys.getenv("{{var_entorno_contrasena}}"),
            dbname = "{{base_de_datos}}")
}

#' Obtiene el esquema de una tabla
#'
#' Los nombres de `information_schema.columns` se renombran a los que esperan
#' las pruebas (`name`, `type`, `notnull`, `dflt_value`).
#'
#' @param con Conexión DBI a la base de datos.
#' @param tabla Nombre de la tabla.
#' @return Un data frame con el esquema de la tabla.
obtener_esquema_tabla <- function(con, tabla) {
  # Para PostgreSQL, obtenemos el esquema de information_schema.columns
  # Mapeamos nombres de columnas a la salida esperada por las pruebas (name, type, etc.)
  query <- paste0("SELECT column_name as name, data_type as type, is_nullable as notnull, column_default as dflt_value FROM information_schema.columns WHERE table_name = '", tabla, "'")
  dbGetQuery(con, query)
}
