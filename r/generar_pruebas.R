# generar_pruebas.R
#
# Genera, tabla por tabla, los archivos `test_contrato_<Tabla>.R` a partir de la
# sección correspondiente del contrato.
#
# Un fallo en una tabla no detiene a las demás: se reporta y se sigue, para que
# una corrida larga no se pierda entera por un corte del servidor. La cobertura
# se verifica al final (ver r/verificar_cobertura.R) y ahí sí falla el flujo si
# quedó alguna regla sin prueba.

library(readr)

#' Genera y escribe las pruebas de una tabla del contrato
#'
#' Si el LLM devuelve algo de lo que no se puede extraer código R, guarda la
#' respuesta cruda y aborta esta tabla: escribir un archivo vacío haría que el
#' flujo pareciera exitoso cuando en realidad no se generó nada.
#'
#' @param tabla Nombre de la tabla, tal como aparece en el contrato.
#' @param seccion Texto markdown de la sección del contrato de esa tabla.
#' @param ids Identificadores canónicos que las pruebas deben cubrir.
#' @param system_prompt System prompt de la corrida, común a todas las tablas.
#' @param dir_destino Directorio de pruebas donde se escribe el archivo.
#' @return La ruta del archivo escrito, de forma invisible.
generar_pruebas_tabla <- function(
  tabla,
  seccion,
  ids,
  system_prompt,
  dir_destino
) {
  user_prompt <- construir_user_prompt(tabla, seccion, ids)
  respuesta_llm <- llamar_llm(system_prompt, user_prompt)
  codigo_pruebas <- extraer_codigo_r(respuesta_llm)

  if (!nzchar(codigo_pruebas)) {
    ruta_cruda <- file.path(
      dir_destino,
      paste0("respuesta_cruda_", tabla, ".txt")
    )
    write_file(respuesta_llm, ruta_cruda)
    stop(
      "no se pudo extraer código R de la respuesta. Respuesta cruda en: ",
      ruta_cruda
    )
  }

  ruta_pruebas <- file.path(
    dir_destino,
    paste0("test_contrato_", tabla, ".R")
  )
  cat("Escribiendo pruebas a:", ruta_pruebas, "\n")
  write_file(codigo_pruebas, ruta_pruebas)
  invisible(ruta_pruebas)
}

#' Genera las pruebas de todas las tablas del contrato
#'
#' @param secciones_tabla Lista nombrada con el texto de cada sección del
#'   contrato, tal como la devuelve `dividir_secciones_tabla()`.
#' @param expectativas Data frame de expectativas de `parsear_contrato()`.
#' @param system_prompt System prompt de la corrida, común a todas las tablas.
#' @param dir_destino Directorio de pruebas donde se escriben los archivos.
#' @return Los nombres de las tablas procesadas, de forma invisible.
generar_pruebas_contrato <- function(
  secciones_tabla,
  expectativas,
  system_prompt,
  dir_destino
) {
  tablas <- names(secciones_tabla)

  for (tabla in tablas) {
    # Identificadores canónicos que las pruebas de esta tabla deben cubrir
    ids_tabla <- ids_de_tabla(expectativas, tabla)

    cat(
      "Generando pruebas para tabla:",
      tabla,
      paste0("(", length(ids_tabla), " reglas)"),
      "\n"
    )

    tryCatch(
      generar_pruebas_tabla(
        tabla,
        secciones_tabla[[tabla]],
        ids_tabla,
        system_prompt,
        dir_destino
      ),
      error = function(e) {
        cat(
          "Error al generar las pruebas para",
          tabla,
          ":",
          conditionMessage(e),
          "\n"
        )
      }
    )
  }

  invisible(tablas)
}
