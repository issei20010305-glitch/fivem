# re:IN city – loading screen

A rain-themed loading screen for re:IN city. The umbrella in the logo shelters the
name: rain falls across the whole screen, splashes on the canopy and drips off its tips.

## Install

1. Copy the `reincity_loadscreen` folder into your `resources` directory.
2. Add `ensure reincity_loadscreen` to `server.cfg`.
3. Remove / disable any other loading screen resource (only one can be active).

## Customise

Everything is in `web/config.js`: tagline, vertical text, status messages, rain
density / wind, and the rain sound (on/off, volume). To change the logo, replace
`web/logo.png` (transparent PNG; it is drawn in white automatically).

Open `web/index.html` in a browser to preview it — outside FiveM the progress bar
runs as a 20 second demo.
