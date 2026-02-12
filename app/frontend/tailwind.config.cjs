/** @type {import('tailwindcss').Config} */
module.exports = {
  darkMode: "class",
  content: [
    "./index.html",
    "./App.tsx",
    "./ProjectSelector.tsx",
    "./components/**/*.{ts,tsx}",
    "./hooks/**/*.{ts,tsx}",
    "./lib/**/*.{ts,tsx}",
    "./services/**/*.{ts,tsx}",
    "./utils/**/*.{ts,tsx}",
    "./src/**/*.{ts,tsx}",
    "./styles/**/*.css",
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: ["var(--font-sans)"],
        mono: ["var(--font-mono)"],
      },
      colors: {
        brand: {
          50: "#ecfdf5",
          100: "#d1fae5",
          200: "#a7f3d0",
          300: "#6ee7b7",
          400: "#4dd796",
          500: "#3ecf8e",
          600: "#2fb87a",
          700: "#26a269",
          800: "#1e8b5c",
          900: "#166d47",
          950: "#0d4530",
        },
      },
      animation: {
        "spin-slow": "spin 3s linear infinite",
        in: "enter 0.3s ease-out",
        "polling-pulse": "polling-pulse 2s ease-in-out infinite",
        "workflow-pulse": "workflow-pulse 2s ease-in-out infinite",
      },
      keyframes: {
        enter: {
          "0%": { opacity: "0", transform: "translateY(10px)" },
          "100%": { opacity: "1", transform: "translateY(0)" },
        },
        "polling-pulse": {
          "0%, 100%": { opacity: "1" },
          "50%": { opacity: "0.6" },
        },
        "workflow-pulse": {
          "0%, 100%": {
            boxShadow: "0 0 0 0 rgba(62, 207, 142, 0.4)",
            borderColor: "rgb(62, 207, 142)",
          },
          "50%": {
            boxShadow: "0 0 12px 4px rgba(62, 207, 142, 0.3)",
            borderColor: "rgb(110, 231, 183)",
          },
        },
      },
    },
  },
  plugins: [require("@tailwindcss/typography"), require("tailwindcss-animate")],
};
