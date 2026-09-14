/**
 * Generate a clean PDF table from real5_battle_calc_output.txt
 * Rows = games, columns = battles; conditional formatting by goal met (Y/N).
 * Small sample sizes (denominator <= 3) use softer fail styling so they aren't penalized heavily.
 *
 * Usage: node generate-pdf.mjs [input.txt] [output.pdf] [pbp.csv] [logo] [gameId1] [gameId2] ...
 * Default: ../real5_battle_calc_output.txt -> ./season_battle_report.pdf
 * Optional game IDs: only generate per-game PDFs for those; if omitted, generate all.
 */

import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import React from "react";
import {
  Document,
  Page,
  View,
  Text,
  Image,
  StyleSheet,
  renderToFile,
} from "@react-pdf/renderer";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

/** Per-game met column: Y/N (reliable in PDF Helvetica; ✓/✗ need a font that often fails to embed). */
function metSymbol(met) {
  return met ? "Y" : "N";
}

/** Load logo as data URL so @react-pdf Image can render it (avoids path resolution issues). */
function loadLogoDataUrl(filePath) {
  if (!filePath || !fs.existsSync(filePath)) return null;
  try {
    const buf = fs.readFileSync(filePath);
    const base64 = buf.toString("base64");
    const ext = path.extname(filePath).toLowerCase();
    const mime = ext === ".png" ? "image/png" : ext === ".jpg" || ext === ".jpeg" ? "image/jpeg" : "image/png";
    return `data:${mime};base64,${base64}`;
  } catch {
    return null;
  }
}

const BATTLE_ORDER = [
  "B1a",
  "B1b",
  "B2a",
  "B2b",
  "B3a",
  "B3b",
  "B3c",
  "B4",
  "B5a",
  "B5b",
];

/** Header label for each battle column (B1a etc. in front, short description) */
const BATTLE_LABELS = {
  B1a: "B1a Leadoff Runners (Off)",
  B1b: "B1b Leadoff Runners (Def)",
  B2a: "B2a Leadoff Runs % (Off)",
  B2b: "B2b Leadoff Stranded % (Def)",
  B3a: "B3a Total Baserunners (Off)",
  B3b: "B3b Total Baserunners (Def)",
  B3c: "B3c Total Bases + XBs (Off)",
  B4: "B4 Defensive Errors (Pitch)",
  B5a: "B5a BB+HBP (Off) vs K",
  B5b: "B5b BB+HBP (Def)",
};

/** Game IDs to exclude from the report (empty = include all games) */
const EXCLUDED_GAME_IDS = [];

/** Battle shortKeys that are rate metrics — average row shows % (e.g. B2a, B2b). */
const RATE_METRIC_KEYS = ["B2a", "B2b"];

const SMALL_SAMPLE_THRESHOLD = 3; // for % metrics only: den <= this gets softer fail styling

/** Goals for average-row "met" (count metrics: threshold; rate: %). B5a is special (more BB+HBP than K). */
const AVG_GOALS = {
  B1a: { min: 4 },
  B1b: { max: 3 },
  B2a: { pctMin: 67 },
  B2b: { pctMin: 70 },
  B3a: { min: 16 },
  B3b: { max: 13 },
  B3c: { min: 24 },
  B4: { max: 0 },
  B5a: "more", // sum(num) > sum(den)
  B5b: { max: 4 },
};

/** Success row: treat as "goal met" when success % >= this. */
const SUCCESS_PCT_GOAL = 67;

/** One-line summary of what the numbers mean for each battle (num/den from display). */
function battleSummaryLine(shortKey, num, den) {
  const n = num ?? 0;
  const d = den ?? 0;
  switch (shortKey) {
    case "B1a":
      return `${n} leadoff runners (goal 4+)`;
    case "B1b":
      return `${n} leadoff runners allowed (goal <=3)`;
    case "B2a":
      return `${n} leadoff runners scored from ${d} leadoff opps (goal 67%+)`;
    case "B2b":
      return `${n} leadoff runners stranded from ${d} opportunities (goal 70%+)`;
    case "B3a":
      return `${n} total baserunners (goal 16+)`;
    case "B3b":
      return `${n} baserunners allowed (goal <=13)`;
    case "B3c":
      return `${n} total bases + XBs (goal 24)`;
    case "B4":
      return `${n} errors (goal 0)`;
    case "B5a":
      return `${n} BB+HBP vs ${d} K (goal: more BB+HBP than K)`;
    case "B5b":
      return `${n} BB+HBP allowed (goal <=4)`;
    default:
      return `${n}/${d}`;
  }
}

function parseBattleOutput(text) {
  const games = [];
  const lines = text.split(/\r?\n/);
  let i = 0;

  while (i < lines.length) {
    const gameLine = lines[i];
    const gameMatch = gameLine.match(/^Game\s+(\d+)\s+\((.+)\)\s*$/);
    if (!gameMatch) {
      i++;
      continue;
    }
    const gameId = gameMatch[1];
    const gameLabel = gameMatch[2].trim();
    i++;
    // skip separator line
    if (lines[i] && lines[i].match(/^-+$/)) i++;
    const metrics = [];
    let makeupB3c = null;
    while (i < lines.length && lines[i].trim() !== "") {
      const line = lines[i];
      const makeupMatch = line.match(/^\s*Makeup B3c:\s*(.+)$/);
      if (makeupMatch) {
        makeupB3c = makeupMatch[1].trim();
        i++;
        continue;
      }
      const metricMatch = line.match(
        /^\s+(.+?):\s+(\d+\/\d+)\s+\(goal met:\s*(Y|N|✓|✗)\)\s*$/
      );
      if (metricMatch) {
        const key = metricMatch[1].trim();
        const display = metricMatch[2].trim();
        const met = metricMatch[3];
        const shortKey = key.split(/\s+/)[0];
        const numDen = display.match(/^(\d+)\/(\d+)$/);
        const num = numDen ? parseInt(numDen[1], 10) : null;
        const den = numDen ? parseInt(numDen[2], 10) : null;
        metrics.push({ key, shortKey, display, met, num, den });
      }
      i++;
    }
    games.push({ id: gameId, label: gameLabel, metrics, makeupB3c });
    while (i < lines.length && lines[i].trim() === "") i++;
  }

  return { games };
}

/** Parse PBP CSV and return { [gameId]: { date, score } } (date and final score per game; last row per game = final). */
function parsePbpCsvForDateScore(csvPath) {
  const text = fs.readFileSync(csvPath, "utf-8");
  const lines = text.split(/\r?\n/).filter((l) => l.trim());
  if (lines.length < 2) return {};
  const result = {};
  for (let i = 1; i < lines.length; i++) {
    const cols = parseCsvLine(lines[i]);
    if (cols.length < 7) continue;
    const gameId = cols[cols.length - 1].trim();
    const date = cols[0].trim();
    const score = (cols[6] || "").trim();
    if (gameId && date) {
      result[gameId] = { date, score: score || "—" };
    }
  }
  return result;
}

/** Parse score string (e.g. "6-3") and game label to get our runs, their runs, win, and "X-Y Win" or "X-Y Loss". */
function parseScoreAndResult(scoreStr, gameLabel) {
  if (!scoreStr || typeof scoreStr !== "string") return { displayText: scoreStr || "—", scoreOnly: scoreStr || "—", win: null };
  const parts = scoreStr.trim().split(/[-–—]/).map((p) => parseInt(p.trim(), 10));
  if (parts.length < 2 || isNaN(parts[0]) || isNaN(parts[1]))
    return { displayText: scoreStr, scoreOnly: scoreStr, win: null };
  const awayRuns = parts[0];
  const homeRuns = parts[1];
  const isUsdAway = gameLabel && String(gameLabel).toLowerCase().startsWith("san diego");
  const ourRuns = isUsdAway ? awayRuns : homeRuns;
  const theirRuns = isUsdAway ? homeRuns : awayRuns;
  const win = ourRuns > theirRuns;
  const scoreOnly = `${ourRuns}-${theirRuns}`;
  const displayText = `${scoreOnly} ${win ? "Win" : "Loss"}`;
  return { displayText, scoreOnly, win };
}

function formatTitleDate(mmDdYyyy) {
  if (!mmDdYyyy || !/^\d{1,2}\/\d{1,2}\/\d{4}$/.test(mmDdYyyy)) return mmDdYyyy || "";
  const [mm, dd, yyyy] = mmDdYyyy.split("/");
  const months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
  const m = parseInt(mm, 10);
  const d = parseInt(dd, 10);
  if (m < 1 || m > 12) return mmDdYyyy;
  return `${months[m - 1]} ${d}, ${yyyy}`;
}

function parseCsvLine(line) {
  const cols = [];
  let i = 0;
  while (i < line.length) {
    if (line[i] === '"') {
      let j = i + 1;
      while (j < line.length) {
        if (line[j] === '"' && line[j + 1] !== '"') break;
        if (line[j] === '"') j++;
        j++;
      }
      cols.push(line.slice(i + 1, j).replace(/""/g, '"'));
      i = j + 1;
      if (line[i] === ",") i++;
    } else {
      const j = line.indexOf(",", i);
      if (j < 0) {
        cols.push(line.slice(i));
        break;
      }
      cols.push(line.slice(i, j));
      i = j + 1;
    }
  }
  return cols;
}

const styles = StyleSheet.create({
  page: {
    padding: 24,
    fontSize: 9,
    fontFamily: "Helvetica",
  },
  title: {
    fontSize: 14,
    fontFamily: "Helvetica-Bold",
  },
  headerRowWithLogo: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    width: "100%",
    marginBottom: 8,
  },
  logo: {
    width: 44,
    height: 44,
    flexShrink: 0,
    objectFit: "contain",
  },
  logoWrap: {
    flexShrink: 0,
    alignItems: "flex-end",
  },
  table: {
    width: "100%",
  },
  headerRow: {
    flexDirection: "row",
    borderBottomWidth: 1.5,
    borderBottomColor: "#333",
    paddingVertical: 6,
    paddingHorizontal: 4,
    backgroundColor: "#f5f5f5",
  },
  dataRow: {
    flexDirection: "row",
    borderBottomWidth: 0.5,
    borderBottomColor: "#ccc",
    paddingVertical: 5,
    paddingHorizontal: 4,
  },
  summaryRow: {
    flexDirection: "row",
    borderBottomWidth: 1,
    borderBottomColor: "#333",
    paddingVertical: 5,
    paddingHorizontal: 4,
    backgroundColor: "#f0f0f0",
    fontFamily: "Helvetica-Bold",
  },
  headerCell: {
    fontFamily: "Helvetica-Bold",
    flexGrow: 0,
    flexShrink: 0,
  },
  gameCol: { width: "18%", minWidth: 90 },
  dateCol: { width: "10%", minWidth: 56 },
  scoreCol: { width: "8%", minWidth: 44 },
  scoreWin: {
    backgroundColor: "#a5d6a7",
    color: "#1b5e20",
  },
  scoreLoss: {
    backgroundColor: "#ffcdd2",
    color: "#b71c1c",
  },
  battleCol: { width: "6.4%", minWidth: 38 },
  cell: {
    flexGrow: 0,
    flexShrink: 0,
    paddingHorizontal: 2,
    textAlign: "center",
  },
  /** Well over (goal met, not small sample) */
  cellSuccess: {
    backgroundColor: "#a5d6a7",
    color: "#1b5e20",
  },
  /** Small success (goal met, small sample) */
  cellSuccessLight: {
    backgroundColor: "#e8f5e9",
    color: "#2e7d32",
  },
  /** Zero or <50% of success (goal not met) */
  cellFail: {
    backgroundColor: "#ffcdd2",
    color: "#b71c1c",
  },
  /** More than 50% but less than success (goal not met) */
  cellFailLiteRed: {
    backgroundColor: "#ef9e9e",
    color: "#bf360c",
  },
  /** Small sample (den <= 3) — amber regardless of Y/N */
  cellAmber: {
    backgroundColor: "#ffcc80",
    color: "#e65100",
  },
  /** Per-game: background only (text forced black) */
  cellSuccessBg: { backgroundColor: "#a5d6a7" },
  cellSuccessLightBg: { backgroundColor: "#e8f5e9" },
  cellFailBg: { backgroundColor: "#ffcdd2" },
  cellFailLiteRedBg: { backgroundColor: "#ef9e9e" },
  cellAmberBg: { backgroundColor: "#ffcc80" },
  colorKey: {
    flexDirection: "column",
    marginLeft: 16,
    marginBottom: 0,
  },
  colorKeyHorizontal: {
    flexDirection: "row",
    flexWrap: "wrap",
    alignItems: "center",
    marginBottom: 6,
  },
  colorKeyItem: {
    flexDirection: "row",
    alignItems: "center",
    marginBottom: 2,
  },
  colorKeyItemInline: {
    flexDirection: "row",
    alignItems: "center",
    marginRight: 10,
  },
  colorKeySwatch: {
    width: 10,
    height: 10,
    marginRight: 6,
    borderWidth: 0.5,
    borderColor: "#999",
  },
  colorKeyLabel: {
    fontSize: 9,
    fontFamily: "Helvetica",
  },
  titleWithLegend: {
    flexDirection: "row",
    alignItems: "center",
    flex: 1,
  },
  // Per-game report
  gamePage: {
    padding: 28,
    fontSize: 11,
    fontFamily: "Helvetica",
  },
  gameHeader: {
    marginBottom: 16,
    paddingBottom: 10,
    borderBottomWidth: 1.5,
    borderBottomColor: "#333",
  },
  gameTitle: {
    fontSize: 16,
    fontFamily: "Helvetica-Bold",
  },
  gameDateScore: {
    fontSize: 11,
    marginTop: 6,
    color: "#444",
  },
  gameScore: {
    fontSize: 22,
    fontFamily: "Helvetica-Bold",
    marginTop: 10,
    paddingVertical: 4,
    paddingHorizontal: 6,
    color: "#111",
  },
  battleRow: {
    flexDirection: "row",
    alignItems: "stretch",
    marginBottom: 10,
    paddingBottom: 8,
    borderBottomWidth: 0.5,
    borderBottomColor: "#eee",
  },
  battleLabel: {
    width: "28%",
    minWidth: 120,
    fontFamily: "Helvetica-Bold",
    fontSize: 11,
    lineHeight: 1.4,
    paddingRight: 8,
  },
  battleValue: {
    width: "10%",
    minWidth: 44,
    fontSize: 11,
    lineHeight: 1.4,
    paddingVertical: 4,
    paddingHorizontal: 4,
  },
  battleMet: {
    width: "8%",
    minWidth: 28,
    fontSize: 11,
    fontFamily: "Helvetica-Bold",
    lineHeight: 1.4,
    paddingVertical: 4,
    paddingHorizontal: 4,
  },
  battleSummary: {
    flex: 1,
    minWidth: 140,
    fontSize: 10,
    lineHeight: 1.4,
    paddingVertical: 4,
    paddingHorizontal: 4,
  },
  battleCellText: {
    lineHeight: 1.4,
    color: "#000",
  },
  battleMetSymbolMet: {
    fontFamily: "Helvetica-Bold",
    fontSize: 12,
    color: "#000",
  },
  battleMetSymbolFail: {
    fontFamily: "Helvetica-Bold",
    fontSize: 12,
    color: "#000",
  },
  makeupBlock: {
    marginTop: 4,
    marginBottom: 10,
    paddingVertical: 6,
    paddingHorizontal: 8,
    backgroundColor: "#f8f8f8",
    borderLeftWidth: 3,
    borderLeftColor: "#888",
    fontSize: 8,
    color: "#444",
  },
});

/** Parse date string (MM/DD/YYYY or YYYY-MM-DD) to Date for sorting; invalid/missing => epoch. */
function parseDateForSort(dateStr) {
  if (!dateStr || typeof dateStr !== "string") return new Date(0);
  const trimmed = dateStr.trim();
  const mdy = trimmed.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  if (mdy) {
    const [, mm, dd, yyyy] = mdy;
    return new Date(parseInt(yyyy, 10), parseInt(mm, 10) - 1, parseInt(dd, 10));
  }
  const iso = trimmed.match(/^(\d{4})-(\d{1,2})-(\d{1,2})/);
  if (iso) return new Date(trimmed);
  return new Date(0);
}

function BattleTableDocument({ data }) {
  const gameDateScore = data.gameDateScore || {};
  const games = (data.games || [])
    .filter((g) => !EXCLUDED_GAME_IDS.includes(g.id))
    .sort((a, b) => {
      const da = parseDateForSort(gameDateScore[a.id]?.date);
      const db = parseDateForSort(gameDateScore[b.id]?.date);
      if (da.getTime() !== db.getTime()) return da.getTime() - db.getTime();
      return String(a.id).localeCompare(String(b.id));
    });
  if (!games.length) {
    return React.createElement(
      Document,
      {},
      React.createElement(
        Page,
        { size: "A4", style: styles.page },
        React.createElement(Text, { style: styles.title }, "No game data")
      )
    );
  }

  const metricKeys = BATTLE_ORDER.filter((k) =>
    games[0].metrics.some((m) => m.shortKey === k)
  );

  const dates = games
    .map((g) => gameDateScore[g.id]?.date)
    .filter(Boolean);
  const maxDateStr =
    dates.length > 0
      ? dates.sort((a, b) => new Date(b) - new Date(a))[0]
      : "";
  const titleDate = formatTitleDate(maxDateStr);
  const reportTitle = titleDate
    ? `USD Baseball — Battle reports as of ${titleDate}`
    : "USD Baseball — Battle reports";

  const logoPath = data.logoPath || null;
  const logoSrc = loadLogoDataUrl(logoPath);
  const hasLogo = !!logoSrc;
  const colorKeyItems = [
    { style: styles.cellSuccess, label: "✓ — goal met" },
    { style: styles.cellSuccessLight, label: "✓ — goal met (small sample)" },
    { style: styles.cellAmber, label: "✗ — small sample" },
    { style: styles.cellFail, label: "✗ — below goal, closer" },
    { style: styles.cellFailLiteRed, label: "✗ — below goal" },
  ];
  const colorKey = React.createElement(
    View,
    { style: styles.colorKey },
    ...colorKeyItems.map((item, idx) =>
      React.createElement(
        View,
        { key: idx, style: styles.colorKeyItem },
        React.createElement(View, {
          style: [styles.colorKeySwatch, item.style],
        }),
        React.createElement(Text, { style: styles.colorKeyLabel }, item.label)
      )
    )
  );
  const logoEl = hasLogo
    ? React.createElement(Image, {
        src: logoSrc,
        style: styles.logo,
      })
    : React.createElement(View, { style: { width: 44, height: 44 } });
  const titleBlock = React.createElement(
    View,
    { style: styles.headerRowWithLogo },
    React.createElement(
      View,
      { style: styles.titleWithLegend },
      React.createElement(Text, { style: styles.title }, reportTitle),
      colorKey
    ),
    React.createElement(View, { style: styles.logoWrap }, logoEl)
  );

  const headerCells = [
    React.createElement(
      View,
      { key: "game", style: [styles.headerCell, styles.gameCol] },
      React.createElement(Text, {}, "Game")
    ),
    React.createElement(
      View,
      { key: "date", style: [styles.headerCell, styles.dateCol] },
      React.createElement(Text, {}, "Date")
    ),
    React.createElement(
      View,
      { key: "score", style: [styles.headerCell, styles.scoreCol] },
      React.createElement(Text, {}, "Score")
    ),
    ...metricKeys.map((k) =>
      React.createElement(
        View,
        { key: k, style: [styles.headerCell, styles.battleCol] },
        React.createElement(Text, {}, BATTLE_LABELS[k] || k)
      )
    ),
  ];

  const dataRows = games.map((game) => {
    const gameCell = React.createElement(
      View,
      { key: "game", style: [styles.cell, styles.gameCol] },
      React.createElement(Text, { numberOfLines: 3 }, game.label)
    );
    const info = gameDateScore[game.id] || {};
    const dateCell = React.createElement(
      View,
      { key: "date", style: [styles.cell, styles.dateCol] },
      React.createElement(Text, {}, info.date || "—")
    );
    const scoreResult = parseScoreAndResult(info.score, game.label);
    const scoreStyle =
      scoreResult.win === true
        ? [styles.cell, styles.scoreCol, styles.scoreWin]
        : scoreResult.win === false
          ? [styles.cell, styles.scoreCol, styles.scoreLoss]
          : [styles.cell, styles.scoreCol];
    const scoreCell = React.createElement(
      View,
      { key: "score", style: scoreStyle },
      React.createElement(Text, { style: { fontFamily: "Helvetica-Bold" } }, scoreResult.displayText)
    );
    const battleCells = metricKeys.map((shortKey) => {
      const m = game.metrics.find((x) => x.shortKey === shortKey);
      if (!m)
        return React.createElement(View, {
          key: shortKey,
          style: [styles.cell, styles.battleCol],
        });
      const isSmall =
        RATE_METRIC_KEYS.includes(shortKey) &&
        m.den != null &&
        m.den <= SMALL_SAMPLE_THRESHOLD;
      const met = m.met === "Y" || m.met === "✓";
      const rate =
        m.den != null && m.den > 0 && m.num != null
          ? m.num / m.den
          : 0;
      let levelStyle = styles.cell;
      if (isSmall) {
        levelStyle = met ? styles.cellSuccessLight : styles.cellAmber;
      } else if (met) {
        levelStyle = styles.cellSuccess;
      } else {
        if (m.num === 0 || rate < 0.5) levelStyle = styles.cellFailLiteRed;
        else levelStyle = styles.cellFail;
      }
      const metSymbol = met ? "✓" : "✗";
      const cellStyle = [styles.cell, styles.battleCol, levelStyle];
      return React.createElement(
        View,
        { key: shortKey, style: cellStyle },
        React.createElement(Text, {}, m.display),
        React.createElement(Text, { style: { fontSize: 7, marginTop: 1 } }, metSymbol)
      );
    });
    return React.createElement(
      View,
      { key: game.id, style: styles.dataRow, wrap: false },
      gameCell,
      dateCell,
      scoreCell,
      ...battleCells
    );
  });

  const n = games.length;
  const avgCells = metricKeys.map((shortKey) => {
    const list = games
      .map((g) => g.metrics.find((m) => m.shortKey === shortKey))
      .filter((m) => m != null && m.num != null);
    if (list.length === 0)
      return React.createElement(View, {
        key: shortKey,
        style: [styles.cell, styles.battleCol],
      });
    const goal = AVG_GOALS[shortKey];
    let text;
    let met = false;
    let isSmall = false;
    let rate = 0;
    if (RATE_METRIC_KEYS.includes(shortKey)) {
      const withDen = list.filter((m) => m.den != null && m.den > 0);
      const totalDen = withDen.reduce((a, m) => a + m.den, 0);
      isSmall = totalDen <= SMALL_SAMPLE_THRESHOLD;
      const pcts = withDen.map((m) => (m.num / m.den) * 100);
      const avgPct =
        pcts.length > 0
          ? pcts.reduce((a, b) => a + b, 0) / pcts.length
          : null;
      text = avgPct != null ? `${avgPct.toFixed(1)}%` : "—";
      if (avgPct != null && goal && typeof goal.pctMin === "number") {
        met = avgPct >= goal.pctMin;
        rate = goal.pctMin ? avgPct / goal.pctMin : 0;
      }
    } else {
      const nums = list.map((m) => m.num);
      const avg = nums.reduce((a, b) => a + b, 0) / nums.length;
      text = avg % 1 === 0 ? String(Math.round(avg)) : avg.toFixed(1);
      if (goal === "more") {
        const sumNum = list.reduce((a, m) => a + m.num, 0);
        const sumDen = list.reduce((a, m) => a + (m.den ?? 0), 0);
        met = sumNum > sumDen;
        rate = sumDen > 0 ? sumNum / sumDen : 0;
      } else if (goal && typeof goal.min === "number") {
        met = avg >= goal.min;
        rate = goal.min ? avg / goal.min : 0;
      } else if (goal && typeof goal.max === "number") {
        met = avg <= goal.max;
        rate = avg > 0 ? goal.max / avg : 1;
      }
    }
    let levelStyle = styles.cell;
    if (isSmall) {
      levelStyle = met ? styles.cellSuccessLight : styles.cellAmber;
    } else if (met) {
      levelStyle = styles.cellSuccess;
    } else {
      levelStyle =
        rate < 0.5 ? styles.cellFailLiteRed : styles.cellFail;
    }
    return React.createElement(
      View,
      { key: shortKey, style: [styles.cell, styles.battleCol, levelStyle] },
      React.createElement(Text, { style: { fontFamily: "Helvetica-Bold" } }, text)
    );
  });
  const successCells = metricKeys.map((shortKey) => {
    const list = games
      .map((g) => g.metrics.find((m) => m.shortKey === shortKey))
      .filter((m) => m != null);
    const metCount = list.filter((m) => m.met === "Y" || m.met === "✓").length;
    const pct = list.length > 0 ? (metCount / list.length) * 100 : 0;
    const text = list.length > 0 ? `${pct.toFixed(0)}%` : "—";
    const met = pct >= SUCCESS_PCT_GOAL;
    let levelStyle = styles.cell;
    if (met) {
      levelStyle = pct >= 100 ? styles.cellSuccess : styles.cellSuccessLight;
    } else {
      levelStyle =
        pct >= 50 ? styles.cellFail : styles.cellFailLiteRed;
    }
    return React.createElement(
      View,
      { key: shortKey, style: [styles.cell, styles.battleCol, levelStyle] },
      React.createElement(Text, { style: { fontFamily: "Helvetica-Bold" } }, text)
    );
  });

  const averageRow = React.createElement(
    View,
    { key: "avg", style: [styles.dataRow, styles.summaryRow], wrap: false },
    React.createElement(
      View,
      { style: [styles.cell, styles.gameCol] },
      React.createElement(Text, { style: { fontFamily: "Helvetica-Bold" } }, "Avg")
    ),
    React.createElement(View, { style: [styles.cell, styles.dateCol] }, React.createElement(Text, {}, "—")),
    React.createElement(View, { style: [styles.cell, styles.scoreCol] }, React.createElement(Text, {}, "—")),
    ...avgCells
  );
  const successRateRow = React.createElement(
    View,
    { key: "success", style: [styles.dataRow, styles.summaryRow], wrap: false },
    React.createElement(
      View,
      { style: [styles.cell, styles.gameCol] },
      React.createElement(Text, { style: { fontFamily: "Helvetica-Bold" } }, "Success")
    ),
    React.createElement(View, { style: [styles.cell, styles.dateCol] }, React.createElement(Text, {}, "—")),
    React.createElement(View, { style: [styles.cell, styles.scoreCol] }, React.createElement(Text, {}, "—")),
    ...successCells
  );

  return React.createElement(
    Document,
    {},
    React.createElement(
      Page,
      { size: "A4", orientation: "landscape", style: styles.page },
      titleBlock,
      React.createElement(
        View,
        { style: styles.table },
        React.createElement(View, {
          style: [styles.headerRow, styles.dataRow],
          wrap: false,
        }, ...headerCells),
        ...dataRows,
        averageRow,
        successRateRow
      )
    )
  );
}

/** From game label "A @ B", return the opponent (the part that isn't San Diego). */
function opponentFromLabel(label) {
  if (!label || typeof label !== "string") return "";
  const parts = label.split(" @ ");
  if (parts.length !== 2) return "";
  const lower = label.toLowerCase();
  return lower.startsWith("san diego") ? (parts[1] || "").trim() : (parts[0] || "").trim();
}

/** Short name for title: "Charlotte", "OSU", "GU" (Gonzaga), else first letter of each word (e.g. LBSB). */
function opponentTitleName(opponentName) {
  if (!opponentName) return "";
  const lower = opponentName.toLowerCase();
  if (lower.includes("charlotte")) return "Charlotte";
  if (lower.includes("oregon st") || lower.includes("oregon state")) return "OSU";
  if (lower.includes("gonzaga")) return "GU";
  if (lower.includes("santa clara")) return "SC";
  if (lower.includes("irvine")) return "UCI";
  if (lower.includes("san francisco")) return "USF";
  if (lower.includes("seattle")) return "SU";
  if (lower.includes("fullerton") || lower.includes("cal st. fullerton") || lower.includes("cal state fullerton"))
    return "CSF";
  if (lower.includes("lmu") || lower.includes("loyola marymount")) return "LMU";
  return opponentName
    .split(/\s+/)
    .map((w) => (w.replace(/[^a-zA-Z0-9]/g, "").charAt(0) || ""))
    .filter(Boolean)
    .join("")
    .toUpperCase();
}

/** Single-game PDF: one file with one page for the given game (battles and numbers that contributed). */
function PerGameSingleDocument({ data, game }) {
  const gameDateScore = data.gameDateScore || {};
  const info = gameDateScore[game.id] || {};
  const reportTitle = `${game.label} Battle Report`;

  const logoPath = data.logoPath || null;
  const logoSrc = loadLogoDataUrl(logoPath);
  const hasLogo = !!logoSrc;
  const logoEl = hasLogo
    ? React.createElement(Image, {
        src: logoSrc,
        style: styles.logo,
      })
    : React.createElement(View, { style: { width: 44, height: 44 } });
  const titleBlock = React.createElement(
    View,
    { style: styles.headerRowWithLogo },
    React.createElement(Text, { style: styles.title }, reportTitle),
    React.createElement(View, { style: styles.logoWrap }, logoEl)
  );

  const perGameColorKeyItems = [
    { style: styles.cellSuccessBg, label: "Y — goal met" },
    { style: styles.cellSuccessLightBg, label: "Y — goal met (small sample)" },
    { style: styles.cellAmberBg, label: "N — small sample" },
    { style: styles.cellFailBg, label: "N — below goal, closer" },
    { style: styles.cellFailLiteRedBg, label: "N — below goal" },
  ];
  const perGameColorKey = React.createElement(
    View,
    { style: styles.colorKeyHorizontal },
    ...perGameColorKeyItems.map((item, idx) =>
      React.createElement(
        View,
        { key: idx, style: styles.colorKeyItemInline },
        React.createElement(View, {
          style: [styles.colorKeySwatch, item.style],
        }),
        React.createElement(Text, { style: styles.colorKeyLabel }, item.label)
      )
    )
  );

  const scoreResult = parseScoreAndResult(info.score, game.label);
  const gameScoreStyle =
    scoreResult.win === true
      ? [styles.gameScore, styles.scoreWin]
      : scoreResult.win === false
        ? [styles.gameScore, styles.scoreLoss]
        : styles.gameScore;
  const header = React.createElement(
    View,
    { key: "header", style: styles.gameHeader },
    React.createElement(Text, { style: styles.gameDateScore }, info.date || "—"),
    React.createElement(Text, { style: gameScoreStyle }, scoreResult.displayText)
  );
  const metricOrder = BATTLE_ORDER.filter((k) =>
    game.metrics.some((m) => m.shortKey === k)
  );
  const battleRows = metricOrder.map((shortKey) => {
    const m = game.metrics.find((x) => x.shortKey === shortKey);
    if (!m) return null;
    const isSmall =
      RATE_METRIC_KEYS.includes(shortKey) &&
      m.den != null &&
      m.den <= SMALL_SAMPLE_THRESHOLD;
    const met = m.met === "Y" || m.met === "✓";
    const rate =
      m.den != null && m.den > 0 && m.num != null ? m.num / m.den : 0;
    let levelStyle = null;
    if (isSmall) {
      levelStyle = met ? styles.cellSuccessLightBg : styles.cellAmberBg;
    } else if (met) {
      levelStyle = styles.cellSuccessBg;
    } else {
      levelStyle =
        m.num === 0 || rate < 0.5 ? styles.cellFailLiteRedBg : styles.cellFailBg;
    }
    const summary = battleSummaryLine(m.shortKey, m.num, m.den);
    return React.createElement(
      View,
      { key: shortKey, style: styles.battleRow },
      React.createElement(
        View,
        { style: styles.battleLabel },
        React.createElement(Text, { style: styles.battleCellText }, m.key)
      ),
      React.createElement(
        View,
        { style: [styles.battleValue, levelStyle] },
        React.createElement(Text, { style: styles.battleCellText }, m.display)
      ),
      React.createElement(
        View,
        { style: [styles.battleMet, levelStyle] },
        React.createElement(Text, {
          style: met ? styles.battleMetSymbolMet : styles.battleMetSymbolFail,
        }, metSymbol(met))
      ),
      React.createElement(
        View,
        { style: [styles.battleSummary, levelStyle] },
        React.createElement(Text, { style: styles.battleCellText }, summary)
      )
    );
  }).filter(Boolean);

  const makeupEl =
    game.makeupB3c != null && game.makeupB3c !== ""
      ? React.createElement(
          View,
          { key: "makeup", style: styles.makeupBlock },
          React.createElement(Text, {}, `B3c makeup: ${game.makeupB3c}`)
        )
      : null;

  return React.createElement(
    Document,
    {},
    React.createElement(
      Page,
      { size: "A4", style: styles.gamePage },
      titleBlock,
      perGameColorKey,
      header,
      ...battleRows,
      ...(makeupEl ? [makeupEl] : [])
    )
  );
}

async function main() {
  const inputPath =
    process.argv[2] ||
    path.join(__dirname, "..", "real5_battle_calc_output.txt");
  const outputPath =
    process.argv[3] || path.join(__dirname, "season_battle_report.pdf");
  const pbpCsvPath =
    process.argv[4] || path.join(__dirname, "..", "real5_pbp_baseballr_style.csv");
  const logoPath = path.resolve(
    process.argv[5] || path.join(__dirname, "sd_logo.png")
  );
  // Optional: only generate per-game PDFs for these IDs (argv[6], argv[7], ...). If none, generate all.
  const onlyGameIds = new Set(
    process.argv.slice(6).filter((a) => /^\d+$/.test(String(a))).map(Number)
  );

  const text = fs.readFileSync(inputPath, "utf-8");
  const data = parseBattleOutput(text);
  let gameDateScore = {};
  try {
    if (fs.existsSync(pbpCsvPath)) {
      gameDateScore = parsePbpCsvForDateScore(pbpCsvPath);
    }
  } catch (e) {
    console.warn("Could not load PBP CSV for date/score:", e.message);
  }
  data.gameDateScore = gameDateScore;
  data.logoPath = logoPath;

  const doc = React.createElement(BattleTableDocument, { data });
  await renderToFile(doc, outputPath);
  console.log(`Wrote ${outputPath}`);

  const outDir = path.dirname(outputPath);
  let games = (data.games || []).filter(
    (g) => !EXCLUDED_GAME_IDS.includes(g.id)
  );
  if (onlyGameIds.size > 0) {
    games = games.filter((g) => onlyGameIds.has(Number(g.id)));
  }
  for (const game of games) {
    const info = gameDateScore[game.id] || {};
    const dateStr = (info.date || "").trim().replace(/\//g, "-") || game.id;
    const opponent = opponentFromLabel(game.label);
    const opponentName = opponentTitleName(opponent);
    const safeName = [dateStr, opponentName, game.id].filter(Boolean).join("_");
    const perGamePath = path.join(outDir, `${safeName}_Battle_report.pdf`);
    const perGameDoc = React.createElement(PerGameSingleDocument, {
      data,
      game,
    });
    await renderToFile(perGameDoc, perGamePath);
    console.log(`Wrote ${perGamePath}`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
