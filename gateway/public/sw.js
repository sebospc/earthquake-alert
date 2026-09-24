self.addEventListener("push", event => {
  let message = null;
  try {
    message = event.data ? event.data.json() : null;
  } catch {}
  // Safari revokes the subscription after a push that shows nothing, so a broken
  // payload still shows something. Lateness is decided by the server, never this clock.
  const title = message?.title || "Alerta de sismo";
  const body = message?.body || "Abre la app para ver el detalle.";
  // Same tag: a resent message replaces the notification instead of showing twice.
  event.waitUntil(self.registration.showNotification(title, { body, tag: message?.tag }));
});

self.addEventListener("notificationclick", event => {
  event.notification.close();
  event.waitUntil(self.clients.openWindow("/"));
});
