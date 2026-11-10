# parsear_contrato.R
#
# Extrae del contrato de datos, de forma determinista y sin LLM, la lista de
# expectativas que las pruebas generadas deben cubrir. Cada expectativa lleva un
# identificador canónico `tabla.columna.regla` que sirve para verificar después
# si el generador produjo una prueba para ella.

library(stringr)

# --- Limpieza de celdas --------------------------------------------------

#' Normaliza el valor de una celda del contrato
#'
#' El markdown proviene de exportar un documento de Google Docs, que introduce
#' espacios de ancho cero (U+200B), escapes de guion bajo y negritas alrededor
#' de los encabezados.
#'
#' @param x Vector de caracteres con el contenido crudo de una o más celdas.
#' @return El mismo vector, sin marcas de formato y sin espacios sobrantes.
limpiar_celda <- function(x) {
  x <- gsub("​", "", x)
  x <- gsub("\\*\\*", "", x)
  x <- gsub("`", "", x)
  x <- gsub("\\\\_", "_", x)
  trimws(x)
}

# --- Lectura de tablas markdown ------------------------------------------

#' Agrupa en bloques las líneas de tabla markdown
#'
#' Cada bloque es una secuencia de líneas consecutivas que empiezan con "|", es
#' decir una tabla markdown completa.
#'
#' @param lineas Vector de caracteres con las líneas del contrato.
#' @return Una lista de bloques; cada bloque es un vector de líneas.
extraer_bloques_tabla <- function(lineas) {
  bloques <- list()
  actual <- character()

  for (linea in lineas) {
    if (grepl("^\\s*\\|", linea)) {
      actual <- c(actual, linea)
    } else if (length(actual) > 0) {
      bloques[[length(bloques) + 1]] <- actual
      actual <- character()
    }
  }
  if (length(actual) > 0) {
    bloques[[length(bloques) + 1]] <- actual
  }

  bloques
}

#' Convierte un bloque de tabla markdown en filas de celdas
#'
#' Descarta las filas separadoras (`| :---- | ... |`), que no llevan datos.
#'
#' @param bloque Vector de líneas de una tabla markdown.
#' @return Una lista de filas; cada fila es un vector de celdas ya limpias.
filas_tabla <- function(bloque) {
  es_separador <- grepl("^\\s*\\|[-:[:space:]|]+\\|\\s*$", bloque)
  bloque <- bloque[!es_separador]

  lapply(bloque, function(linea) {
    linea <- sub("^\\s*\\|", "", linea)
    linea <- sub("\\|\\s*$", "", linea)
    limpiar_celda(strsplit(linea, "|", fixed = TRUE)[[1]])
  })
}

#' Devuelve las filas de datos de un bloque
#'
#' Son las filas posteriores a la de encabezado. La fila de encabezado se
#' localiza buscando la primera que contenga todos los nombres indicados.
#'
#' @param bloque Vector de líneas de una tabla markdown.
#' @param encabezados Nombres de columna que identifican la fila de encabezado.
#' @return Una lista de filas de datos, vacía si no se encuentra el encabezado.
filas_de_datos <- function(bloque, encabezados) {
  filas <- filas_tabla(bloque)

  indice_encabezado <- NA_integer_
  for (i in seq_along(filas)) {
    if (all(encabezados %in% filas[[i]])) {
      indice_encabezado <- i
      break
    }
  }

  if (is.na(indice_encabezado) || indice_encabezado == length(filas)) {
    return(list())
  }

  filas[seq(indice_encabezado + 1, length(filas))]
}

# --- Secciones por tabla --------------------------------------------------

#' Divide el contrato en secciones, una por tabla
#'
#' Cada sección abarca desde un encabezado `### Tabla: X` hasta el siguiente.
#'
#' @param contract_text Texto completo del contrato de datos.
#' @return Lista nombrada por tabla con el texto completo de cada sección.
dividir_secciones_tabla <- function(contract_text) {
  encabezados <- unique(str_extract_all(contract_text, "### Tabla: (.+)")[[1]])
  nombres <- str_replace(encabezados, "### Tabla: ", "")

  secciones <- list()
  for (nombre in nombres) {
    nombre_limpio <- gsub("\\\\", "", nombre)
    patron <- paste0(
      "(### Tabla: ",
      str_escape(nombre),
      "\\s*\\n[\\s\\S]*?)(?=### Tabla:|$)"
    )
    coincidencia <- regmatches(
      contract_text,
      regexpr(patron, contract_text, perl = TRUE)
    )

    if (length(coincidencia) > 0) {
      secciones[[nombre_limpio]] <- coincidencia[[1]]
    } else {
      warning("No se pudo extraer la sección para la tabla: ", nombre)
    }
  }

  secciones
}

# --- Vocabulario de reglas de calidad -------------------------------------

# Reglas que el parser sabe traducir a un identificador canónico. Un contrato con
# una regla fuera de este vocabulario no es un error: se marca como `otra_regla`
# y se reporta, porque puede tratarse de una regla en prosa que solo el LLM puede
# interpretar.
reglas_conocidas <- c(
  unico = "debe ser [úu]nico",
  mayor_a_cero = "mayor a 0|mayor que 0|>\\s*0",
  integridad_referencial = "integridad referencial",
  iso8601 = "iso\\s?8601",
  sin_numeros = "no debe contener caracteres num[ée]ricos",
  capitalizado = "formato capitalizado|capitalizad"
)

#' Traduce el texto de una regla del contrato a su identificador canónico
#'
#' @param texto Texto de la celda "Reglas de calidad" del contrato.
#' @return El identificador de la regla; `"otra_regla"` si no está en el
#'   vocabulario conocido, o `NA` si la celda está vacía.
identificar_regla <- function(texto) {
  texto_normalizado <- tolower(limpiar_celda(texto))

  if (!nzchar(texto_normalizado)) {
    return(NA_character_)
  }

  for (id in names(reglas_conocidas)) {
    if (grepl(reglas_conocidas[[id]], texto_normalizado)) {
      return(id)
    }
  }

  "otra_regla"
}

# --- Parseo del contrato --------------------------------------------------

#' Extrae el destino de una llave foránea de la descripción de una columna
#'
#' Reconoce el formato "Referencia a tabla.columna".
#'
#' @param descripcion Texto de la celda "Descripción" del contrato.
#' @return Un vector con los elementos `tabla` y `columna`, ambos `NA` si la
#'   descripción no declara ninguna referencia.
extraer_referencia <- function(descripcion) {
  coincidencia <- str_match(
    descripcion,
    "[Rr]eferencia a\\s+([A-Za-z0-9_]+)\\.([A-Za-z0-9_]+)"
  )

  if (is.na(coincidencia[1, 2])) {
    return(c(tabla = NA_character_, columna = NA_character_))
  }

  c(tabla = coincidencia[1, 2], columna = coincidencia[1, 3])
}

#' Parsea una sección de tabla y devuelve sus expectativas
#'
#' Combina las dos tablas markdown de la sección: el diccionario de datos
#' (variable, descripción, tipo) y las reglas de calidad (variable, nulo,
#' reglas). De ahí salen la expectativa de esquema, las de no-nulidad y las de
#' cada regla de calidad reconocida.
#'
#' @param seccion Texto markdown de la sección de una tabla.
#' @param nombre_tabla Nombre de la tabla, tal como aparece en el encabezado.
#' @return Un data frame de expectativas, o `NULL` si la sección no aporta
#'   ninguna.
parsear_seccion <- function(seccion, nombre_tabla) {
  tabla <- tolower(nombre_tabla)
  lineas <- strsplit(seccion, "\n", fixed = TRUE)[[1]]
  bloques <- extraer_bloques_tabla(lineas)

  diccionario <- list()
  reglas <- list()

  for (bloque in bloques) {
    filas <- filas_tabla(bloque)
    celdas <- unlist(filas)

    if ("Tipo" %in% celdas && "Variable" %in% celdas) {
      diccionario <- filas_de_datos(
        bloque,
        c("Variable", "Descripción", "Tipo")
      )
    } else if ("Nulo" %in% celdas && "Reglas de calidad" %in% celdas) {
      reglas <- filas_de_datos(
        bloque,
        c("Variable", "Nulo", "Reglas de calidad")
      )
    }
  }

  expectativas <- list()

  agregar <- function(
    columna,
    regla,
    texto = NA_character_,
    tipo = NA_character_,
    referencia = NA_character_
  ) {
    id <- if (is.na(columna)) {
      paste0(tabla, ".", regla)
    } else {
      paste0(tabla, ".", columna, ".", regla)
    }
    expectativas[[length(expectativas) + 1]] <<- data.frame(
      id = id,
      tabla = tabla,
      columna = columna,
      regla = regla,
      texto_contrato = texto,
      tipo = tipo,
      referencia = referencia,
      stringsAsFactors = FALSE
    )
  }

  # Una expectativa de esquema por tabla, derivada del diccionario
  if (length(diccionario) > 0) {
    agregar(NA_character_, "esquema")
  }

  # Tipo y llave foránea de cada columna del diccionario
  tipos <- list()
  for (fila in diccionario) {
    if (length(fila) < 3 || !nzchar(fila[1])) {
      next
    }
    columna <- fila[1]
    tipos[[columna]] <- fila[3]

    referencia <- extraer_referencia(fila[2])
    if (!is.na(referencia[["tabla"]])) {
      tipos[[paste0(columna, ".ref")]] <- paste0(
        referencia[["tabla"]],
        ".",
        referencia[["columna"]]
      )
    }
  }

  # Nulidad y reglas de calidad
  for (fila in reglas) {
    if (length(fila) < 2 || !nzchar(fila[1])) {
      next
    }
    columna <- fila[1]
    nulo <- tolower(fila[2])
    tipo_columna <- if (!is.null(tipos[[columna]])) {
      tipos[[columna]]
    } else {
      NA_character_
    }
    referencia <- if (!is.null(tipos[[paste0(columna, ".ref")]])) {
      tipos[[paste0(columna, ".ref")]]
    } else {
      NA_character_
    }

    if (nulo %in% c("no")) {
      agregar(columna, "no_nulo", "Nulo: No", tipo_columna, referencia)
    }

    texto_regla <- if (length(fila) >= 4) fila[4] else ""
    id_regla <- identificar_regla(texto_regla)
    if (!is.na(id_regla)) {
      agregar(columna, id_regla, texto_regla, tipo_columna, referencia)
    }
  }

  if (length(expectativas) == 0) {
    return(NULL)
  }

  do.call(rbind, expectativas)
}

#' Deriva del contrato todas las expectativas que las pruebas deben cubrir
#'
#' Es el punto de entrada del módulo.
#'
#' @param contract_text Texto completo del contrato de datos.
#' @return Un data frame con una expectativa por fila y las columnas `id`,
#'   `tabla`, `columna`, `regla`, `texto_contrato`, `tipo` y `referencia`.
parsear_contrato <- function(contract_text) {
  secciones <- dividir_secciones_tabla(contract_text)

  if (length(secciones) == 0) {
    stop("No se pudieron extraer secciones de tablas del contrato")
  }

  partes <- list()
  for (nombre in names(secciones)) {
    parte <- parsear_seccion(secciones[[nombre]], nombre)
    if (!is.null(parte)) {
      partes[[length(partes) + 1]] <- parte
    }
  }

  if (length(partes) == 0) {
    stop("No se pudo derivar ninguna expectativa del contrato")
  }

  do.call(rbind, partes)
}

#' Identificadores canónicos de una tabla, en el orden del contrato
#'
#' Se usa para decirle al LLM exactamente qué pruebas debe producir.
#'
#' @param expectativas Data frame de expectativas de `parsear_contrato()`.
#' @param nombre_tabla Nombre de la tabla; la comparación ignora mayúsculas.
#' @return Un vector de caracteres con los identificadores de esa tabla.
ids_de_tabla <- function(expectativas, nombre_tabla) {
  expectativas$id[expectativas$tabla == tolower(nombre_tabla)]
}
