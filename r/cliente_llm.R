# cliente_llm.R
#
# Comunicación con el servidor del LLM (API compatible con OpenAI) y extracción
# del código R de la respuesta.
#
# Cada invocación es independiente: no se acumula historial entre tablas, de modo
# que la generación de una tabla no contamina la de las siguientes. La URL base,
# la API key y el modelo vienen de config.R.

library(httr2)
library(stringr)

#' Verifica que la configuración del servidor del LLM esté completa
#'
#' Falla temprano si falta alguna variable de entorno, antes de gastar tiempo
#' leyendo el contrato o construyendo los prompts.
#'
#' @return `TRUE` de forma invisible si la configuración está completa.
validar_config_llm <- function() {
  if (!nzchar(llm_base_url)) {
    stop("Error: La variable de entorno LLM_BASE_URL no está configurada")
  }

  if (!nzchar(llm_api_key)) {
    stop("Error: La variable de entorno LLM_API_KEY no está configurada")
  }

  if (!nzchar(llm_model)) {
    stop("Error: La variable de entorno LLM_MODEL no está configurada")
  }

  invisible(TRUE)
}

#' Llama una vez al LLM y devuelve el texto de la respuesta
#'
#' Por defecto se usa la API en modo streaming (SSE): generar las pruebas de una
#' tabla puede tardar más que el límite de algunos proxies, que cortan la espera
#' con un error por tiempo de espera (p. ej. HTTP 524) cuando la respuesta llega
#' completa al final. Con streaming los fragmentos llegan de inmediato y la
#' conexión nunca queda inactiva. Si el proveedor no soporta streaming, se
#' desactiva con `LLM_STREAM=false` y se espera la respuesta completa.
#'
#' @param system_prompt Prompt de sistema, con las instrucciones generales.
#' @param user_prompt Prompt de usuario, con la sección del contrato de la tabla.
#' @return La respuesta del modelo como una única cadena.
llamar_llm_una_vez <- function(system_prompt, user_prompt) {
  req <- httr2::request(llm_base_url) |>
    httr2::req_url_path_append("chat/completions") |>
    httr2::req_headers(
      Authorization = paste("Bearer", llm_api_key)
    ) |>
    httr2::req_body_json(list(
      model = llm_model,
      messages = list(
        list(role = "system", content = system_prompt),
        list(role = "user", content = user_prompt)
      ),
      temperature = 0, # Temperatura cero para máxima consistencia
      stream = llm_stream
    )) |>
    httr2::req_timeout(600)

  contenido <- if (llm_stream) {
    leer_respuesta_stream(req)
  } else {
    leer_respuesta_completa(req)
  }

  if (!nzchar(contenido)) {
    stop("El LLM devolvió una respuesta vacía")
  }

  contenido
}

#' Ejecuta la petición sin streaming y devuelve el texto de la respuesta
#'
#' El cuerpo se lee como texto y se parsea a mano porque algunos servidores
#' responden JSON con un Content-Type distinto de `application/json`.
#'
#' @param req Petición httr2 ya construida, con `stream = FALSE`.
#' @return El contenido del mensaje del modelo como una única cadena.
leer_respuesta_completa <- function(req) {
  resp <- httr2::req_perform(req)
  cuerpo <- jsonlite::fromJSON(
    httr2::resp_body_string(resp),
    simplifyVector = FALSE
  )
  if (length(cuerpo$choices) == 0) {
    return("")
  }
  contenido <- cuerpo$choices[[1]]$message$content
  if (is.null(contenido)) "" else contenido
}

#' Ejecuta la petición en modo streaming (SSE) y devuelve el texto acumulado
#'
#' @param req Petición httr2 ya construida, con `stream = TRUE`.
#' @return La respuesta del modelo como una única cadena.
leer_respuesta_stream <- function(req) {
  resp <- httr2::req_perform_connection(req)
  on.exit(close(resp), add = TRUE)

  if (httr2::resp_status(resp) != 200) {
    stop("El servidor del LLM respondió HTTP ", httr2::resp_status(resp))
  }

  # Acumular el contenido de los fragmentos (deltas) del stream
  partes <- character()
  repeat {
    evento <- httr2::resp_stream_sse(resp)
    if (is.null(evento) || identical(trimws(evento$data), "[DONE]")) {
      break
    }
    # No todos los eventos traen texto: algunos modelos emiten fragmentos con
    # solo metadatos (uso de tokens, filtros) y `choices` vacío, así que se
    # ignora todo lo que no contenga contenido.
    fragmento <- tryCatch(
      jsonlite::fromJSON(evento$data, simplifyVector = FALSE),
      error = function(e) NULL
    )
    if (is.null(fragmento) || length(fragmento$choices) == 0) {
      next
    }
    delta <- fragmento$choices[[1]]$delta$content
    if (!is.null(delta)) {
      partes <- c(partes, delta)
    }
  }

  paste0(partes, collapse = "")
}

#' Llama al LLM reintentando ante fallos transitorios
#'
#' El streaming resuelve los timeouts del proxy, pero la conexión sigue expuesta
#' a cortes ("Connection reset by peer") y a errores 5xx del servidor. Sin
#' reintentos, un corte deja la tabla sin pruebas y el flujo continúa como si
#' nada. La espera entre intentos crece de 5 s hasta un tope de 60 s.
#'
#' @param system_prompt Prompt de sistema, con las instrucciones generales.
#' @param user_prompt Prompt de usuario, con la sección del contrato de la tabla.
#' @param intentos Número máximo de intentos antes de fallar.
#' @return La respuesta del modelo como una única cadena.
llamar_llm <- function(system_prompt, user_prompt, intentos = 4) {
  for (intento in seq_len(intentos)) {
    resultado <- tryCatch(
      llamar_llm_una_vez(system_prompt, user_prompt),
      error = function(e) e
    )

    if (!inherits(resultado, "error")) {
      return(resultado)
    }

    if (intento == intentos) {
      stop(
        "El LLM falló tras ",
        intentos,
        " intentos: ",
        conditionMessage(resultado),
        call. = FALSE
      )
    }

    espera <- min(60, 5 * 2^(intento - 1))
    cat(
      "  Intento",
      intento,
      "fallido (",
      conditionMessage(resultado),
      "). Reintentando en",
      espera,
      "s...\n"
    )
    Sys.sleep(espera)
  }
}

#' Extrae de la respuesta del LLM únicamente el código R de las pruebas
#'
#' Se intentan varios patrones, del más específico al más laxo, porque el LLM no
#' siempre etiqueta el bloque de la misma forma (```r, ```R, ```{r} o ```). Si no
#' hay ningún bloque delimitado se acepta la respuesta completa, pero solo
#' cuando contiene pruebas, para no escribir prosa en un archivo .R.
#'
#' @param texto_respuesta Respuesta cruda del modelo.
#' @return El código R encontrado, o una cadena vacía con un aviso si no lo hay.
extraer_codigo_r <- function(texto_respuesta) {
  patrones_codigo <- c(
    "```\\s*\\{?[rR]\\}?[^\\n]*\\n([\\s\\S]*?)\\n```", # ```r, ```R, ```{r}
    "```[^\\n]*\\n([\\s\\S]*?)\\n```" # bloque sin etiqueta de lenguaje
  )

  for (patron in patrones_codigo) {
    coincidencia <- str_match(texto_respuesta, patron)
    if (!is.na(coincidencia[1, 2])) {
      # coincidencia[1, 2] es el contenido del primer grupo de captura
      return(trimws(coincidencia[1, 2]))
    }
  }

  if (str_detect(texto_respuesta, "test_that\\s*\\(")) {
    return(trimws(texto_respuesta))
  }

  warning(
    "No se encontró ningún bloque de código R válido en la respuesta del LLM. Devolviendo cadena vacía."
  )
  # La cadena vacía es la señal que `generar_pruebas_tabla()` comprueba con
  # `nzchar()` para guardar la respuesta cruda y abortar esa tabla. Sin ella se
  # devolvería el mensaje del `warning()`, y se escribiría como si fuera código.
  ""
}
