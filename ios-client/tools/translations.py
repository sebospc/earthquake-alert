"""Fills en and pt-BR in the String Catalogs, every entry "needs_review" until a native reviewer
and investigator's docs/research/languages.md (official protective-action wording) sign off.
Consent and legal texts stay Spanish-only (shouldTranslate false): the legal work covers
Colombia only. Run from ios-client/: python3 tools/translations.py"""
import json

# TODO(legal, per country): translate once each country's privacy notice and terms exist.
SPANISH_ONLY = {
    "Antes de empezar",
    "Para avisarle guardamos el identificador de notificaciones de su iPhone y una zona aproximada de unos 11 km. Su posición exacta nunca sale del teléfono.",
    "Esta app no es un sistema oficial ni del Estado. Puede fallar o llegar tarde, y no reemplaza las indicaciones de las autoridades.",
    "Aviso de privacidad",
    "Términos de uso",
    "Acepto",
    "Retirar consentimiento",
    "¿Retirar su consentimiento?",
    "Dejará de recibir alertas de sismo y borraremos su registro del servidor.",
    "Aún no pudimos borrar su registro del servidor. Seguimos intentando; hasta entonces podría llegarle alguna alerta.",
    "%@ %@",  # icon + words, both already localized
}

TRANSLATIONS = {
    "Abrir Ajustes": ("Open Settings", "Abrir Ajustes"),
    "Activar": ("Turn On", "Ativar"),
    "Activar alertas": ("Turn On Alerts", "Ativar alertas"),
    "Activo": ("Active", "Ativo"),
    "Ahora mismo no podemos avisarle. Lo estamos arreglando.": ("We can't alert you right now. We're fixing it.", "No momento não podemos avisar você. Estamos resolvendo."),
    "Ahora mismo no podemos avisarle. Revise su conexión a internet.": ("We can't alert you right now. Check your internet connection.", "No momento não podemos avisar você. Verifique sua conexão com a internet."),
    "Alerta de prueba": ("Test Alert", "Alerta de teste"),
    "Alerta de sismo": ("Earthquake Alert", "Alerta de terremoto"),
    "Alertas activas": ("Alerts On", "Alertas ativos"),
    "Alertas de sismo": ("Earthquake Alerts", "Alertas de terremoto"),
    "Alertas desactivadas": ("Alerts Off", "Alertas desativados"),
    "Aviso atrasado": ("Late Notice", "Aviso atrasado"),
    "Cerrar": ("Close", "Fechar"),
    "Cobertura": ("Coverage", "Cobertura"),
    "Cobertura completa": ("Full coverage", "Cobertura completa"),
    "Cobertura limitada: solo le avisaremos de sismos fuertes.": ("Limited coverage: we'll only alert you about strong earthquakes.", "Cobertura limitada: só avisaremos sobre terremotos fortes."),
    "Cobertura parcial: algunos sismos pequeños podrían no avisarse.": ("Partial coverage: some small earthquakes may not trigger an alert.", "Cobertura parcial: alguns terremotos pequenos podem não ser avisados."),
    "Con Concentración activa, el aviso puede llegar en silencio.": ("With a Focus on, the alert may arrive silently.", "Com um Foco ativado, o aviso pode chegar em silêncio."),
    "Enviada. Debería sonar en unos segundos.": ("Sent. It should sound in a few seconds.", "Enviado. Deve tocar em alguns segundos."),
    "Enviando…": ("Sending…", "Enviando…"),
    "Espere unos minutos para probar de nuevo.": ("Wait a few minutes to try again.", "Aguarde alguns minutos para testar de novo."),
    "Falta su ubicación": ("Location Needed", "Falta sua localização"),
    "La usamos para elegir los sensores cercanos. Su posición exacta no sale del teléfono.": ("We use it to choose nearby sensors. Your exact position never leaves the phone.", "Nós a usamos para escolher os sensores próximos. Sua posição exata não sai do telefone."),
    "Las alertas pueden no sonar": ("Alerts May Not Sound", "Os alertas podem não tocar"),
    "Le avisamos cuando se detecta un sismo cerca de usted.": ("We alert you when an earthquake is detected near you.", "Avisamos você quando um terremoto é detectado perto de você."),
    "Le enviamos una alerta de prueba para que escuche cómo suena.": ("We send you a test alert so you can hear how it sounds.", "Enviamos um alerta de teste para você ouvir como ele soa."),
    "Llegó. Así sonará una alerta.": ("It arrived. This is how an alert will sound.", "Chegou. É assim que um alerta vai tocar."),
    "Muestra los sensores que lo cubren": ("Shows the sensors that cover you", "Mostra os sensores que cobrem você"),
    "Ningún sensor cerca por ahora.": ("No sensor nearby yet.", "Nenhum sensor por perto por enquanto."),
    "No llegó. Revise que las notificaciones estén activadas.": ("It didn't arrive. Check that notifications are on.", "Não chegou. Verifique se as notificações estão ativadas."),
    "No se pudo enviar. Revise su conexión a internet.": ("Couldn't send. Check your internet connection.", "Não foi possível enviar. Verifique sua conexão com a internet."),
    "Permita las notificaciones para que la alerta le llegue al instante.": ("Allow notifications so the alert reaches you instantly.", "Permita as notificações para que o alerta chegue na hora."),
    "Probar alerta": ("Send Test Alert", "Enviar alerta de teste"),
    "Recibida %@": ("Received %@", "Recebido %@"),
    "Reintentando. Mientras tanto no recibirá alertas.": ("Retrying. Until then you won't get alerts.", "Tentando de novo. Enquanto isso você não receberá alertas."),
    "Sensores que lo cubren": ("Sensors covering you", "Sensores que cobrem você"),
    "Servicio interrumpido": ("Service Interrupted", "Serviço interrompido"),
    "Servicio interrumpido: ahora mismo no podemos avisarle.": ("Service interrupted: we can't alert you right now.", "Serviço interrompido: no momento não podemos avisar você."),
    "Sin conexión con el servidor": ("No Connection to the Server", "Sem conexão com o servidor"),
    "Sin cobertura aún": ("No Coverage Yet", "Sem cobertura ainda"),
    "Sin datos": ("No data", "Sem dados"),
    "Sin permiso no podemos avisarle.": ("Without permission we can't alert you.", "Sem permissão não podemos avisar você."),
    "Sin señal": ("No signal", "Sem sinal"),
    "Su posición exacta no sale del teléfono.": ("Your exact position never leaves the phone.", "Sua posição exata não sai do telefone."),
    "Su teléfono aún no está registrado. Reintentando.": ("Your phone isn't registered yet. Retrying.", "Seu telefone ainda não está registrado. Tentando de novo."),
    "Su zona todavía no tiene cobertura.": ("Your area has no coverage yet.", "Sua região ainda não tem cobertura."),
    "Ubicación actualizada %@. Abra la app en su zona para actualizarla.": ("Location updated %@. Open the app in your area to update it.", "Localização atualizada %@. Abra o app na sua região para atualizá-la."),
    "Un paso más": ("One More Step", "Mais um passo"),
    "Verifique sus alertas de sismo": ("Check your earthquake alerts", "Verifique seus alertas de terremoto"),
    "Abra la app para confirmar que sus alertas siguen activas.": ("Open the app to confirm your alerts are still on.", "Abra o app para confirmar que seus alertas continuam ativos."),
    # InfoPlist
    "CFBundleDisplayName": ("Sismo", "Sismo"),
    "NSLocationWhenInUseUsageDescription": ("Your location is used to choose the nearest earthquake sensors. The server only gets an approximate area, never your exact position.", "Sua localização é usada para escolher os sensores de terremoto mais próximos. O servidor recebe só uma área aproximada, nunca sua posição exata."),
    "NSLocationAlwaysAndWhenInUseUsageDescription": ("To switch sensors when you travel, even with the app closed. The server only gets an approximate area, never your exact position.", "Para trocar de sensores quando você viaja, mesmo com o app fechado. O servidor recebe só uma área aproximada, nunca sua posição exata."),
}

# The push keys from docs/ios-contract.md, "Localized text". Not in the source code, so kept here.
# Protective-action wording (ALERT_BODY_*, LATE_ALERT_BODY) stays Spanish in every language
# until investigator's docs/research/languages.md gives the official phrases: never invented.
CONTRACT_SPANISH = {
    "ALERT_TITLE": "Alerta de sismo",
    "ALERT_BODY_MAGNITUDE": "Sismo M%@ cerca de su zona. Protéjase ahora.",
    "ALERT_BODY_NO_MAGNITUDE": "Posible sismo cerca de su zona. Protéjase ahora.",
    "LATE_ALERT_TITLE": "Aviso de sismo atrasado",
    "LATE_ALERT_BODY": "El sismo ocurrió hace %@ min. Ya no es un aviso anticipado.",
    "TEST_ALERT_TITLE": "Alerta de prueba",
    "TEST_ALERT_BODY": "Así sonará una alerta de sismo. Esto es solo una prueba.",
    "SERVICE_DOWN_TITLE": "Servicio interrumpido",
    "SERVICE_DOWN_BODY": "Ahora mismo no podemos avisarle.",
    "COVERAGE_RESTORED_TITLE": "Cobertura restablecida",
    "COVERAGE_RESTORED_BODY": "Las alertas de su zona vuelven a funcionar.",
    "NO_COVERAGE_TITLE": "Sin cobertura en su zona",
    "NO_COVERAGE_BODY": "Su zona todavía no tiene cobertura.",
}
AWAITING_OFFICIAL_WORDING = {"ALERT_BODY_MAGNITUDE", "ALERT_BODY_NO_MAGNITUDE", "LATE_ALERT_BODY"}
TRANSLATIONS.update({key: (CONTRACT_SPANISH[key], CONTRACT_SPANISH[key]) for key in AWAITING_OFFICIAL_WORDING})
TRANSLATIONS.update({
    "ALERT_TITLE": ("Earthquake Alert", "Alerta de terremoto"),
    "LATE_ALERT_TITLE": ("Late Earthquake Notice", "Aviso de terremoto atrasado"),
    "TEST_ALERT_TITLE": ("Test Alert", "Alerta de teste"),
    "TEST_ALERT_BODY": ("This is how an earthquake alert will sound. This is only a test.", "É assim que um alerta de terremoto vai tocar. Isto é só um teste."),
    "SERVICE_DOWN_TITLE": ("Service Interrupted", "Serviço interrompido"),
    "SERVICE_DOWN_BODY": ("We can't alert you right now.", "No momento não podemos avisar você."),
    "COVERAGE_RESTORED_TITLE": ("Coverage Restored", "Cobertura restabelecida"),
    "COVERAGE_RESTORED_BODY": ("Alerts for your area work again.", "Os alertas da sua região voltaram a funcionar."),
    "NO_COVERAGE_TITLE": ("No Coverage in Your Area", "Sem cobertura na sua região"),
    "NO_COVERAGE_BODY": ("Your area has no coverage yet.", "Sua região ainda não tem cobertura."),
})

INFOPLIST_SPANISH = {
    "CFBundleDisplayName": "Sismo",
    "NSLocationWhenInUseUsageDescription": "Su ubicación se usa para elegir los sensores de sismo más cercanos. Al servidor solo llega una zona aproximada, nunca su posición exacta.",
    "NSLocationAlwaysAndWhenInUseUsageDescription": "Para cambiar de sensores cuando usted viaja, aunque la app esté cerrada. Al servidor solo llega una zona aproximada, nunca su posición exacta.",
}


def unit(value, state):
    return {"stringUnit": {"state": state, "value": value}}


def fill(path, extra_keys=None):
    catalog = json.load(open(path))
    for key, spanish in (extra_keys or {}).items():
        entry = catalog["strings"].setdefault(key, {})
        entry["extractionState"] = "manual"  # keeps sync from marking it stale
        entry["localizations"] = {"es": unit(spanish, "translated")}
    for key, entry in catalog["strings"].items():
        if key in SPANISH_ONLY:
            entry["shouldTranslate"] = False
            entry.pop("localizations", None)
            continue
        english, portuguese = TRANSLATIONS[key]  # KeyError = a new string without translations: add it
        entry.setdefault("localizations", {}).update(
            {"en": unit(english, "needs_review"), "pt-BR": unit(portuguese, "needs_review")})
    json.dump(catalog, open(path, "w"), ensure_ascii=False, indent=2, sort_keys=True)


fill("EarthquakeRelay/Localizable.xcstrings", CONTRACT_SPANISH)
fill("RelayCore/Sources/RelayCore/Localizable.xcstrings")
fill("EarthquakeRelay/InfoPlist.xcstrings", INFOPLIST_SPANISH)
