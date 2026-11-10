import Toybox.Lang;

// Address of the Gassi-Server (ADR 0006). Fixed in the app: changing it
// needs an app update.
module ServerConfig {
    const BASE = "https://poo-tracker.kjoerg.workers.dev";
    const PRIVACY_URL = BASE + "/datenschutz";
}
