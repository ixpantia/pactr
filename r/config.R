# config.R

#' Ruta absoluta de una variable de ambiente, resuelta desde la raíz
#'
#' Falla temprano si la variable no está definida en el `.Renviron`, para no
#' arrastrar una ruta vacía hasta el punto en que se intenta leer el archivo.
#'
#' @param variable Nombre de la variable de ambiente que contiene la ruta.
#' @return La ruta absoluta, resuelta con `here()` desde la raíz del proyecto.
ruta_proyecto <- function(variable) {
  valor <- Sys.getenv(variable)
  if (valor == "") {
    stop("Falta la variable ", variable, " en el archivo .Renviron")
  }
  here(valor)
}

# --- Configuración del Contrato de Datos ---
contract_file_path <- ruta_proyecto("CONTRACT_FILE_PATH")

# --- Configuración de la Base de Datos ---
# Tipo de base de datos: "sqlite", "postgres", "sql_server"
db_type <- tolower(Sys.getenv("DB_TYPE"))
dbname <- Sys.getenv("BASE_DE_DATOS")
# Ruta al archivo de base de datos; solo se usa con db_type = "sqlite"
sqlite_db_path <- if (db_type == "sqlite") {
  ruta_proyecto("BASE_DE_DATOS")
} else {
  ""
}
# En el caso de SQLite, esta variable no se utilizará
host <- Sys.getenv("SERVIDOR")
# En el caso de SQLite, esta variable no se utilizará
user <- Sys.getenv("USUARIO_DB")
# En el caso de SQLite, esta variable no se utilizará
password_env_var <- "CONTRASENA_DB"
# Puerto del servidor; hoy solo lo usa db_type = "postgres". Si no está en el
# .Renviron se asume el puerto estándar de PostgreSQL, que es lo habitual.
puerto <- if (nzchar(Sys.getenv("PUERTO_DB"))) {
  Sys.getenv("PUERTO_DB")
} else {
  "5432"
}

# --- Configuración del Generador de Pruebas ---
test_output_dir <- ruta_proyecto("TEST_OUTPUT_DIR")
system_prompt_path <- ruta_proyecto("SYSTEM_PROMPT_PATH")
# Destino de los resultados (.parquet); puede ser una ruta fuera del proyecto,
# por eso no se resuelve con here()
test_results_dir <- Sys.getenv("TEST_RESULTS_DIR")

# --- Configuración del LLM ---
llm_model <- Sys.getenv("LLM_MODEL")
# El LLM se consume a través de un servidor compatible con la API de OpenAI
llm_base_url <- Sys.getenv("LLM_BASE_URL")
llm_api_key <- Sys.getenv("LLM_API_KEY")
# Streaming (SSE) de la respuesta. Se activa por defecto; desactívalo con
# LLM_STREAM=false si el proveedor no lo soporta.
llm_stream <- !tolower(Sys.getenv("LLM_STREAM", "true")) %in% c("false", "0", "no")
