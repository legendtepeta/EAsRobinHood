# Portafolio de Estrategias Algorítmicas para NASDAQ (US100)

## Introducción
Este documento explica, paso a paso, la lógica y los detalles de cinco Expert Advisors (EAs) diseñados para operar el índice NASDAQ (US100, NQ) en MetaTrader 5.

**¿Cuál es la idea?** No depender de una sola estrategia. Los mercados cambian: a veces hay tendencia fuerte, a veces el precio se queda lateral, y otras veces hay gaps locos en la apertura. Por eso vamos a tener un EA para cada situación.

---

## Estrategia 1: "Momentum ORB" (Rompimiento del Rango de Apertura)
*Aprovechamos el caos de la apertura de Nueva York.*

### ¿Por qué funciona?
Cuando abre Wall Street a las 9:30 AM (hora de Nueva York), entra una cantidad brutal de órdenes. El precio se mueve mucho en los primeros 30 minutos mientras el mercado "decide" hacia dónde ir. Una vez que rompe ese rango inicial, suele continuar en esa dirección con fuerza.

### Los Parámetros
*   **Temporalidad**: M5 o M15.
*   **Horario de Operación**: Solo entre las 9:30 AM y 10:30 AM (hora de NY). Fuera de ese horario, el EA no hace nada.
*   **Duración del Rango**: Los primeros 30 minutos (de 9:30 a 10:00).

### ¿Cómo Entramos?
*   **Para Comprar (Long)**:
    1.  Calculamos el **máximo** del rango de apertura (el precio más alto entre 9:30 y 10:00).
    2.  Ponemos una orden pendiente Buy Stop unos puntitos por encima de ese máximo.
    3.  Si no se activa antes de las 11:00 AM, la cancelamos.
*   **Para Vender (Short)**:
    1.  Calculamos el **mínimo** del rango.
    2.  Ponemos una orden Sell Stop unos puntitos por debajo.

### ¿Cómo Salimos?
*   **Stop Loss**: 
    *   Opción A: Fijo (por ejemplo, 50 puntos).
    *   Opción B: En el lado opuesto del rango (más agresivo, pero mejor ratio riesgo/beneficio).
*   **Take Profit**: 
    *   Opción A: El doble del Stop Loss (ratio 2:1).
    *   Opción B: Cerramos todo al final del día (15:55 PM).
*   **Trailing Stop**: Movemos el SL a breakeven cuando llevamos X puntos de ganancia.

---

## Estrategia 2: "Trend-Rider" (Siguiendo la Tendencia con EMAs + RSI)
*La clásica que nunca falla: "la tendencia es tu amiga".*

### ¿Por qué funciona?
El NASDAQ tiende a moverse en tendencias claras durante el día. Si identificamos cuándo empieza una tendencia (cruce de medias) y nos aseguramos de no comprar en el pico (filtro RSI), podemos subirnos al tren y dejar correr las ganancias.

### Los Parámetros
*   **Temporalidad**: H1 (más fiable) o M15 (más entradas).
*   **Indicadores**:
    *   EMA Rápida: 9 periodos.
    *   EMA Lenta: 21 periodos.
    *   RSI: 14 periodos (niveles 30 y 70).

### ¿Cómo Entramos?
*   **Para Comprar**:
    *   La EMA de 9 cruza *por encima* de la EMA de 21.
    *   El RSI está *por debajo* de 70 (no estamos comprando un techo).
    *   Entramos al cierre de la vela.
*   **Para Vender**:
    *   La EMA de 9 cruza *por debajo* de la EMA de 21.
    *   El RSI está *por encima* de 30 (no estamos vendiendo un suelo).

### ¿Cómo Salimos?
*   **Stop Loss**: En el último swing (máximo o mínimo reciente) o basado en ATR (2 veces el ATR).
*   **Take Profit**: No ponemos TP fijo. Dejamos correr la operación.
*   **Señal de Salida**: Cerramos cuando las EMAs vuelven a cruzarse en la dirección contraria.

---

## Estrategia 3: "Snap-Back" (Reversión a la Media con Bollinger)
*Para cuando el mercado está aburrido y no va a ningún lado.*

### ¿Por qué funciona?
Durante las horas del almuerzo americano o antes de noticias importantes, el precio suele quedarse en un rango, rebotando como una pelota entre dos paredes. Las Bandas de Bollinger nos dicen cuándo el precio se ha "estirado" demasiado y probablemente va a regresar al centro.

### Los Parámetros
*   **Temporalidad**: M5 o M15.
*   **Indicadores**: 
    *   Bandas de Bollinger (Periodo 20, Desviación 2.0 o 2.5).
*   **Filtro Importante**: ADX menor a 25. Si el ADX está alto, hay tendencia y NO queremos operar esta estrategia.

### ¿Cómo Entramos?
*   **Para Vender**:
    *   El precio toca o cierra por encima de la **Banda Superior**.
    *   La vela de confirmación es roja (bajista).
*   **Para Comprar**:
    *   El precio toca o cierra por debajo de la **Banda Inferior**.
    *   La vela de confirmación es verde (alcista).

### ¿Cómo Salimos?
*   **Take Profit**: La **Banda del Medio** (la línea central). Esa es la media.
*   **Stop Loss**: Un poquito más allá de la banda (por ejemplo, Banda Superior + 10 puntos).

---

## Estrategia 4: "Gap Fill" (Cerrando los Huecos)
*Apostamos a que el mercado "limpiará" el hueco de la noche anterior.*

### ¿Por qué funciona?
El mercado de futuros opera por la noche. Si pasa algo importante, el precio de apertura puede estar muy lejos del cierre de ayer. Esto deja un "hueco" en el gráfico. Estadísticamente, el precio tiende a regresar y "cerrar" ese hueco antes de tomar una nueva dirección.

### Los Parámetros
*   **Temporalidad**: M5.
*   **Datos Necesarios**: El precio de cierre de ayer (vela D1) y el precio de apertura de hoy.
*   **Umbral de Gap**: El hueco tiene que ser significativo (mínimo 20 puntos, por ejemplo).

### ¿Cómo Entramos?
*   **Hora de Análisis**: 9:30 AM EST.
*   **Para Comprar**:
    *   El mercado abre *por debajo* del cierre de ayer (gap a la baja).
    *   Esperamos a que cierre la primera vela de 5 minutos.
    *   Si esa vela es verde (alcista), compramos.
*   **Para Vender**:
    *   El mercado abre *por encima* del cierre de ayer (gap al alza).
    *   Esperamos la primera vela de 5 min.
    *   Si es roja (bajista), vendemos.

### ¿Cómo Salimos?
*   **Take Profit**: El precio de cierre de ayer. Ese es el objetivo exacto.
*   **Stop Loss**: El máximo o mínimo de la primera vela de 5 minutos.

---

## Estrategia 5: "Price Action Master" (Patrones de Velas)
*Sin indicadores. Solo leemos lo que el precio nos está diciendo.*

### ¿Por qué funciona?
Los indicadores como el RSI o las medias móviles siempre van "retrasados" porque se basan en datos pasados. Los patrones de velas nos muestran lo que está pasando *ahora mismo*: quién está ganando la batalla, los compradores o los vendedores.

### Los Parámetros
*   **Temporalidad**: M15 o H1.
*   **Niveles Clave**: Números redondos cada 500 o 1000 puntos (14000, 14500, 15000, etc.). Estos niveles actúan como imanes para el precio.

### ¿Cómo Entramos?
*   **Patrones que Buscamos**:
    *   **Pin Bar (Martillo / Estrella Fugaz)**: Una vela con un cuerpo pequeño (en la parte alta o baja) y una mecha muy larga que "rechaza" un nivel.
    *   **Envolvente (Engulfing)**: Una vela grande que se "come" completamente a la vela anterior.
*   **Condiciones**:
    *   El precio tiene que estar cerca de un Número Redondo (a menos de 10-15 puntos).
    *   Se forma uno de los patrones.
    *   Entramos al cierre de la vela del patrón.

### ¿Cómo Salimos?
*   **Stop Loss**: Más allá de la mecha del Pin Bar o de la vela envolvente.
*   **Take Profit**: Basado en ratio riesgo/beneficio (por ejemplo, 3:1).
*   **Trailing Stop**: Una vez que llevamos 1:1 de ganancia, empezamos a mover el SL vela por vela.

---

## Resumen y Recomendación

| # | Estrategia | Tipo de Mercado | Dificultad |
|---|---|---|---|
| 1 | Momentum ORB | Apertura con volatilidad | ⭐⭐ |
| 2 | Trend-Rider | Mercado con tendencia clara | ⭐⭐⭐ |
| 3 | Snap-Back | Mercado lateral/aburrido | ⭐⭐⭐ |
| 4 | Gap Fill | Gaps significativos en apertura | ⭐⭐⭐ |
| 5 | Price Action Master | Reversiones en niveles clave | ⭐⭐⭐⭐ |

**¿Cuáles elegir?** Para un portafolio equilibrado, te recomiendo:
*   **#1 (Momentum)** para la apertura del mercado.
*   **#2 (Trend-Rider)** para el resto del día.
*   **#4 (Gap Fill)** cuando hay oportunidades especiales.

¡Listo para empezar a programar! 🚀
