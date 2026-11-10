# validar_contrato.R
#
# Punto de entrada del generador. Lee el contrato de datos, deriva de él las
# reglas que las pruebas deben cubrir, le pide al LLM las pruebas de cada tabla,
# escribe los archivos de apoyo y verifica al final que no haya quedado ninguna
# regla sin prueba.
#
# Este archivo solo orquesta; la lógica vive en los módulos que carga:
#   - r/config.R              rutas y parámetros del .Renviron
#   - r/parsear_contrato.R    expectativas derivadas del contrato, sin LLM
#   - r/verificar_cobertura.R comparación entre expectativas y pruebas generadas
#   - r/cliente_llm.R         llamadas al servidor del LLM
#   - r/prompts.R             construcción de los prompts
#   - r/plantillas.R          archivos generados que no dependen del LLM
#   - r/generar_pruebas.R     flujo de generación tabla por tabla
#
# Uso: source("r/validar_contrato.R")

library(readr)
library(here)

source(here("r/config.R"))
cat("✓ Configuración cargada desde config.R\n")

source(here("r/parsear_contrato.R"))
source(here("r/verificar_cobertura.R"))
source(here("r/cliente_llm.R"))
source(here("r/prompts.R"))
source(here("r/plantillas.R"))
source(here("r/generar_pruebas.R"))

#' Ejecuta el flujo completo de generación de pruebas
#'
#' @return El data frame de cobertura, de forma invisible.
validar_contrato <- function() {
  # Las rutas y el modelo vienen de config.R:
  # system_prompt_path, contract_file_path, test_output_dir, llm_model
  if (!file.exists(system_prompt_path)) {
    stop(
      "Error: No se encontró el archivo de system prompt en: ",
      system_prompt_path
    )
  }

  if (!file.exists(contract_file_path)) {
    stop("Error: No se encontró el archivo fuente en: ", contract_file_path)
  }

  validar_config_llm()

  if (!dir.exists(test_output_dir)) {
    dir.create(test_output_dir, recursive = TRUE)
    cat("✓ Directorio de test creado:", test_output_dir, "\n")
  }

  cat("📖 Leyendo system prompt para las pruebas...\n")
  prompt_base <- read_file(system_prompt_path)

  cat("📖 Leyendo contrato a validar...\n")
  contrato <- read_file(contract_file_path)

  secciones_tabla <- dividir_secciones_tabla(contrato)
  if (length(secciones_tabla) == 0) {
    stop("No se pudieron extraer secciones de tablas del contrato")
  }

  # Derivar del contrato, sin LLM, las reglas que las pruebas deben cubrir
  expectativas <- parsear_contrato(contrato)
  cat(
    "✓ Expectativas derivadas del contrato:",
    nrow(expectativas),
    "en",
    length(unique(expectativas$tabla)),
    "tablas\n"
  )

  cat("Generando pruebas unitarias con", llm_model, "...\n")
  system_prompt <- construir_system_prompt(prompt_base, db_type)
  generar_pruebas_contrato(
    secciones_tabla,
    expectativas,
    system_prompt,
    test_output_dir
  )

  escribir_helpers(db_type, test_output_dir)
  escribir_run_tests()
  escribir_meta_prueba_cobertura(test_output_dir)
  cat("Estructura de directorios y archivos creada exitosamente.\n")

  # La cobertura se verifica al final, con todos los archivos ya escritos, para
  # que queden disponibles aunque resulte incompleta. Una regla del contrato sin
  # prueba detiene el flujo; las reglas fuera del vocabulario conocido y las
  # pruebas sin identificador canónico solo advierten.
  cobertura <- verificar_cobertura(expectativas, test_output_dir)
  reportar_cobertura(cobertura, estricto = TRUE)
  cat("✓ Todas las reglas del contrato tienen prueba asociada.\n")

  invisible(cobertura)
}

validar_contrato()
