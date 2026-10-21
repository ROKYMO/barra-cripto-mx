#!/bin/bash
# <xbar.title>Gadget cripto (BTC, ETH, SOL)</xbar.title>
# <xbar.version>v1.3</xbar.version>
# <xbar.author>ROKYMO</xbar.author>
# <xbar.author.github>ROKYMO</xbar.author.github>
# <xbar.abouturl>https://github.com/ROKYMO/barra-cripto-mx</xbar.abouturl>
# <xbar.desc>Cuánto BTC, ETH y SOL tienes, cuánto valen (MXN y USD), tu ganancia, el total y los precios en vivo.</xbar.desc>
# <xbar.dependencies>curl</xbar.dependencies>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
#
# Gadget de cripto para la barra de menú del Mac (SwiftBar).
# - Se actualiza cada 30 s (el "30s" del nombre del archivo; cámbialo a 1m, 5m, etc. si quieres).
# - Precios en USD: Kraken. Precios en MXN: Bitso. Si alguno falla, usa CoinGecko.
# - Sin internet (p. ej. a bordo) muestra el último precio guardado en gris.
# - Tus datos viven solo en tu Mac, en ~/.gadget_btc/ (no se envían a ningún lado).
# - No necesita llaves de API ni acceso a tu exchange o tu wallet.

export LC_ALL=C

DIR="$HOME/.gadget_btc"
DATOS="$DIR/datos.conf"
CACHE="$DIR/cache_v3.txt"
COMPRAS="$DIR/compras.csv"
UA="GadgetBTC/1.3"
YO="$0"
DONDE="(suma tu wallet y tu exchange)"
mkdir -p "$DIR"
rm -f "$DIR/cache.txt" "$DIR/cache_v2.txt"   # cachés de versiones anteriores

# ---------- monedas ----------
MONEDAS="BTC ETH SOL"
kraken_par() { case "$1" in BTC) echo XXBTZUSD ;; ETH) echo XETHZUSD ;; SOL) echo SOLUSD ;; esac; }
gecko_id()   { case "$1" in BTC) echo bitcoin ;; ETH) echo ethereum ;; SOL) echo solana ;; esac; }
ejemplo()    { case "$1" in BTC) echo 0.00067 ;; ETH) echo 0.015 ;; SOL) echo 0.5 ;; esac; }
limite()     { case "$1" in BTC) echo 1 ;; ETH) echo 10 ;; SOL) echo 200 ;; esac; }
libro()      { printf '%s_mxn' "$(printf '%s' "$1" | tr 'A-Z' 'a-z')"; }
clave_inv()  { if [ "$1" = BTC ]; then echo INVERTIDO_USD; else echo "INVERTIDO_$1_USD"; fi; }
moneda_ok()  { case " $MONEDAS " in *" $1 "*) echo "$1" ;; *) echo BTC ;; esac; }

# ---------- utilidades ----------
leer() { [ -f "$DATOS" ] && sed -n "s/^$1=//p" "$DATOS" | tail -n 1 | tr -d ' \r\t'; }
cache() { [ -f "$CACHE" ] && sed -n "s/^$1=//p" "$CACHE" | tail -n 1; }

guardar() { # clave valor
  local tmp
  [ -f "$DATOS" ] || printf '# Gadget BTC: tus datos. Puedes editarlo a mano.\n' > "$DATOS"
  tmp=$(mktemp "${TMPDIR:-/tmp}/gadgetbtc.XXXXXX") || return 1
  awk -v k="$1" -v v="$2" '
    index($0, k "=") == 1 { print k "=" v; hecho = 1; next }
    { print }
    END { if (!hecho) print k "=" v }' "$DATOS" > "$tmp" && cat "$tmp" > "$DATOS"
  rm -f "$tmp"
}

es_num() { case "$1" in ''|.|*[!0-9.]*|*.*.*) return 1 ;; esac; return 0; }

num_cripto() { printf '%s' "$1" | tr -d ' $' | tr ',' '.'; }   # 0,00067 -> 0.00067

num_usd() { # 1,234.50 -> 1234.50 | 1,320 -> 1320 | 55,20 -> 55.20
  local x
  x=$(printf '%s' "$1" | tr -d ' $')
  case "$x" in
    *.*)                 x=$(printf '%s' "$x" | tr -d ',') ;;
    *,[0-9][0-9][0-9])   x=$(printf '%s' "$x" | tr -d ',') ;;
    *)                   x=$(printf '%s' "$x" | tr ',' '.') ;;
  esac
  printf '%s' "$x"
}

sumar() { awk -v a="$1" -v b="$2" -v d="$3" 'BEGIN { printf "%." d "f", a + b }'; }
mayor() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a + 0 > b + 0) }'; }
precio_ok() { [ -n "$1" ] && awk -v x="$1" 'BEGIN { exit !(x + 0 > 0.01) }'; }

hora_de() { # epoch -> "21:06" (o "18/10 21:06" si no es de hoy)
  [ -n "$1" ] || return 0
  local f='+%H:%M' d
  d=$(date -r "$1" '+%Y%m%d' 2>/dev/null || date -d "@$1" '+%Y%m%d' 2>/dev/null)
  [ "$d" != "$(date '+%Y%m%d')" ] && f='+%d/%m %H:%M'
  date -r "$1" "$f" 2>/dev/null || date -d "@$1" "$f" 2>/dev/null
}

migrar_compras() { # historial v1.0 (solo BTC) -> con columna moneda
  local tmp
  [ -f "$COMPRAS" ] || return 0
  if [ "$(head -n 1 "$COMPRAS")" = "fecha,btc,usd,precio_btc_usd" ]; then
    tmp=$(mktemp "${TMPDIR:-/tmp}/gadgetbtc.XXXXXX") || return 1
    awk -F, 'NR == 1 { print "fecha,moneda,cantidad,usd,precio_usd"; next }
             { print $1 ",BTC," $2 "," $3 "," $4 }' "$COMPRAS" > "$tmp" && cat "$tmp" > "$COMPRAS"
    rm -f "$tmp"
  fi
}

pedir() { # mensaje, valor_por_defecto  -> imprime lo escrito; falla si cancela
  osascript -e 'on run argv' \
    -e 'set r to display dialog (item 1 of argv) default answer (item 2 of argv) with title "Gadget BTC" buttons {"Cancelar", "Guardar"} default button "Guardar" cancel button "Cancelar"' \
    -e 'return text returned of r' \
    -e 'end run' "$1" "$2" 2>/dev/null
}
confirmar() {
  osascript -e 'on run argv' \
    -e 'display dialog (item 1 of argv) with title "Gadget BTC" buttons {"Cancelar", "Sí, guardar"} default button "Sí, guardar" cancel button "Cancelar"' \
    -e 'end run' "$1" >/dev/null 2>&1
}
alerta() {
  osascript -e 'on run argv' -e 'display alert (item 1 of argv) message (item 2 of argv)' -e 'end run' "$1" "$2" >/dev/null 2>&1
}
avisar() {
  osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "Gadget BTC"' -e 'end run' "$1" >/dev/null 2>&1
}

# ---------- acciones del menú ----------
M=$(moneda_ok "$2"); EJ=$(ejemplo "$M"); LIM=$(limite "$M"); KC="$M"; KI=$(clave_inv "$M")

case "$1" in
  compra)
    b=$(pedir "¿Cuántos $M compraste?
(usa punto para decimales, ej. $EJ)" "") || exit 0
    b=$(num_cripto "$b")
    es_num "$b" || { alerta "Cantidad no válida" "Escribe solo el número de $M, ej. $EJ"; exit 0; }
    u=$(pedir "¿Cuántos USD pagaste por esos $M?
(incluye la comisión)" "55") || exit 0
    u=$(num_usd "$u")
    es_num "$u" || { alerta "Cantidad no válida" "Escribe solo el número de USD, ej. 55.20"; exit 0; }
    if mayor "$b" "$LIM"; then confirmar "¿Seguro? Vas a sumar $b $M." || exit 0; fi
    nb=$(sumar "$(leer "$KC")" "$b" 8)
    ni=$(sumar "$(leer "$KI")" "$u" 2)
    guardar "$KC" "$nb"
    guardar "$KI" "$ni"
    migrar_compras
    [ -f "$COMPRAS" ] || echo "fecha,moneda,cantidad,usd,precio_usd" > "$COMPRAS"
    echo "$(date '+%Y-%m-%d %H:%M'),$M,$b,$u,$(cache "${M}_USD")" >> "$COMPRAS"
    avisar "Compra guardada. Ahora tienes $nb $M."
    exit 0 ;;

  ajustar)
    b=$(pedir "¿Cuántos $M tienes en total?
$DONDE" "$(leer "$KC")") || exit 0
    b=$(num_cripto "$b")
    es_num "$b" || { alerta "Cantidad no válida" "Escribe solo el número de $M, ej. $EJ"; exit 0; }
    u=$(pedir "¿Cuántos USD has metido en total a $M?
(solo $M, con comisiones; 0 si no quieres ver ganancia)" "$(leer "$KI")") || exit 0
    u=$(num_usd "$u")
    es_num "$u" || { alerta "Cantidad no válida" "Escribe solo el número de USD, ej. 950"; exit 0; }
    guardar "$KC" "$(sumar "$b" 0 8)"
    guardar "$KI" "$(sumar "$u" 0 2)"
    avisar "Datos de $M actualizados."
    exit 0 ;;

  historial)
    migrar_compras
    if [ -f "$COMPRAS" ]; then open "$COMPRAS"
    else alerta "Aún no hay compras" "Usa «Registrar compra» después de cada compra y aquí verás el historial."
    fi
    exit 0 ;;

  barra)
    guardar BARRA "$2"
    exit 0 ;;

  ocultar)
    if [ "$(leer OCULTAR)" = "1" ]; then guardar OCULTAR 0; else guardar OCULTAR 1; fi
    exit 0 ;;
esac

# ---------- precios ----------
TD=$(mktemp -d "${TMPDIR:-/tmp}/gadgetbtc.XXXXXX")
PARES=""; IDS=""
for m in $MONEDAS; do
  PARES="$PARES${PARES:+,}${m/BTC/XBT}USD"
  IDS="$IDS${IDS:+,}$(gecko_id "$m")"
  curl -s -m 6 -A "$UA" "https://api.bitso.com/v3/ticker/?book=$(libro "$m")" > "$TD/$m" 2>/dev/null &
done
curl -s -m 6 -A "$UA" "https://api.kraken.com/0/public/Ticker?pair=$PARES" > "$TD/kraken" 2>/dev/null &
wait
KR=$(tr -d '\n' < "$TD/kraken")

kraken_usd() { printf '%s' "$KR" | sed -E -n "s/.*\"$1\":\{[^}]*\"c\":\[\"([0-9.]+)\".*/\1/p"; }
bitso() { printf '%s' "$1" | sed -E -n "s/.*\"$2\":\"(-?[0-9.]+)\".*/\1/p"; }
cambio24() { [ -n "$1" ] && [ -n "$2" ] && awk -v l="$1" -v c="$2" 'BEGIN { if (l - c > 0) printf "%.4f", c / (l - c) * 100 }'; }
gecko() { printf '%s' "$CG" | sed -E -n "s/.*\"$1\":\{[^}]*\"$2\":(-?[0-9.eE+-]+).*/\1/p"; }

i=0; FALTA=0
for m in $MONEDAS; do
  BJ=$(tr -d '\n' < "$TD/$m")
  U[$i]=$(kraken_usd "$(kraken_par "$m")"); precio_ok "${U[$i]}" || U[$i]=""
  X[$i]=$(bitso "$BJ" last);               precio_ok "${X[$i]}" || X[$i]=""
  C[$i]=""; [ -n "${X[$i]}" ] && C[$i]=$(cambio24 "${X[$i]}" "$(bitso "$BJ" change_24)")
  SU[$i]=Kraken; SX[$i]=Bitso
  { [ -z "${U[$i]}" ] || [ -z "${X[$i]}" ]; } && FALTA=1
  i=$((i + 1))
done
rm -rf "$TD"

if [ "$FALTA" = 1 ]; then
  CG=$(curl -s -m 6 -A "$UA" "https://api.coingecko.com/api/v3/simple/price?ids=$IDS&vs_currencies=usd,mxn&include_24hr_change=true" 2>/dev/null | tr -d '\n')
  i=0
  for m in $MONEDAS; do
    g=$(gecko_id "$m")
    if [ -z "${U[$i]}" ]; then U[$i]=$(gecko "$g" usd); precio_ok "${U[$i]}" || U[$i]=""; SU[$i]=CoinGecko; fi
    if [ -z "${X[$i]}" ]; then X[$i]=$(gecko "$g" mxn); precio_ok "${X[$i]}" || X[$i]=""; SX[$i]=CoinGecko; C[$i]=$(gecko "$g" mxn_24h_change); fi
    i=$((i + 1))
  done
fi

# una línea por moneda: m|cantidad|invertido|usd|mxn|chg|fuenteUSD|fuenteMXN|cacheUSD|cacheMXN|cacheCHG|cacheT|cacheHora
REG=""; i=0
for m in $MONEDAS; do
  ct=$(cache "${m}_T")
  REG="$REG${REG:+;}$m|$(leer "$m")|$(leer "$(clave_inv "$m")")|${U[$i]}|${X[$i]}|${C[$i]}|${SU[$i]}|${SX[$i]}|$(cache "${m}_USD")|$(cache "${m}_MXN")|$(cache "${m}_CHG")|$ct|$(hora_de "$ct")"
  i=$((i + 1))
done

# ---------- menú ----------
awk -v reg="$REG" -v barra="$(leer BARRA)" -v oc="$(leer OCULTAR)" \
    -v ahora="$(date +%s)" -v hnow="$(date +%H:%M)" -v cachef="$CACHE" -v yo="$YO" '
function absv(n) { return n < 0 ? -n : n }
function fmt(n, d,    s, p, ip, fp, out, neg) {
  neg = (n < 0); if (neg) n = -n
  s = sprintf("%." d "f", n)
  p = index(s, ".")
  if (p) { ip = substr(s, 1, p - 1); fp = substr(s, p) } else { ip = s; fp = "" }
  out = ""
  while (length(ip) > 3) { out = "," substr(ip, length(ip) - 2) out; ip = substr(ip, 1, length(ip) - 3) }
  if (neg && (ip out fp) ~ /[1-9]/) return "-" ip out fp
  return ip out fp
}
function precio(n) { return fmt(n, n < 1000 ? 2 : 0) }
function pct(n,    r) {
  r = sprintf("%.1f", n) + 0
  return (r > 0 ? "+" : (r < 0 ? "-" : "")) fmt(absv(r), 1) "%"
}
function dinero(n, d) { return (n < 0 ? "-$" : "$") fmt(absv(n), d) }
function ganancia(g) { return (g > 0 ? "+" : "") dinero(g, 2) " USD" }
function color(n) { return n > 0 ? VERDE : (n < 0 ? ROJO : "") }
function o(txt) { return ocu ? OCULTO : txt }
function flecha(p) { return (p >= 0 ? "▲" : "▼") fmt(absv(p), 1) "%" }
function accion(txt, args, icono, extra) {
  print txt " | bash=\"" yo "\" " args " terminal=false refresh=true sfimage=" icono (extra != "" ? " " extra : "")
}
function linea(m) { # "₿ $11,087 ▲0.2%" si tienes; si no, solo el precio en USD
  if (CANT[m] > 0 && HAYP[m]) return SIM[m] " $" fmt(VMXN[m], 0) (CONG[m] ? " " flecha(GANP[m]) : "")
  return SIM[m] " US$" precio(USD[m])
}
function seccion(m) {
  print SIM[m] " " NOM[m]
  if (CANT[m] <= 0) {
    accion("Configura cuántos " m " tienes…", "param1=ajustar param2=" m, "gearshape", "")
  } else {
    print "Tienes: " o(sprintf("%.8f", CANT[m])) " " m
    if (HAYP[m]) print "Valen: " o(dinero(VMXN[m], 0)) " MXN  ·  " o(dinero(VUSD[m], 2)) " USD"
    if (INV[m] > 0) {
      print "Invertido: " o(dinero(INV[m], 2)) " USD"
      if (CONG[m]) print "Ganancia: " o(ganancia(GAN[m])) " (" pct(GANP[m]) ") | " color(GAN[m])
      print "Costo promedio: " o(dinero(INV[m] / CANT[m], (INV[m] / CANT[m]) < 1000 ? 2 : 0)) " USD por " m
    }
  }
  if (HAYP[m]) {
    print "Precio: $" precio(USD[m]) " USD  ·  $" precio(MXN[m]) " MXN"
    if (CHG[m] != "") print "Últimas 24 h: " pct(CHG[m] + 0) " | " color(CHG[m] + 0)
  } else print "Sin precio por ahora | " GRIS
}
BEGIN {
  VERDE = "color=#1f8f4e,#5cd38a"; ROJO = "color=#c9372c,#ff6b5e"; GRIS = "color=#8e8e93,#8e8e93"
  OCULTO = "•••••"
  SIM["BTC"] = "₿"; NOM["BTC"] = "Bitcoin";  ICO["BTC"] = "bitcoinsign.circle"
  SIM["ETH"] = "Ξ"; NOM["ETH"] = "Ethereum"; ICO["ETH"] = "diamond"
  SIM["SOL"] = "◎"; NOM["SOL"] = "Solana";   ICO["SOL"] = "s.circle"
  ocu = (oc == "1")
  if (barra == "") barra = "rotar"
  if (barra == "ambos") barra = "total"

  n = split(reg, R, ";")
  for (k = 1; k <= n; k++) {
    split(R[k], f, "|"); m = f[1]; ORD[k] = m
    CANT[m] = f[2] + 0; INV[m] = f[3] + 0
    if (f[4] != "" && f[5] != "") {           # precio fresco
      USD[m] = f[4]; MXN[m] = f[5]; CHG[m] = f[6]; T[m] = ahora; H[m] = hnow; VIEJO[m] = 0
      USADA[f[7]] = 1; USADA[f[8]] = 1
    } else if (f[9] != "" && f[10] != "") {   # último precio guardado
      USD[m] = f[9]; MXN[m] = f[10]; CHG[m] = f[11]; T[m] = f[12]; H[m] = f[13]; VIEJO[m] = 1
    } else { USD[m] = ""; MXN[m] = ""; CHG[m] = ""; VIEJO[m] = 0 }
    HAYP[m] = (USD[m] + 0 > 0 && MXN[m] + 0 > 0)
    if (HAYP[m]) {   # guarda el último precio bueno para cuando no haya internet
      print m "_USD=" USD[m] > cachef; print m "_MXN=" MXN[m] > cachef
      print m "_CHG=" CHG[m] > cachef; print m "_T=" T[m] > cachef
    }
    VMXN[m] = 0; VUSD[m] = 0
    if (CANT[m] > 0 && HAYP[m]) { VMXN[m] = CANT[m] * MXN[m]; VUSD[m] = CANT[m] * USD[m] }
    CONG[m] = (CANT[m] > 0 && HAYP[m] && INV[m] > 0)
    if (CONG[m]) { GAN[m] = VUSD[m] - INV[m]; GANP[m] = GAN[m] / INV[m] * 100 }
  }
  close(cachef)

  # totales
  tienen = 0; sinprecio = 0; viejo = 0; nviejo = 0; pre = ""; totMXN = 0; totUSD = 0; invT = 0; valT = 0
  for (k = 1; k <= n; k++) {
    m = ORD[k]
    if (VIEJO[m]) { viejo = 1; LV[++nviejo] = m }
    if (CANT[m] > 0) { tienen++; pre = pre SIM[m]; if (!HAYP[m]) sinprecio = 1 }
    totMXN += VMXN[m]; totUSD += VUSD[m]
    if (CONG[m]) { invT += INV[m]; valT += VUSD[m] }
  }
  if (invT > 0) { ganT = valT - invT; ganTP = ganT / invT * 100 }
  totalOK = (tienen > 0 && !sinprecio)
  lineaTotal = pre " $" fmt(totMXN, 0) (invT > 0 ? " " flecha(ganTP) : "")

  # --- título en la barra (si hay varias líneas, SwiftBar las va rotando) ---
  nt = 0
  if (!HAYP["BTC"]) TIT[++nt] = "₿ sin red"
  else if (ocu) { for (k = 1; k <= n; k++) if (HAYP[ORD[k]]) TIT[++nt] = SIM[ORD[k]] " US$" precio(USD[ORD[k]]) }
  else if (barra == "precio") TIT[++nt] = "₿ US$" precio(USD["BTC"])
  else if (barra == "precios") {
    t = ""
    for (k = 1; k <= n; k++) if (HAYP[ORD[k]]) t = t (t != "" ? "  " : "") SIM[ORD[k]] " " precio(USD[ORD[k]])
    TIT[++nt] = t
  }
  else if (barra == "valor") TIT[++nt] = linea("BTC")
  else if (barra == "total") TIT[++nt] = (totalOK ? lineaTotal : "₿ US$" precio(USD["BTC"]))
  else {   # rotar: el total y luego cada moneda que tienes
    if (tienen > 1 && totalOK) TIT[++nt] = lineaTotal
    for (k = 1; k <= n; k++) { m = ORD[k]; if (CANT[m] > 0 && HAYP[m]) TIT[++nt] = linea(m) }
    if (nt == 0) TIT[++nt] = "₿ US$" precio(USD["BTC"])
  }
  for (k = 1; k <= nt; k++) print TIT[k] " | dropdown=false" (viejo ? " " GRIS : "")
  print "---"

  # --- total de cripto ---
  if (totalOK) {
    print "Total en cripto: " o(dinero(totMXN, 0)) " MXN  ·  " o(dinero(totUSD, 2)) " USD"
    if (invT > 0) {
      print "Invertido total: " o(dinero(invT, 2)) " USD"
      print "Ganancia total: " o(ganancia(ganT)) " (" pct(ganTP) ") | " color(ganT)
    }
    print "---"
  }

  for (k = 1; k <= n; k++) { seccion(ORD[k]); print "---" }

  # --- acciones ---
  print "Registrar compra | sfimage=plus.circle"
  for (k = 1; k <= n; k++) accion("--" ORD[k] "…", "param1=compra param2=" ORD[k], ICO[ORD[k]], "")
  print "Ajustar totales | sfimage=slider.horizontal.3"
  for (k = 1; k <= n; k++) accion("--" ORD[k] "…", "param1=ajustar param2=" ORD[k], ICO[ORD[k]], "")
  accion("Historial de compras", "param1=historial", "list.bullet.rectangle", "")
  print "Mostrar en la barra | sfimage=menubar.rectangle"
  accion("--Rotar: total y cada moneda", "param1=barra param2=rotar", "arrow.triangle.2.circlepath", (barra == "rotar" ? "checked=true" : ""))
  accion("--Solo el total (MXN) y ganancia", "param1=barra param2=total", "sum", (barra == "total" ? "checked=true" : ""))
  accion("--Solo BTC (MXN) y ganancia", "param1=barra param2=valor", "bitcoinsign.circle", (barra == "valor" ? "checked=true" : ""))
  accion("--Precio de BTC (USD)", "param1=barra param2=precio", "chart.line.uptrend.xyaxis", (barra == "precio" ? "checked=true" : ""))
  accion("--Precios de todas (USD)", "param1=barra param2=precios", "chart.bar", (barra == "precios" ? "checked=true" : ""))
  if (ocu) accion("Mostrar montos", "param1=ocultar", "eye", "")
  else accion("Ocultar montos", "param1=ocultar", "eye.slash", "")
  print "---"
  frescas = 0; for (k = 1; k <= n; k++) if (HAYP[ORD[k]] && !VIEJO[ORD[k]]) frescas++
  if (viejo && frescas == 0) print "Sin conexión · último precio: " H[LV[1]] " | size=11 " GRIS
  else if (viejo) {
    l = ""; for (k = 1; k <= nviejo; k++) l = l (k > 1 ? ", " : "") LV[k]
    print "Precio de " l " sin actualizar desde " H[LV[1]] " | size=11 " GRIS
  }
  if (frescas > 0) {
    fu = ""
    if (USADA["Kraken"]) fu = fu (fu != "" ? " / " : "") "Kraken"
    if (USADA["Bitso"]) fu = fu (fu != "" ? " / " : "") "Bitso"
    if (USADA["CoinGecko"]) fu = fu (fu != "" ? " / " : "") "CoinGecko"
    print "Actualizado " hnow " · " fu " | size=11 " GRIS
  }
  print "Actualizar ahora | refresh=true sfimage=arrow.clockwise"
}'
