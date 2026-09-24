// Coverage decisions for the page, kept free of DOM so they can be tested with node.

export function kmBetween(a, b) {
  const toRad = degrees => degrees * Math.PI / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLon = toRad(b.lon - a.lon);
  const h = Math.sin(dLat / 2) ** 2
    + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLon / 2) ** 2;
  return 2 * 6371 * Math.asin(Math.sqrt(h));
}

/**
 * "full" | "partial" | "none". Thresholds come from sensors.json `coverage`.
 * Only a sensor marked public: true can cover anyone; a missing flag fails closed.
 */
export function coverageTier(km, sensor, thresholds) {
  if (sensor.public !== true) return "none";
  if (km <= thresholds.full_km) return "full";
  if (km <= thresholds.partial_km) return "partial";
  return "none";
}

/** The closest public sensor with its distance and tier, from a sensors.json document. */
export function nearestSensor(here, sensorList) {
  const nearest = sensorList.sensors
    .filter(sensor => sensor.public === true)
    .map(sensor => ({ ...sensor, km: kmBetween(here, sensor) }))
    .reduce((best, sensor) => (best === null || sensor.km < best.km ? sensor : best), null);
  if (nearest === null) return null;
  return { ...nearest, tier: coverageTier(nearest.km, nearest, sensorList.coverage) };
}

export const TIER_TEXT = {
  full: "Cobertura completa (sismos desde M4.5).",
  partial: "Cobertura parcial: solo sismos desde M5.0.",
  none: "Tu zona todavía no tiene cobertura."
};

function formatAge(ms) {
  const minutes = Math.floor(ms / 60_000);
  if (minutes < 1) return "menos de un minuto";
  if (minutes < 120) return `${minutes} min`;
  return `${Math.floor(minutes / 60)} h`;
}

/**
 * { healthy, text } for one sensor. `status` is the /status body, or null when it did not
 * answer: an unreachable gateway is red, never "still green from last time".
 * The server decides staleness; this only picks the words.
 */
export function coverageState(status, sensorId) {
  if (!status) {
    return { healthy: false, text: "No se pudo consultar el estado. Sin cobertura confirmada." };
  }
  if (!status.relay_enabled) {
    return { healthy: false, text: "Reenvío detenido. Ahora no vas a recibir alertas." };
  }
  const sensor = status.sensors.find(entry => entry.id === sensorId);
  if (!sensor) {
    return { healthy: false, text: "Tu sensor ya no existe. Vuelve a activar las alertas." };
  }
  if (sensor.stale) {
    return { healthy: false, text: "El sensor no reporta hace más de 15 min. Sin cobertura por ahora." };
  }
  if (sensor.aea_stale || sensor.aea_ok !== true) {
    return {
      healthy: false,
      text: "No está confirmado que el sensor pueda recibir alertas. Sin cobertura por ahora."
    };
  }
  // This page is the web push channel: an APNs-only outage must not turn it red.
  if (!sensor.covered_webpush) return { healthy: false, text: "Sin cobertura por ahora." };
  // Both checks have to be fresh, so the older one is the honest age. Server clock only.
  const oldest = Math.min(Date.parse(sensor.last_heartbeat_at), Date.parse(sensor.aea_checked_at));
  return { healthy: true, text: `Última verificación hace ${formatAge(Date.parse(status.now) - oldest)}.` };
}
