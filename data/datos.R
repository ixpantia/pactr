library(DBI)
library(RSQLite)

# --- Parámetros de conexión desde variables de ambiente (.Renviron) ---
db_nombre <- Sys.getenv("BASE_DE_DATOS")
db_contrasena <- Sys.getenv("CONTRASENA_DB")

if (db_nombre == "") {
  stop(
    "Necesitas crear un archivo .Renviron que contenga la variable ambiental
     BASE_DE_DATOS=<el nombre/ruta de la base de datos>"
  )
}
if (db_contrasena == "") {
  stop(
    "Necesitas crear un archivo .Renviron que contenga la variable ambiental
     CONTRASENA_DB=<la contraseña>"
  )
}

# 1. Crear la conexión (crea el archivo de base de datos en tu carpeta actual)
# Nota: SQLite no autentica; db_contrasena se valida pero el driver no la usa.
if (file.exists(db_nombre)) {
  file.remove(db_nombre)
}
con <- dbConnect(RSQLite::SQLite(), dbname = db_nombre)

# 2. Crear las tablas (Adaptado ligeramente a sintaxis SQLite)
# Nota: En SQLite usamos 'INTEGER PRIMARY KEY AUTOINCREMENT'

# Tabla Autores
dbExecute(
  con,
  "
  CREATE TABLE IF NOT EXISTS autores (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    nombre TEXT NOT NULL,
    nacionalidad TEXT
  )
"
)

# Tabla Libros
dbExecute(
  con,
  "
  CREATE TABLE IF NOT EXISTS libros (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    titulo TEXT NOT NULL,
    precio REAL NOT NULL,
    autor_id INTEGER,
    FOREIGN KEY (autor_id) REFERENCES autores(id)
  )
"
)

# Tabla Ventas
dbExecute(
  con,
  "
  CREATE TABLE IF NOT EXISTS ventas (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    libro_id INTEGER,
    fecha_venta TEXT,
    cantidad INTEGER,
    FOREIGN KEY (libro_id) REFERENCES libros(id)
  )
"
)

# 3. Poblar datos (Insertar)

# Autores
dbExecute(
  con,
  "INSERT INTO autores (nombre, nacionalidad) VALUES 
                ('Gabriel García Márquez', 'Colombiana'),
                ('J.K. Rowling', 'Británica'),
                ('George Orwell', 'Británica'),
                ('Isabel Allende', 'Chilena')"
)

# Libros
dbExecute(
  con,
  "INSERT INTO libros (titulo, precio, autor_id) VALUES 
                ('Cien años de soledad', 15.00, 1),
                ('El amor en los tiempos del cólera', 12.99, 1),
                ('Harry Potter y la piedra filosofal', 20.00, 2),
                ('1984', 10.50, 3),
                ('La casa de los espíritus', 14.00, 4)"
)

# Ventas (Nota: SQLite usa fechas como texto YYYY-MM-DD por defecto)
dbExecute(
  con,
  "INSERT INTO ventas (libro_id, fecha_venta, cantidad) VALUES 
                (1, '2026-07-01', 2),
                (3, '2026-07-02', 1),
                (1, '2026-07-03', 1),
                (4, '2026-07-05', 3),
                (5, '2026-07-06', 1),
                (1, '2026-07-28', 5),
                (2, '2026-07-29', 2),
                (99, '2026-07-28', 1),
                (3, '28/07/2026', 1),
                (4, '2026-07-29', 0)"
)

# 4. Consultar los datos (Trayendo el resultado a un Dataframe de R)
sql_reporte <- "
  SELECT 
    v.fecha_venta,
    l.titulo AS Libro,
    a.nombre AS Autor,
    l.precio AS Precio_Unitario,
    v.cantidad,
    (l.precio * v.cantidad) AS Total_Venta
  FROM ventas v
  JOIN libros l ON v.libro_id = l.id
  JOIN autores a ON l.autor_id = a.id
"

df_resultado <- dbGetQuery(con, sql_reporte)

# 5. Ver el resultado
print(df_resultado)

# 6. IMPORTANTE: Desconectar al terminar
dbDisconnect(con)
