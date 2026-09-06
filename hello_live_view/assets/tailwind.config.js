// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

module.exports = {
  content: [
    "./js/**/*.js",
    "../lib/*_web.ex",
    "../lib/*_web/**/*.*ex"
  ],
  // The .be-* chrome in css/app.css is a small design system: keep every part
  // of it in the bundle even when nothing on the page happens to use it yet,
  // so reaching for `.be-btn` in a new template just works.
  safelist: [{ pattern: /^be-/ }],
  theme: {
    extend: {
      colors: {
        brand: "#FD4F00",
        // A modern reading of the BeOS/Haiku palette. The same values are
        // exposed as CSS custom properties (--be-*) in css/app.css.
        be: {
          panel: "#d8d8d8",
          "panel-hi": "#eaeaea",
          "panel-lo": "#c4c4c4",
          light: "#ffffff",
          shadow: "#9a9a9a",
          "shadow-deep": "#6d6d6d",
          outline: "#2c2c2c",
          yellow: "#ffcb00",
          "yellow-hi": "#ffe066",
          "yellow-lo": "#e8ac00",
          desktop: "#336698",
          ink: "#101010",
          "ink-soft": "#4a4a4a",
          link: "#12459a",
          nerves: "#fd4f00",
        },
      },
      fontFamily: {
        sans: ['"Helvetica Neue"', "Helvetica", "Arial", '"Liberation Sans"', "system-ui", "sans-serif"],
        mono: ['"DejaVu Sans Mono"', "ui-monospace", '"SF Mono"', "Menlo", "Consolas", "monospace"],
      },
    },
  },
  plugins: [
    require("@tailwindcss/forms"),
    // Allows prefixing tailwind classes with LiveView classes to add rules
    // only when LiveView classes are applied, for example:
    //
    //     <div class="phx-click-loading:animate-ping">
    //
    plugin(({addVariant}) => addVariant("phx-click-loading", [".phx-click-loading&", ".phx-click-loading &"])),
    plugin(({addVariant}) => addVariant("phx-submit-loading", [".phx-submit-loading&", ".phx-submit-loading &"])),
    plugin(({addVariant}) => addVariant("phx-change-loading", [".phx-change-loading&", ".phx-change-loading &"])),

    // Embeds Heroicons (https://heroicons.com) into your app.css bundle
    // See your `CoreComponents.icon/1` for more information.
    //
    plugin(function({matchComponents, theme}) {
      let iconsDir = path.join(__dirname, "../deps/heroicons/optimized")
      let values = {}
      let icons = [
        ["", "/24/outline"],
        ["-solid", "/24/solid"],
        ["-mini", "/20/solid"],
        ["-micro", "/16/solid"]
      ]
      icons.forEach(([suffix, dir]) => {
        fs.readdirSync(path.join(iconsDir, dir)).forEach(file => {
          let name = path.basename(file, ".svg") + suffix
          values[name] = {name, fullPath: path.join(iconsDir, dir, file)}
        })
      })
      matchComponents({
        "hero": ({name, fullPath}) => {
          let content = fs.readFileSync(fullPath).toString().replace(/\r?\n|\r/g, "")
          let size = theme("spacing.6")
          if (name.endsWith("-mini")) {
            size = theme("spacing.5")
          } else if (name.endsWith("-micro")) {
            size = theme("spacing.4")
          }
          return {
            [`--hero-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
            "-webkit-mask": `var(--hero-${name})`,
            "mask": `var(--hero-${name})`,
            "mask-repeat": "no-repeat",
            "background-color": "currentColor",
            "vertical-align": "middle",
            "display": "inline-block",
            "width": size,
            "height": size
          }
        }
      }, {values})
    })
  ]
}
