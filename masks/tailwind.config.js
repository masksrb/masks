import typography from "@tailwindcss/typography";
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
};
