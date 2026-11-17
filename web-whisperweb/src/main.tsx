import { createRoot } from "react-dom/client";

import App from "./App.tsx";
import { ErrorBoundary } from "./components/ErrorBoundary";
import { applyAppearance, getAppearance } from "./lib/theme";
import "./index.css";

// Apply the saved appearance (System / Light / Dark / Pitch black) before
// first paint so there's no theme flash.
applyAppearance(getAppearance());

createRoot(document.getElementById("root")!).render(
  <ErrorBoundary>
    <App />
  </ErrorBoundary>
);
