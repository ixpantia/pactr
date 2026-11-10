#' Conecta con la base de datos Coocique
#' @return odbc Conexión a base de datos Coocique ME
#' @export
conecta_me <- function() {
  # Traer datos ---------------------------------------------------------------
  db_usuario <- Sys.getenv("USUARIO_DB")
  db_contrasena <- Sys.getenv("CONTRASENA_DB")
  db_servidor <- Sys.getenv("SERVIDOR")
  db_base_de_datos <- Sys.getenv("BASE_DE_DATOS")
  if (db_usuario == "") {
    warning(
      "Necesitas crear un archivo .Renviron que contiene la variable ambiental
            USUARIO_DB=<el nombre de usuario>"
    )
  }
  if (db_contrasena == "") {
    warning(
      "Necesitas crear un archivo .Renviron que contiene la variable ambiental
            CONTRASENA_DB=<la contraseña>"
    )
  }
  if (db_servidor == "") {
    warning(
      "Necesitas crear un archivo .Renviron que contiene la variable ambiental
            SERVIDOR=<la dirección del servidor>"
    )
  }
  conn <- odbc::dbConnect(
    drv = odbc::odbc(),
    driver = "ODBC Driver 17 for SQL Server",
    server = db_servidor,
    database = db_base_de_datos,
    uid = db_usuario,
    pwd = db_contrasena
  )
}
