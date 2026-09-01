-- BUILD ROWS: NOTHING MAY OVERLAP, AT ANY TEXT LENGTH.
--
-- The same failure the journal rail had, in a second place. Each row nailed
-- `detail` to a fixed -30 and gave the whole row a fixed height of 46. That
-- held only while `meta` fitted on one line. Adding the ST/AoE figures pushed
-- meta onto a second line, so it ran straight through the detail text:
--
--   MEASURED · 7 fights  thin sample · AoE
--   6.0M(7)
--   composition was never captured -- damage only     <- drawn on top
--
-- Placement is measured now. This simulates that pass and asserts the
-- invariant, with the long-meta case that actually broke.
--
--   node tools/run_lua.js tools/buildrow_layout_test.lua

-- One wrapped line per 34 characters, roughly the 268px meta column.
local function Wrap(text, perLine)
  return math.max(1, math.ceil(#(text or "") / (perLine or 34))) * 12
end

-- Mirrors the placement in BL.Refresh: meta measured, detail below it, row
-- height derived from both.
local function layout(metaText, detailText)
  local metaH = Wrap(metaText, 34)
  local detailTop = 17 + metaH + 2
  local detailH = (detailText ~= "") and Wrap(detailText, 52) or 0
  local h = detailTop + ((detailText ~= "") and (detailH + 8) or 4)
  if h < 34 then h = 34 end
  return {
    name   = { top = 0,  bottom = 15 },
    meta   = { top = 17, bottom = 17 + metaH },
    detail = { top = detailTop, bottom = detailTop + detailH },
    height = h,
  }
end

local function check(label, metaText, detailText)
  local b = layout(metaText, detailText)
  assert(b.meta.top >= b.name.bottom,
    label .. ": meta overlaps the name")
  if detailText ~= "" then
    assert(b.detail.top >= b.meta.bottom,
      ("%s: detail starts at %d but meta runs to %d -- OVERLAP")
        :format(label, b.detail.top, b.meta.bottom))
    assert(b.height >= b.detail.bottom,
      ("%s: row is %dpx but detail reaches %d -- CLIPPED")
        :format(label, b.height, b.detail.bottom))
  else
    assert(b.height >= b.meta.bottom,
      label .. ": row too short for its meta line")
  end
  print(("%-22s meta %2d-%2d  detail %2d-%2d  row %dpx")
    :format(label, b.meta.top, b.meta.bottom,
            b.detail.top, b.detail.bottom, b.height))
  return b
end

-- 1. The old happy case: short meta, one line each.
check("short meta", "MEASURED · 40 fights", "27 S · 7 core · +82% adaptive")

-- 2. THE CASE THAT BROKE: meta carrying fights + thin-sample + both buckets.
local long = "MEASURED · 249 fights · ST 98k(8) / AoE 803k(182)"
local twoLine = check("both buckets", long, "composition was never captured -- damage only")
assert(twoLine.meta.bottom > 29,
  "this meta must genuinely wrap, or the test is not exercising the bug")

-- 3. Worst case: wrapped meta AND a long composition line.
check("long meta + detail",
  "MEASURED · 427 fights  thin sample · ST 91k(71) / AoE 513k(234)",
  "27 S · 7 core · +82% adaptive · 223k hp · 59.6% crit")

-- 4. No detail at all (a row whose composition was never captured and whose
--    Detail() returned "") must still not clip its meta.
check("no detail", "MEASURED · 3 fights  thin sample · AoE 320k(3)", "")

-- 5. A row must never be shorter than the floor, however little it holds.
local tiny = layout("MEASURED", "")
assert(tiny.height >= 34, "row height floor must hold, got " .. tiny.height)
print(("%-22s row %dpx (floor)"):format("minimal", tiny.height))

-- 6. Growing the meta must grow the ROW, not just push text through the
--    boundary -- that is precisely what a fixed height failed to do.
local a = layout("MEASURED · 8 fights", "x")
local b = layout("MEASURED · 249 fights · ST 98k(8) / AoE 803k(182)", "x")
assert(b.height > a.height,
  "a taller meta must produce a taller row: " .. a.height .. " vs " .. b.height)
print(("%-22s %dpx -> %dpx as meta wraps"):format("row grows", a.height, b.height))

print("\nBUILD ROW LAYOUT OK -- measured placement, no overlap, no clipping.")
