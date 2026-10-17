// Replaces a service worker that Collie registered for this hostname on
// 2026-09-04, when Collie was the root handler on port 443. iOS kept that
// worker. It intercepts every navigation on the origin, including
// /mechatron-prime/, and paints Collie's own error page. curl does not run
// service workers, so the server looks fine.
//
// This script has no fetch handler. It takes the next update check, drops
// the registration, and reloads open windows onto the network.
// Keep this in step with mechatron-prime assets/unregister-service-worker.js.
self.addEventListener("install", function (event) {
	event.waitUntil(self.skipWaiting());
});

self.addEventListener("activate", function (event) {
	event.waitUntil(
		self.registration.unregister().then(function () {
			return self.clients.matchAll({ type: "window" });
		}).then(function (clients) {
			var waits = [];
			clients.forEach(function (client) {
				if (client.navigate) {
					waits.push(client.navigate(client.url));
				}
			});
			return Promise.all(waits);
		}),
	);
});
