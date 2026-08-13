import { createRoot } from "react-dom/client";

import App from "./App.tsx";
import { startPWA } from "./sr/pwa";
import "./index.css";

createRoot(document.getElementById("root")!).render(<App />);

// Offline support and keyboard tracking: both belong to the shell around the
// app, not to any screen inside it.
startPWA();
