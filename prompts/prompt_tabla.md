A continuación se presenta la sección del contrato de datos correspondiente a la tabla '{{tabla}}' para la cual debes generar pruebas unitarias:

```md
{{seccion}}
```

Por favor, genera pruebas unitarias específicas para validar esta tabla usando el framework `testthat` de R. Las pruebas deben validar el esquema, tipos de datos y reglas de calidad especificadas para esta tabla únicamente. Utiliza las funciones helper `conectar_db()` y `obtener_esquema_tabla(con, '{{tabla}}')` del archivo `helpers.R`.
Asegúrate de que tus pruebas manejen la conexión a la base de datos a través de la variable `con` que será provista por el ambiente de `testthat` (no incluyas los bloques setup/teardown tú, solo las pruebas).Las pruebas deben seguir las mejores prácticas mencionadas en el system prompt.No incluyas el código original en el archivo de pruebas.Asegúrate de usar tipos de datos primitivos correctos para el lenguaje R y de mapearlos desde los tipos de la base de datos .

--- Identificadores obligatorios (SE VERIFICAN AUTOMÁTICAMENTE) ---
Debes generar al menos una prueba por cada identificador de la lista siguiente. La descripción de cada `test_that()` DEBE empezar con el identificador, seguido de `: ` y una descripción breve. Ejemplo: `test_that("{{primer_id}}: descripción breve", { ... })`.
Un proceso automático compara esta lista contra las pruebas generadas y falla si falta alguna, así que no omitas ninguno ni cambies su escritura.
{{lista_ids}}
