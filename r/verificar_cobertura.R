# verificar_cobertura.R
#
# Compara las expectativas derivadas del contrato (ver parsear_contrato.R) con
# las pruebas realmente generadas, y reporta qué reglas quedaron sin cubrir.
#
# La detección es en dos niveles:
#   1. Identificador canónico en la descripción del `test_that()`. Es exacta y es
#      lo que el prompt le exige al LLM.
#   2. Señales en el cuerpo de la prueba (nombre de la columna junto al helper
#      o patrón esperado). Sirve para distinguir "no existe la prueba" de
#      "existe pero el LLM no respetó el identificador", que exigen acciones
#      distintas.

library(stringr)

# Señales que delatan que una prueba valida cierta regla, aunque no lleve el
# identificador canónico. Se buscan en el cuerpo del `test_that()`.
senales_regla <- list(
  esquema = c("comparar_tipo_sql", "obtener_esquema_tabla", "schema_esperado"),
  no_nulo = c("IS NULL", "is.na", "notnull", "nulo"),
  unico = c("validar_unicidad", "DISTINCT", "duplicad"),
  mayor_a_cero = c("> 0", "<= 0", "mayor"),
  integridad_referencial = c(
    "validar_integridad_referencial",
    "LEFT JOIN",
    "integridad"
  ),
  iso8601 = c("is_iso8601_date", "8601"),
  sin_numeros = c("contains_numeric"),
  capitalizado = c("is_capitalized_strict", "capitaliz")
)

#' Extrae de un archivo de pruebas cada bloque `test_that()`
#'
#' El generador nombra los archivos `test_contrato_<Tabla>.R`, así que la tabla
#' se deduce del nombre. Es necesario para no dar por cubierta una regla de una
#' tabla con una prueba de otra.
#'
#' @param ruta Ruta a un archivo de pruebas generado.
#' @return Una lista de bloques, cada uno con `descripcion`, `cuerpo`, `archivo`
#'   y `tabla`.
extraer_bloques_test <- function(ruta) {
  texto <- readr::read_file(ruta)
  partes <- strsplit(texto, "test_that\\s*\\(", perl = TRUE)[[1]]

  if (length(partes) <= 1) {
    return(list())
  }

  # El generador nombra los archivos test_contrato_<Tabla>.R, así que la tabla
  # se deduce del nombre. Es necesario para no dar por cubierta una regla de una
  # tabla con una prueba de otra.
  archivo <- basename(ruta)
  tabla <- tolower(str_replace(
    str_replace(archivo, "^test_contrato_", ""),
    "\\.R$",
    ""
  ))

  lapply(partes[-1], function(parte) {
    descripcion <- str_match(parte, "^\\s*[\"']([^\"']*)[\"']")[1, 2]
    list(
      descripcion = if (is.na(descripcion)) "" else descripcion,
      cuerpo = parte,
      archivo = archivo,
      tabla = tabla
    )
  })
}

#' ¿El cuerpo de la prueba muestra señales de validar esta expectativa?
#'
#' Es la detección de segundo nivel, la que se usa cuando la prueba no declara
#' el identificador canónico. Exige que la prueba pertenezca al archivo de la
#' tabla y, en reglas de columna, que la columna aparezca como palabra completa:
#' así `id` no se da por cubierta al encontrar `autor_id`.
#'
#' @param bloque Bloque de prueba de `extraer_bloques_test()`.
#' @param tabla Tabla de la expectativa que se está buscando.
#' @param columna Columna de la expectativa, o `NA` si la regla es de tabla.
#' @param regla Identificador de la regla, clave de `senales_regla`.
#' @return `TRUE` si el cuerpo contiene alguna señal de esa regla.
tiene_senales <- function(bloque, tabla, columna, regla) {
  senales <- senales_regla[[regla]]
  if (is.null(senales)) {
    return(FALSE)
  }

  # La prueba debe pertenecer al archivo de la tabla en cuestión
  if (!identical(bloque$tabla, tabla)) {
    return(FALSE)
  }

  # Para reglas de columna, la columna debe aparecer en el cuerpo como palabra
  # completa: así `id` no se da por cubierta al encontrar `autor_id`.
  if (!is.na(columna)) {
    patron_columna <- paste0("\\b", columna, "\\b")
    if (!grepl(patron_columna, bloque$cuerpo)) {
      return(FALSE)
    }
  }

  any(vapply(
    senales,
    function(s) grepl(s, bloque$cuerpo, fixed = TRUE),
    logical(1)
  ))
}

#' Compara las expectativas del contrato contra las pruebas generadas
#'
#' @param expectativas Data frame de expectativas de `parsear_contrato()`.
#' @param dir_tests Directorio donde están los archivos `test_contrato_*.R`.
#' @return El mismo data frame con dos columnas más: `estado` (`"CUBIERTA"`,
#'   `"SIN_ID"` o `"AUSENTE"`) y `evidencia`, que indica dónde se encontró.
verificar_cobertura <- function(expectativas, dir_tests) {
  archivos <- list.files(
    dir_tests,
    pattern = "^test_contrato_.*\\.R$",
    full.names = TRUE
  )

  bloques <- unlist(
    lapply(archivos, extraer_bloques_test),
    recursive = FALSE
  )

  estados <- character(nrow(expectativas))
  evidencias <- character(nrow(expectativas))

  for (i in seq_len(nrow(expectativas))) {
    id <- expectativas$id[i]
    tabla <- expectativas$tabla[i]
    columna <- expectativas$columna[i]
    regla <- expectativas$regla[i]

    con_id <- Filter(
      function(b) grepl(id, b$descripcion, fixed = TRUE),
      bloques
    )

    if (length(con_id) > 0) {
      estados[i] <- "CUBIERTA"
      evidencias[i] <- con_id[[1]]$archivo
      next
    }

    con_senales <- Filter(
      function(b) tiene_senales(b, tabla, columna, regla),
      bloques
    )

    if (length(con_senales) > 0) {
      estados[i] <- "SIN_ID"
      evidencias[i] <- paste0(
        con_senales[[1]]$archivo,
        ": \"",
        con_senales[[1]]$descripcion,
        "\""
      )
    } else {
      estados[i] <- "AUSENTE"
      evidencias[i] <- ""
    }
  }

  resultado <- expectativas
  resultado$estado <- estados
  resultado$evidencia <- evidencias
  resultado
}

#' Imprime el reporte de cobertura del contrato
#'
#' Las reglas fuera del vocabulario conocido y las pruebas sin identificador
#' canónico solo advierten, porque exigen revisión manual pero no invalidan la
#' corrida.
#'
#' @param cobertura Data frame devuelto por `verificar_cobertura()`.
#' @param estricto Si es `TRUE`, una regla del contrato sin prueba detiene el
#'   flujo con un error en lugar de advertir.
#' @return El data frame de cobertura, de forma invisible.
reportar_cobertura <- function(cobertura, estricto = TRUE) {
  total <- nrow(cobertura)
  cubiertas <- sum(cobertura$estado == "CUBIERTA")
  sin_id <- sum(cobertura$estado == "SIN_ID")
  ausentes <- sum(cobertura$estado == "AUSENTE")

  cat("\n--- Cobertura del contrato ---\n")
  cat(sprintf(
    "%d expectativas: %d cubiertas, %d sin identificador, %d ausentes\n\n",
    total,
    cubiertas,
    sin_id,
    ausentes
  ))

  for (i in seq_len(total)) {
    marca <- switch(
      cobertura$estado[i],
      CUBIERTA = "  OK    ",
      SIN_ID = "  AVISO ",
      AUSENTE = "  FALTA "
    )
    cat(marca, cobertura$id[i], "\n", sep = "")
  }
  cat("\n")

  no_reconocidas <- cobertura[cobertura$regla == "otra_regla", ]
  if (nrow(no_reconocidas) > 0) {
    warning(
      "El contrato contiene reglas fuera del vocabulario conocido; ",
      "revisa manualmente que estén cubiertas:\n",
      paste0(
        "  - ",
        no_reconocidas$id,
        ": \"",
        no_reconocidas$texto_contrato,
        "\"",
        collapse = "\n"
      ),
      call. = FALSE
    )
  }

  if (sin_id > 0) {
    filas <- cobertura[cobertura$estado == "SIN_ID", ]
    warning(
      "Hay reglas cubiertas por pruebas sin identificador canónico:\n",
      paste0("  - ", filas$id, " -> ", filas$evidencia, collapse = "\n"),
      call. = FALSE
    )
  }

  if (ausentes > 0) {
    filas <- cobertura[cobertura$estado == "AUSENTE", ]
    mensaje <- paste0(
      "Las siguientes reglas del contrato no tienen prueba asociada:\n",
      paste0("  - ", filas$id, collapse = "\n")
    )
    if (estricto) {
      stop(mensaje, call. = FALSE)
    }
    warning(mensaje, call. = FALSE)
  }

  invisible(cobertura)
}
