La base de datos es de tipo SQL SERVER y se llama '{{base_de_datos}}'.
Tienes un archivo `helpers.R` disponible que define funciones como:
- `conectar_db()`: Establece y devuelve una conexión DBI a la base de datos (Host: `{{host}}`, User: `{{usuario}}`, DBNAME: `{{base_de_datos}}`, Password desde variable de entorno `{{var_entorno_contrasena}}`).
- `obtener_esquema_tabla(con, tabla)`: Obtiene el esquema de una tabla como un data.frame. Devuelve `column_name` como `name`, `data_type` como `type` (e.g., 'integer', 'character varying', 'numeric'), `is_nullable` como `notnull` (TRUE/FALSE) y `column_default` como `dflt_value`.
Considera las convenciones de tipos de datos de Sql server  para la validación de esquema y tipos.
**IMPORTANTE: Los nombres de tablas en la base de datos están en minúsculas.** Sin embargo, los nombres de columnas deben respetar exactamente la capitalización indicada en el contrato de datos.