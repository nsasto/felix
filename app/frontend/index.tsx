import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
import { ThemeProvider, getStoredTheme } from "./hooks/ThemeProvider";
import { Toaster } from "./components/ui/sonner";
import "./styles/app.css";

const rootElement = document.getElementById("root");
if (!rootElement) {
  throw new Error("Could not find root element to mount to");
}

// Load theme from localStorage for instant application (no flash of wrong theme)
const storedTheme = getStoredTheme();

const root = ReactDOM.createRoot(rootElement);
root.render(
  <React.StrictMode>
    <ThemeProvider defaultTheme={storedTheme}>
      <App />
      <Toaster position="top-center" />
    </ThemeProvider>
  </React.StrictMode>,
);
