
# --- Comparación de tipos entre el contrato y la base de datos ---

#' Normaliza un tipo SQL para poder compararlo
#'
#' Pasa a minúsculas, quita la especificación de longitud o precisión
#' (varchar(100) -> varchar, decimal(10,2) -> decimal) y los espacios sobrantes.
#'
#' @param tipo Tipo SQL tal como lo declara el contrato o lo reporta el motor.
#' @return El tipo normalizado.
normalizar_tipo_sql <- function(tipo) {
  tipo <- tolower(trimws(as.character(tipo)))
  tipo <- gsub("\\(.*\\)", "", tipo)
  trimws(tipo)
}

#' Familias de tipos equivalentes en SQLite, PostgreSQL y SQL Server
#'
#' Se comparan por familia porque cada motor reporta el mismo tipo lógico con
#' otro nombre: el contrato declara "varchar" pero SQLite devuelve "TEXT" y
#' PostgreSQL "character varying".
familias_tipo_sql <- list(
  entero = c("int", "integer", "int2", "int4", "int8", "bigint", "smallint",
             "tinyint", "mediumint", "serial", "bigserial", "smallserial"),
  numerico = c("numeric", "decimal", "dec", "float", "float4", "float8", "real",
               "double", "double precision", "money", "smallmoney", "number",
               "numérico"),
  texto = c("char", "character", "varchar", "character varying", "varchar2",
            "nchar", "nvarchar", "national character varying", "text", "ntext",
            "clob", "string", "uniqueidentifier"),
  fecha = c("date"),
  fecha_hora = c("datetime", "datetime2", "smalldatetime", "datetimeoffset",
                 "timestamp", "timestamptz", "timestamp without time zone",
                 "timestamp with time zone", "dttm"),
  logico = c("bool", "boolean", "bit"),
  binario = c("blob", "binary", "varbinary", "bytea", "image")
)

#' Familia a la que pertenece un tipo SQL
#'
#' @param tipo Tipo SQL, normalizado o no.
#' @return El nombre de la familia, o `NA` si el tipo no está catalogado.
familia_tipo_sql <- function(tipo) {
  tipo <- normalizar_tipo_sql(tipo)
  for (familia in names(familias_tipo_sql)) {
    if (tipo %in% familias_tipo_sql[[familia]]) {
      return(familia)
    }
  }
  NA_character_
}

#' Compara un único tipo esperado contra el tipo real de la base de datos
#'
#' @param esperado Tipo declarado en el contrato, ya normalizado.
#' @param actual Tipo reportado por el motor, ya normalizado.
#' @return `TRUE` si son equivalentes.
comparar_tipo_sql_simple <- function(esperado, actual) {
  if (esperado == actual) {
    return(TRUE)
  }

  familia_esperada <- familia_tipo_sql(esperado)
  familia_actual <- familia_tipo_sql(actual)

  if (!is.na(familia_esperada) && !is.na(familia_actual)) {
    return(familia_esperada == familia_actual)
  }

  # Tipos no catalogados: se cae a coincidencia por subcadena, como último
  # recurso y sin interpretar el texto como expresión regular.
  grepl(esperado, actual, fixed = TRUE)
}

#' Compara el tipo del contrato con el tipo real de la base de datos
#'
#' El contrato puede declarar varias alternativas separadas por "/" o "|" (por
#' ejemplo "date/text", usado cuando SQLite almacena las fechas como TEXT);
#' basta con que el tipo real coincida con una de ellas.
#'
#' @param expected_type Tipo declarado en el contrato, textual.
#' @param actual_type Tipo reportado por el motor de base de datos.
#' @return `TRUE` si son equivalentes para el motor en uso.
comparar_tipo_sql <- function(expected_type, actual_type) {
  actual <- normalizar_tipo_sql(actual_type)

  if (length(expected_type) != 1 || length(actual) != 1 ||
      is.na(expected_type) || is.na(actual)) {
    return(FALSE)
  }

  alternativas <- normalizar_tipo_sql(
    strsplit(as.character(expected_type), "[/|]")[[1]]
  )
  alternativas <- alternativas[nzchar(alternativas)]

  if (length(alternativas) == 0) {
    return(FALSE)
  }

  any(vapply(
    alternativas,
    comparar_tipo_sql_simple,
    logical(1),
    actual = actual
  ))
}

#' Valida que un valor de R sea del tipo esperado
#'
#' @param valor Valor leído de la base de datos.
#' @param tipo_esperado Nombre del tipo esperado, según el contrato.
#' @return `TRUE` si el valor corresponde al tipo; `FALSE` si no, o si el tipo
#'   no está contemplado.
validar_tipo_r <- function(valor, tipo_esperado) {
  switch(tipo_esperado,
         "integer" = is.integer(valor) || (is.numeric(valor) && valor == as.integer(valor)),
         "numeric" = is.numeric(valor),
         "character" = is.character(valor),
         "logical" = is.logical(valor),
         "char" = is.character(valor),
         "numérico" = is.numeric(valor),
         "date" = inherits(valor,"Date"),
         "dttm" = inherits(valor,"POSIXt"),
         FALSE)
}

#' Valida que una columna no tenga valores duplicados
#'
#' @param con Conexión DBI a la base de datos.
#' @param tabla Nombre de la tabla.
#' @param columna Nombre de la columna que debe ser única.
#' @return `TRUE` si no hay duplicados.
validar_unicidad <- function(con, tabla, columna) {
  query <- paste0("SELECT COUNT(", columna, ") - COUNT(DISTINCT ", columna, ") as duplicados FROM ", tabla)
  result <- dbGetQuery(con, query)
  result$duplicados == 0
}

#' Valida la integridad referencial de una llave foránea
#'
#' @param con Conexión DBI a la base de datos.
#' @param tabla_hija Tabla que contiene la llave foránea.
#' @param columna_hija Columna con la llave foránea.
#' @param tabla_padre Tabla referenciada.
#' @param columna_padre Columna referenciada.
#' @return `TRUE` si toda referencia no nula apunta a una fila existente.
validar_integridad_referencial <- function(con, tabla_hija, columna_hija, tabla_padre, columna_padre) {
  query <- paste0("
    SELECT COUNT(*) as invalidos
    FROM ", tabla_hija, " h
    LEFT JOIN ", tabla_padre, " p ON h.", columna_hija, " = p.", columna_padre, "
    WHERE p.", columna_padre, " IS NULL AND h.", columna_hija, " IS NOT NULL
  ")
  result <- dbGetQuery(con, query)
  result$invalidos == 0
}

# --- Validación de formato ---

#' ¿El texto está capitalizado en sentido estricto?
#'
#' Exige inicial mayúscula y el resto en minúsculas, admitiendo acentos y
#' diéresis. Los `NA` se consideran válidos: la nulidad se valida aparte.
#'
#' @param s Vector de caracteres.
#' @return Un vector lógico del mismo largo.
is_capitalized_strict <- function(s) {
  sapply(s, function(x) {
    if (is.na(x)) return(TRUE)
    # Permitir letras con acentos y diéresis
    grepl("^[A-ZÁÉÍÓÚÜÑ][a-záéíóúüñ]*$", x)
  })
}

#' ¿El texto contiene algún dígito?
#'
#' @param s Vector de caracteres.
#' @return Un vector lógico del mismo largo.
contains_numeric <- function(s) {
  grepl("[0-9]", s)
}

#' ¿El texto es una fecha ISO 8601 (AAAA-MM-DD) válida?
#'
#' Comprueba el formato y además que la fecha exista, para descartar casos como
#' "2026-02-30".
#'
#' @param s Vector de caracteres.
#' @return Un vector lógico del mismo largo.
is_iso8601_date <- function(s) {
  grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", s) & !is.na(as.Date(s, format="%Y-%m-%d"))
}
