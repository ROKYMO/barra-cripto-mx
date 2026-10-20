#!/bin/bash
# <xbar.title>Gadget BTC + ETH</xbar.title>
# <xbar.version>v1.1</xbar.version>
# <xbar.author>ROKYMO</xbar.author>
# <xbar.author.github>ROKYMO</xbar.author.github>
# <xbar.abouturl>https://github.com/ROKYMO/barra-cripto-mx</xbar.abouturl>
# <xbar.desc>Cuánto BTC y ETH tienes, cuánto valen (MXN y USD), tu ganancia, el total y los precios en vivo.</xbar.desc>
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
CACHE="$DIR/cache_v2.txt"
COMPRAS="$DIR/compras.csv"
UA="GadgetBTC/1.1"
YO="$0"
mkdir -p "$DIR"
rm -f "$DIR/cache.txt"   # caché de la versión 1.0

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

clave_cant() { if [ "$1" = ETH ]; then echo ETH; else echo BTC; fi; }
clave_inv()  { if [ "$1" = ETH ]; then echo INVERTIDO_ETH_USD; else echo INVERTIDO_USD; fi; }

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
precio_ok() { [ -n "$1" ] && awk -v x="$1" 'BEGIN { exit !(x + 0 > 1) }'; }

hora_de() { # epoch -> "21:06" (o "18/10 21:06" si no es de hoy)
  [ -n "$1" ] || return 0
  local f='+%H:%M' d
  d=$(date -r "$1" '+%Y%m%d' 2>/dev/null || date -d "@$1" '+%Y%m%d' 2>/dev/null)
  [ "$d" != "$(date '+%Y%m%d')" ] && f='+%d/%m %H:%M'
  date -r "$1" "$f" 2>/dev/null || date -d "@$1" "$f" 2>/dev/null
}

migrar_compras() { # historial v1.0 (solo BTC) -> v1.1 (con columna moneda)
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
M="$2"; [ "$M" = ETH ] || M=BTC
if [ "$M" = ETH ]; then EJ="0.015"; LIM=10; else EJ="0.00067"; LIM=1; fi
KC=$(clave_cant "$M"); KI=$(clave_inv "$M")

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
    if [ "$M" = ETH ]; then p=$(cache E_USD); else p=$(cache B_USD); fi
    echo "$(date '+%Y-%m-%d %H:%M'),$M,$b,$u,$p" >> "$COMPRAS"
    avisar "Compra guardada. Ahora tienes $nb $M."
    exit 0 ;;

  ajustar)
    b=$(pedir "¿Cuántos $M tienes en total?
(suma tu wallet y tu exchange)" "$(leer "$KC")") || exit 0
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
    else alerta "Aún no hay compras" "Usa «Registrar compra…» después de cada compra y aquí verás el historial."
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
TK=$(mktemp "${TMPDIR:-/tmp}/gadgetbtc.XXXXXX")
TB=$(mktemp "${TMPDIR:-/tmp}/gadgetbtc.XXXXXX")
TE=$(mktemp "${TMPDIR:-/tmp}/gadgetbtc.XXXXXX")
curl -s -m 6 -A "$UA" "https://api.kraken.com/0/public/Ticker?pair=XBTUSD,ETHUSD" > "$TK" 2>/dev/null &
curl -s -m 6 -A "$UA" "https://api.bitso.com/v3/ticker/?book=btc_mxn" > "$TB" 2>/dev/null &
curl -s -m 6 -A "$UA" "https://api.bitso.com/v3/ticker/?book=eth_mxn" > "$TE" 2>/dev/null &
wait
KR=$(tr -d '\n' < "$TK"); BB=$(tr -d '\n' < "$TB"); BE=$(tr -d '\n' < "$TE")
rm -f "$TK" "$TB" "$TE"

kraken_usd() { printf '%s' "$KR" | sed -E -n "s/.*\"$1\":\{[^}]*\"c\":\[\"([0-9.]+)\".*/\1/p"; }
bitso() { printf '%s' "$1" | sed -E -n "s/.*\"$2\":\"(-?[0-9.]+)\".*/\1/p"; }
cambio24() { [ -n "$1" ] && [ -n "$2" ] && awk -v l="$1" -v c="$2" 'BEGIN { if (l - c > 0) printf "%.4f", c / (l - c) * 100 }'; }
gecko() { printf '%s' "$CG" | sed -E -n "s/.*\"$1\":\{[^}]*\"$2\":(-?[0-9.eE+-]+).*/\1/p"; }

B_USD=$(kraken_usd XXBTZUSD); precio_ok "$B_USD" || B_USD=""
E_USD=$(kraken_usd XETHZUSD); precio_ok "$E_USD" || E_USD=""
B_MXN=$(bitso "$BB" last);    precio_ok "$B_MXN" || B_MXN=""
E_MXN=$(bitso "$BE" last);    precio_ok "$E_MXN" || E_MXN=""
B_CHG=$( [ -n "$B_MXN" ] && cambio24 "$B_MXN" "$(bitso "$BB" change_24)")
E_CHG=$( [ -n "$E_MXN" ] && cambio24 "$E_MXN" "$(bitso "$BE" change_24)")
B_FU=Kraken; E_FU=Kraken; B_FM=Bitso; E_FM=Bitso

if [ -z "$B_USD" ] || [ -z "$B_MXN" ] || [ -z "$E_USD" ] || [ -z "$E_MXN" ]; then
  CG=$(curl -s -m 6 -A "$UA" "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum&vs_currencies=usd,mxn&include_24hr_change=true" 2>/dev/null | tr -d '\n')
  if [ -z "$B_USD" ]; then B_USD=$(gecko bitcoin usd);  precio_ok "$B_USD" || B_USD=""; B_FU=CoinGecko; fi
  if [ -z "$E_USD" ]; then E_USD=$(gecko ethereum usd); precio_ok "$E_USD" || E_USD=""; E_FU=CoinGecko; fi
  if [ -z "$B_MXN" ]; then B_MXN=$(gecko bitcoin mxn);  precio_ok "$B_MXN" || B_MXN=""; B_FM=CoinGecko; B_CHG=$(gecko bitcoin mxn_24h_change); fi
  if [ -z "$E_MXN" ]; then E_MXN=$(gecko ethereum mxn); precio_ok "$E_MXN" || E_MXN=""; E_FM=CoinGecko; E_CHG=$(gecko ethereum mxn_24h_change); fi
fi

# ---------- menú ----------
awk -v btc="$(leer BTC)" -v binv="$(leer INVERTIDO_USD)" -v eth="$(leer ETH)" -v einv="$(leer INVERTIDO_ETH_USD)" \
    -v barra="$(leer BARRA)" -v oc="$(leer OCULTAR)" \
    -v bfu="$B_USD" -v bfm="$B_MXN" -v bfc="$B_CHG" -v bsu="$B_FU" -v bsm="$B_FM" \
    -v efu="$E_USD" -v efm="$E_MXN" -v efc="$E_CHG" -v esu="$E_FU" -v esm="$E_FM" \
    -v bcu="$(cache B_USD)" -v bcm="$(cache B_MXN)" -v bcc="$(cache B_CHG)" -v bct="$(cache B_T)" -v bch="$(hora_de "$(cache B_T)")" \
    -v ecu="$(cache E_USD)" -v ecm="$(cache E_MXN)" -v ecc="$(cache E_CHG)" -v ect="$(cache E_T)" -v ech="$(hora_de "$(cache E_T)")" \
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
function moneda(p, sim) { # "₿ $11,087 ▲0.2%" si tienes; si no, solo el precio en USD
  if (CANT[p] > 0 && HAYP[p]) return sim " $" fmt(VMXN[p], 0) (CONG[p] ? " " flecha(GANP[p]) : "")
  return sim " US$" fmt(USD[p], 0)
}
function preparar(p,fu, fm, fc, su, sm, cu, cm, cc, ct, ch) {
  if (fu != "" && fm != "") {
    USD[p] = fu; MXN[p] = fm; CHG[p] = fc; T[p] = ahora; H[p] = hnow; VIEJO[p] = 0
    USADA[su] = 1; USADA[sm] = 1
  } else if (cu != "" && cm != "") {
    USD[p] = cu; MXN[p] = cm; CHG[p] = cc; T[p] = ct; H[p] = ch; VIEJO[p] = 1
  } else {
    USD[p] = ""; MXN[p] = ""; CHG[p] = ""; T[p] = ""; H[p] = ""; VIEJO[p] = 0
  }
  HAYP[p] = (USD[p] + 0 > 0 && MXN[p] + 0 > 0)
  if (HAYP[p]) {   # guarda el último precio bueno para cuando no haya internet
    print p "_USD=" USD[p] > cachef; print p "_MXN=" MXN[p] > cachef
    print p "_CHG=" CHG[p] > cachef; print p "_T=" T[p] > cachef
  }
  if (CANT[p] > 0 && HAYP[p]) { VMXN[p] = CANT[p] * MXN[p]; VUSD[p] = CANT[p] * USD[p] }
  else { VMXN[p] = 0; VUSD[p] = 0 }
  CONG[p] = (CANT[p] > 0 && HAYP[p] && INV[p] > 0)
  if (CONG[p]) { GAN[p] = VUSD[p] - INV[p]; GANP[p] = GAN[p] / INV[p] * 100 }
}
function seccion(p, sim, nombre, cripto) {
  print sim " " nombre
  if (CANT[p] <= 0) {
    accion("Configura cuántos " cripto " tienes…", "param1=ajustar param2=" cripto, "gearshape", "")
  } else {
    print "Tienes: " o(sprintf("%.8f", CANT[p])) " " cripto
    if (HAYP[p]) print "Valen: " o(dinero(VMXN[p], 0)) " MXN  ·  " o(dinero(VUSD[p], 2)) " USD"
    if (INV[p] > 0) {
      print "Invertido: " o(dinero(INV[p], 2)) " USD"
      if (CONG[p]) print "Ganancia: " o(ganancia(GAN[p])) " (" pct(GANP[p]) ") | " color(GAN[p])
      print "Costo promedio: " o(dinero(INV[p] / CANT[p], 0)) " USD por " cripto
    }
  }
  if (HAYP[p]) {
    print "Precio: " dinero(USD[p], 0) " USD  ·  " dinero(MXN[p], 0) " MXN"
    if (CHG[p] != "") print "Últimas 24 h: " pct(CHG[p] + 0) " | " color(CHG[p] + 0)
  } else print "Sin precio por ahora | " GRIS
}
BEGIN {
  VERDE = "color=#1f8f4e,#5cd38a"; ROJO = "color=#c9372c,#ff6b5e"; GRIS = "color=#8e8e93,#8e8e93"
  OCULTO = "•••••"
  ocu = (oc == "1")
  if (barra == "") barra = "rotar"
  if (barra == "ambos") barra = "total"
  CANT["B"] = btc + 0; INV["B"] = binv + 0; CANT["E"] = eth + 0; INV["E"] = einv + 0
  preparar("B", bfu, bfm, bfc, bsu, bsm, bcu, bcm, bcc, bct, bch)
  preparar("E", efu, efm, efc, esu, esm, ecu, ecm, ecc, ect, ech)
  close(cachef)

  tieneB = (CANT["B"] > 0); tieneE = (CANT["E"] > 0); viejo = (VIEJO["B"] || VIEJO["E"])
  totMXN = VMXN["B"] + VMXN["E"]; totUSD = VUSD["B"] + VUSD["E"]
  invT = 0; valT = 0
  if (CONG["B"]) { invT += INV["B"]; valT += VUSD["B"] }
  if (CONG["E"]) { invT += INV["E"]; valT += VUSD["E"] }
  if (invT > 0) { ganT = valT - invT; ganTP = ganT / invT * 100 }

  # --- título en la barra (si hay varias líneas, SwiftBar las va rotando) ---
  totalOK = ((tieneB || tieneE) && (!tieneB || HAYP["B"]) && (!tieneE || HAYP["E"]))
  lineaTotal = (tieneB && tieneE ? "₿Ξ" : (tieneE ? "Ξ" : "₿")) " $" fmt(totMXN, 0) (invT > 0 ? " " flecha(ganTP) : "")
  n = 0
  if (!HAYP["B"]) TIT[++n] = "₿ sin red"
  else if (ocu) {
    TIT[++n] = "₿ US$" fmt(USD["B"], 0)
    if (HAYP["E"]) TIT[++n] = "Ξ US$" fmt(USD["E"], 0)
  }
  else if (barra == "precio") TIT[++n] = "₿ US$" fmt(USD["B"], 0)
  else if (barra == "precios") TIT[++n] = "₿ " fmt(USD["B"], 0) (HAYP["E"] ? "  Ξ " fmt(USD["E"], 0) : "")
  else if (barra == "valor") TIT[++n] = moneda("B", "₿")
  else if (barra == "total") TIT[++n] = (totalOK ? lineaTotal : "₿ US$" fmt(USD["B"], 0))
  else {   # rotar: total, BTC y ETH
    if (tieneB && tieneE && totalOK) TIT[++n] = lineaTotal
    TIT[++n] = moneda("B", "₿")
    if (HAYP["E"]) TIT[++n] = moneda("E", "Ξ")
  }
  for (i = 1; i <= n; i++) print TIT[i] " | dropdown=false" (viejo ? " " GRIS : "")
  print "---"

  # --- total de cripto ---
  # (solo si hay precio de todo lo que tienes, para no mostrar un total incompleto)
  if ((tieneB || tieneE) && (!tieneB || HAYP["B"]) && (!tieneE || HAYP["E"])) {
    print "Total en cripto: " o(dinero(totMXN, 0)) " MXN  ·  " o(dinero(totUSD, 2)) " USD"
    if (invT > 0) {
      print "Invertido total: " o(dinero(invT, 2)) " USD"
      print "Ganancia total: " o(ganancia(ganT)) " (" pct(ganTP) ") | " color(ganT)
    }
    print "---"
  }

  seccion("B", "₿", "Bitcoin", "BTC");  print "---"
  seccion("E", "Ξ", "Ethereum", "ETH"); print "---"

  # --- acciones ---
  accion("Registrar compra de BTC…", "param1=compra param2=BTC", "plus.circle", "")
  accion("Registrar compra de ETH…", "param1=compra param2=ETH", "plus.circle", "")
  print "Ajustar totales | sfimage=slider.horizontal.3"
  accion("--BTC…", "param1=ajustar param2=BTC", "bitcoinsign.circle", "")
  accion("--ETH…", "param1=ajustar param2=ETH", "diamond", "")
  accion("Historial de compras", "param1=historial", "list.bullet.rectangle", "")
  print "Mostrar en la barra | sfimage=menubar.rectangle"
  accion("--Rotar: total, BTC y ETH", "param1=barra param2=rotar", "arrow.triangle.2.circlepath", (barra == "rotar" ? "checked=true" : ""))
  accion("--Solo el total BTC + ETH (MXN) y ganancia", "param1=barra param2=total", "sum", (barra == "total" ? "checked=true" : ""))
  accion("--Solo BTC (MXN) y ganancia", "param1=barra param2=valor", "bitcoinsign.circle", (barra == "valor" ? "checked=true" : ""))
  accion("--Precio de BTC (USD)", "param1=barra param2=precio", "chart.line.uptrend.xyaxis", (barra == "precio" ? "checked=true" : ""))
  accion("--Precios de BTC y ETH (USD)", "param1=barra param2=precios", "chart.bar", (barra == "precios" ? "checked=true" : ""))
  if (ocu) accion("Mostrar montos", "param1=ocultar", "eye", "")
  else accion("Ocultar montos", "param1=ocultar", "eye.slash", "")
  print "Abrir Kraken Pro | href=https://pro.kraken.com/app/trade/btc-usd sfimage=arrow.up.right.square"
  print "---"
  if (VIEJO["B"] && VIEJO["E"]) print "Sin conexión · último precio: " H["B"] " | size=11 " GRIS
  else if (viejo) print "Precio de " (VIEJO["B"] ? "BTC" : "ETH") " sin actualizar desde " (VIEJO["B"] ? H["B"] : H["E"]) " | size=11 " GRIS
  if (!viejo && (HAYP["B"] || HAYP["E"])) {
    f = ""
    if (USADA["Kraken"]) f = f (f != "" ? " / " : "") "Kraken"
    if (USADA["Bitso"]) f = f (f != "" ? " / " : "") "Bitso"
    if (USADA["CoinGecko"]) f = f (f != "" ? " / " : "") "CoinGecko"
    print "Actualizado " hnow " · " f " | size=11 " GRIS
  }
  print "Actualizar ahora | refresh=true sfimage=arrow.clockwise"
}'
