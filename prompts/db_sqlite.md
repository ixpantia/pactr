La base de datos es de tipo SQLite y se llama '{{ruta_db}}'.
Tienes un archivo `helpers.R` disponible que define funciones como:
- `conectar_db()`: Establece y devuelve una conexión DBI a la base de datos (path: `{{ruta_db}}`).
- `obtener_esquema_tabla(con, tabla)`: Obtiene el esquema de una tabla como un data.frame. Devuelve `name` y `type` (afinidad de tipo SQLite, e.g., 'INTEGER', 'TEXT', 'REAL').
Ten en cuenta que SQLite maneja los tipos `varchar(X)` como afinidad `TEXT` y `decimal(X,Y)` como `REAL`. Para la validación de unicidad y no-nulos, puedes usar consultas SQL directas como `SELECT COUNT(*) FROM tabla WHERE columna IS NULL` o `SELECT COUNT(columna) - COUNT(DISTINCT columna) FROM tabla`.
**IMPORTANTE: Los nombres de tablas en la base de datos (SQLite) están en minúsculas** (ej. `dbReadTable(con, 'autores')` en lugar de `'Autores'`). Sin embargo, los nombres de columnas deben respetar exactamente la capitalización indicada en el contrato de datos.