import daisyui from "daisyui";

export default {
  content: ["./app/**/*.{svelte,js,css,html.erb}"],
  theme: {
    extend: {
      keyframes: {
        fadeIn: {
          "0%": { opacity: 0 },
          "100%": { opacity: 100 },
        },
        denied: {
          "0%": {
            transform: "translateX(0)",
          },
          "6.5%": {
            transform: "translateX(-6px) rotateY(-9deg)",
          },

          "18.5%": {
            transform: "translateX(5px) rotateY(7deg)",
          },

          "31.5%": {
            transform: "translateX(-3px) rotateY(-5deg)",
          },

          "43.5%": {
            transform: "translateX(2px) rotateY(3deg)",
          },
          "50%": {
            transform: "translateX(0)",
          },
        },
      },
      animation: {
        "fade-in-fast": "fadeIn 100ms ease-in",
        "fade-in-medium": "fadeIn 250ms ease-in",
        "fade-in-slow": "fadeIn 5s linear",
        "fade-in-1s": "fadeIn 1s linear",
        "fade-in": "fadeIn 500ms ease-in",
        spin: "spin 3s linear infinite",
        "bounce-some": "bounce 1s 5 reverse",
        "ping-once": "ping 1s",
        denied: "denied 1s",
      },
    },
    screens: {
      sm: "420px",
      md: "512px",
      lg: "1024px",
      xl: "1280px",
    },
  },
  plugins: [daisyui],
  daisyui: {
    themes: [
      {
        light: {
          ...require("daisyui/src/theming/themes").light,
          secondary: "#a855f7",
        },
      },
      {
        dark: {
          ...require("daisyui/src/theming/themes").dark,
          secondary: "#a855f7",
        },
      },
      {
        manage: {
          primary: "oklch(65.69% 0.196 275.75)",
          secondary: "oklch(74.8% 0.26 342.55)",
          accent: "oklch(74.51% 0.167 183.61)",
          neutral: "#2a323c",
          "neutral-content": "#A6ADBB",
          "base-100": "#1d232a",
          "base-200": "#191e24",
          "base-300": "#15191e",
          "base-content": "#A6ADBB",
        },
      },
    ],
    logs: false,
  },
};
