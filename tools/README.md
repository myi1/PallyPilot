# tools

Offline checks. Neither needs the game client — which matters, because the only
other way to test this addon is to log in and read a screenshot.

Install the dependencies once:

```bash
npm install
```

## Syntax check

Parses every `.lua` in a folder as Lua 5.1 (the client's version).

```bash
node luacheck.js ..
```

## Running addon Lua offline

`run_lua.js` loads a script into [fengari](https://fengari.io/), a Lua VM in
JavaScript. With a stubbed WoW API in front of it, real addon code can be
executed and asserted on without logging in:

```bash
node run_lua.js <script.lua>
```

The worked example lives in CallboardHunter's `tools/` — the route runner moved
there in PallyPilot 0.75.0, and its state-machine tests went with it.
