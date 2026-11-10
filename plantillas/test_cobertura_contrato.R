
# Meta-prueba: verifica que las pruebas generadas cubren todas las reglas
# derivadas del contrato. Este archivo lo escribe r/validar_contrato.R; no lo
# edites a mano.

library(testthat)
library(here)
library(readr)

source(here("r/config.R"))
source(here("r/parsear_contrato.R"))
source(here("r/verificar_cobertura.R"))

expectativas_contrato <- parsear_contrato(read_file(contract_file_path))
cobertura_contrato <- verificar_cobertura(expectativas_contrato, test_output_dir)

test_that("contrato.cobertura: toda regla del contrato tiene prueba", {
  ausentes <- cobertura_contrato$id[cobertura_contrato$estado == "AUSENTE"]
  expect_true(
    length(ausentes) == 0,
    info = paste0(
      "Reglas del contrato sin prueba asociada: ",
      paste(ausentes, collapse = ", ")
    )
  )
})

test_that("contrato.identificadores: las pruebas usan el id canónico", {
  sin_id <- cobertura_contrato$id[cobertura_contrato$estado == "SIN_ID"]
  expect_true(
    length(sin_id) == 0,
    info = paste0(
      "Reglas cubiertas por pruebas que no declaran su identificador: ",
      paste(sin_id, collapse = ", ")
    )
  )
})
