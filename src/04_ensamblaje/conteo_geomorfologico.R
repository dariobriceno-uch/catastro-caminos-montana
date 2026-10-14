# Conteo informativo (no escribe en la base): tramos y roles que cumplen el nivel geomorfológico.
suppressWarnings(suppressMessages({library(arrow)}))
d <- as.data.frame(read_parquet("data/processed/tramos.parquet",
     col_select = c("id_tramo","rol","region","clase_kapos","cruza_portezuelo","cota_max","longitud_calc_m")))
cat("n tramos:", nrow(d), "\n")
sr <- is.na(d$rol) | d$rol %in% c("S/R","-") | grepl("^S/R", d$rol)
g  <- (d$clase_kapos %in% 1:5) | (d$cruza_portezuelo %in% TRUE)
cat("tramos nivel geomorfologico (Kapos 1-5 o portezuelo):", sum(g), " km:", round(sum(d$longitud_calc_m[g])/1000), "\n")
cat("  Kapos 1-5:", sum(d$clase_kapos %in% 1:5), " | portezuelo:", sum(d$cruza_portezuelo %in% TRUE), "\n")
cat("roles identificables con >=1 tramo geomorfologico:", length(unique(d$rol[g & !sr])), "\n")
cat("tramos geomorfologicos sin rol identificable:", sum(g & sr), "\n")
cat("tramos con cota_max >= 1500 m:", sum(d$cota_max >= 1500, na.rm=TRUE), " roles:", length(unique(d$rol[d$cota_max >= 1500 & !sr])), "\n")
x <- d[g, ]; ok <- !sr[g]
a <- aggregate(cbind(tramos = 1, km = x$longitud_calc_m/1000) ~ region, x, sum)
a$roles <- sapply(a$region, function(r) length(unique(x$rol[x$region == r & ok])))
a$km <- round(a$km)
print(a[order(-a$tramos), ], row.names = FALSE)
