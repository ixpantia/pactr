
`helpers.R` también define `comparar_tipo_sql(expected_type, actual_type)`, que devuelve TRUE cuando el tipo declarado en el contrato y el tipo real de la base de datos son equivalentes. Conoce las familias de tipos de SQLite, PostgreSQL y SQL Server (enteros, numéricos, texto, fecha, fecha/hora, lógicos y binarios), por lo que resuelve casos como 'varchar' del contrato contra 'TEXT' en SQLite o 'character varying' en PostgreSQL. Úsala siempre para comparar tipos; no reimplementes esa lógica.

Al generar las pruebas, asume que `con` es el objeto de conexión DBI válido. Recuerda: solo el código R de las pruebas, sin `library()`, `source()`, `setup()` o `teardown()`.

--- Robustez de las pruebas ---
Todas las pruebas que ejecuten consultas SQL deben ser resilientes ante incompatibilidades de tipos de datos en la base de datos. Para lograrlo, envuelve siempre la llamada a `DBI::dbGetQuery()` en un `tryCatch()`. Si la consulta falla (por ejemplo, porque una columna es de tipo `date` puro y se intenta extraer la hora, o cualquier conversión de tipos no soportada), el test debe llamar a `testthat::skip()` con un mensaje descriptivo que explique el motivo, en lugar de lanzar un error que detenga la ejecución. Ejemplo de patrón a seguir:
```r
datos <- tryCatch(
  DBI::dbGetQuery(con, query),
  error = function(e) {
    testthat::skip(paste0("La consulta no pudo ejecutarse (posible incompatibilidad de tipos): ", conditionMessage(e)))
  }
)
```

--- Validación de esquema (PATRÓN OBLIGATORIO) ---
Para la prueba que valida el esquema de cada tabla, DEBES usar EXACTAMENTE el siguiente patrón. Este patrón produce mensajes descriptivos que identifican con precisión cualquier discrepancia entre el contrato y la base de datos:
```r
# Columnas del contrato ausentes en la base de datos
faltantes_en_db <- setdiff(schema_esperado$name, schema_actual$name)
expect_true(length(faltantes_en_db) == 0,
            info = paste0(
              "Las siguientes columnas están en el contrato pero NO en la base de datos: ",
              paste(faltantes_en_db, collapse = ", "), ". ",
              "Verifique que los nombres en el contrato coincidan exactamente con los de la tabla."
            ))

# Columnas en la base de datos no descritas en el contrato (solo warning, no error)
extra_en_db <- setdiff(schema_actual$name, schema_esperado$name)
if (length(extra_en_db) > 0) {
  warning(paste0(
    "Las siguientes columnas existen en la base de datos pero NO están descritas en el contrato: ",
    paste(extra_en_db, collapse = ", "), "."
  ))
}

# Verificar tipos solo para columnas que coinciden en ambos lados
columnas_comunes <- intersect(schema_esperado$name, schema_actual$name)
for (col_name in columnas_comunes) {
  expected_type <- schema_esperado$type[schema_esperado$name == col_name]
  actual_type   <- schema_actual$type[schema_actual$name == col_name]
  # comparar_tipo_sql() está definida en helpers.R y resuelve las equivalencias
  # de tipos entre SQLite, PostgreSQL y SQL Server.
  type_check <- comparar_tipo_sql(expected_type, actual_type)
  expect_true(type_check,
              info = paste0("La columna '", col_name, "' no es del tipo esperado '",
                            expected_type, "'. Tipo encontrado: '", actual_type, "'."))
}
```
Este patrón es obligatorio porque: (a) detecta columnas del contrato con nombres incorrectos y las lista explícitamente, (b) emite un warning (no un error) cuando hay columnas extra en la base de datos no documentadas en el contrato, (c) evita errores de `character(0)` al buscar el tipo de una columna que no existe en la base de datos, y (d) delega la equivalencia de tipos en `comparar_tipo_sql()`, que ya conoce las familias de tipos de cada motor. NUNCA compares tipos con `grepl()` ni con `==` directamente: usa siempre `comparar_tipo_sql()`.

El campo `type` de `schema_esperado` debe copiar TEXTUALMENTE el tipo declarado en el contrato, sin normalizarlo, traducirlo al motor de base de datos ni elegir una de las opciones cuando el contrato ofrece varias. Si el contrato declara `date/text`, escribe exactamente "date/text"; `comparar_tipo_sql()` ya interpreta esas alternativas y acepta cualquiera de ellas.