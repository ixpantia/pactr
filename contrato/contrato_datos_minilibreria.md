# **Contrato de datos Ventas MiniLibrería**

## Documento técnico de manejo de datos 

| Nombre del proyecto | Validación de contratos de datos |
| ----: | :---- |
| **Repositorio** | datachat |
| **Preparado por:** | Magdiel |
| **Versión:** | v0.01 |
| **Fecha:**  | 27 de noviembre del 2025 |
| **Contacto:**  | *Consumidor de los datos:*   *Manejo de los datos:*  Nombre Apellido \<[correo@ejemplo.com](mailto:correo@ejemplo.com)\> |

Contenido  
---

[Introducción	3](#introducción)

[Contexto	3](#contexto)

[Descripción de casos límite y consideraciones especiales	3](#heading=h.jhtbxpflo4pj)

[Definición de esquemas (diccionario)	3](#definición-de-esquemas-\(diccionario\))

[Definición de estándares de calidad de datos	4](#heading=h.b0ir0up9th2l)

[Fuente de datos y accesos	5](#fuente-de-datos-y-accesos)

[Manejo de errores e incidentes	5](#heading=h.7sit2gyz4y7z)

---

# Registro de cambios

| Versión | Autor | Fecha | Descripción |
| :---- | :---- | :---- | :---- |
| 0.0.1 | Magdiel | 20251127 | Versión inicial |

# 

## Introducción {#introducción}

Los Contratos de Datos establecen acuerdos claros entre el equipo de gestión de datos y los consumidores de datos. Estos contratos definen expectativas relacionadas con la confiabilidad, calidad y capacidad de respuesta de los datos, asegurando que ambas partes estén alineadas en cuanto a estándares, procesos y métricas de calidad para la gestión de datos. A través de contratos de datos bien definidos, las organizaciones pueden mantener flujos de datos consistentes y confiables, minimizando los riesgos asociados con cambios en los datos, errores o problemas de latencia.

Los contratos de datos se usan en múltiples contextos y secciones de este documento pueden extenderse o reducirse dependiendo del contexto específico.  Ejemplos de casos de uso de contratos de datos incluyen:

* Integración de APIs  
* Desarrollo de pipelines  
* Tableros y reportes

***Nota:** Típicamente antes de arrancar con la definición de este contrato ya existe un documento  con los Objetivos de Servicio (SLOs) e Indicadores de servicio (SLIs). Si existe, haz la referencia aquí.*

## Contexto {#contexto}

Cada Contrato de Datos debe comenzar con un breve contexto que describa el propósito y alcance del proyecto. Esta sección típicamente incluye:

* Caso de Negocio: Explicación de la necesidad empresarial que impulsa el proyecto. ¿Por qué se necesitan los datos y qué objetivos respaldan?  
* Descripción de los Usuarios: Identificación de los usuarios principales o partes interesadas que consumiran los datos.

## Fuente de datos y accesos {#fuente-de-datos-y-accesos}

Lista de las fuentes de datos necesarias con credenciales de acceso. Puede que sea necesario definir también aspectos de la gobernanza de la fuente de datos

| Nombre de la fuente | Tipo (Vista, tabla, etc.) | Frecuencia actualización | Descripción | Notas sobre acceso a los datos |
| :---- | :---- | :---- | :---- | :---- |
| autores | tabla |  | catálogo maestro de escritores |  |
| libros | tabla |  | inventario de productos disponibles |  |
| ventas | tabla |  | registro transaccional de libros vendidos |  |

## Definición de esquemas (diccionario) {#definición-de-esquemas-(diccionario)}

Dado que el objetivo es tener un producto de datos accesible para toda la organización, incluidos desarrolladores, científicos y autores de documentación técnica y no técnica, es importante contar con una descripción detallada de los datos que estarán disponibles y los estándares que deben cumplir, en otras palabras un diccionario de datos.

Debe existir un diccionario de datos por cada una de las fuentes especificadas en Fuentes y accesos.

### Tabla: Autores

Diccionario

| Tabla: autores |  |  |  |  |
| :---- | :---- | :---- | ----- | :---- |
| **Variable** | **Descripción** | **Tipo** | **Tamaño** | **Notas** |
| `id` | Identificador único del autor  | integer |  | Clave primaria |
| `nombre` | Nombre completo del autor | varchar(100) |  |  |
| `nacionalidad` | País de origen del autor | varchar(50) |  |  |

Reglas de calidad

| Variable | Nulo | Detalles cálculo | Reglas de calidad |
| :---- | :---- | :---- | :---- |
| `id` | No | Autoincremental | Debe ser único |
| `nombre` | No | Nombre completo del autor | No debe contener caracteres numéricos |
| `nacionalidad` | Sí |  | Formato capitalizado (Ej. “Chilena”) |

### Tabla: Libros

Diccionario

| Tabla: libros |  |  |  |  |
| :---- | :---- | :---- | ----- | :---- |
| **Variable** | **Descripción** | **Tipo** | **Tamaño** | **Notas** |
| `id` | Identificador único del libro (SKU) | integer |  | Clave primaria |
| `titulo` | Título oficial de la obra | varchar(150) |  |  |
| `precio` | Precio unitario de venta | decimal(10,2) |  |  |
| `autor_id` | Referencia a `autores.id` | integer |  | Clave secundaria |

Reglas de calidad

| Variable | Nulo | Detalles cálculo | Reglas de calidad |
| :---- | :---- | :---- | :---- |
| `id` | No |  | Debe ser único |
| `titulo` | No |  |  |
| `precio` | No |  | Debe ser mayor a 0 |
| `autor_id` | No |  | Debe existir integridad referencial |

### Tabla: Ventas

Diccionario

| Tabla: ventas |  |  |  |  |
| :---- | :---- | :---- | ----- | :---- |
| **Variable** | **Descripción** | **Tipo** | **Tamaño** | **Notas** |
| `id` | Identificador único de la transacción | integer |  | Clave primaria |
| `libro_id` | Referencia a `libros.id` | integer |  | Clave secundaria |
| `fecha_venta` | Fecha de transacción | date/text |  |  |
| `cantidad` | Unidades vendidas en la transacción | integer |  |  |

Reglas de calidad

| Variable | Nulo | Detalles cálculo | Reglas de calidad |
| :---- | :---- | :---- | :---- |
| `id` | No |  | Debe ser único |
| `libro_id` | No |  | Debe existir integridad referencial |
| `fecha_venta` | No |  | Formato debe ser ISO 8601 (YYYY-MM-DD) |
| `cantidad` | No |  | Debe ser mayor a 0 |
