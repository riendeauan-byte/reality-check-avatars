// Generates the 5-character avatar sprite set into app/avatars/.
// 4 frames per character: closed / half / open (yell) / blink — the overlay
// swaps these by speech energy for lip sync. Re-run after editing any config:
//   cd prep/avatar-gen && npm install && node generate.mjs
import { createAvatar } from "@dicebear/core";
import * as col from "@dicebear/collection";
import { writeFileSync, mkdirSync } from "fs";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

const OUT = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "app", "avatars");
mkdirSync(OUT, { recursive: true });

// Frame = mouth + eyes state; shared across every character.
const FRAMES = {
  closed: { mouth: ["serious"], eyes: ["default"] },
  half: { mouth: ["disbelief"], eyes: ["default"] },
  open: { mouth: ["screamOpen"], eyes: ["squint"] },
  blink: { mouth: ["serious"], eyes: ["closed"] },
};

// The roster. Style: avataaars (https://avataaars.com, free for personal and
// commercial use) via DiceBear (MIT). Tweak any character here and re-run.
const CHARS = {
  iron: {
    seed: "iron1", skinColor: ["614335"], topProbability: 0, facialHairProbability: 0,
    eyebrows: ["angryNatural"], clothing: ["shirtCrewNeck"], clothesColor: ["262e33"],
    accessoriesProbability: 0,
  },
  hustle: {
    seed: "hus1", skinColor: ["d08b5b"], top: ["shortFlat"], hairColor: ["2c1b18"],
    facialHair: ["beardMajestic"], facialHairProbability: 100, facialHairColor: ["2c1b18"],
    eyebrows: ["defaultNatural"], clothing: ["shirtScoopNeck"], clothesColor: ["e6e6e6"],
    accessoriesProbability: 0,
  },
  disciple: {
    seed: "dis1", skinColor: ["ffdbb4"], top: ["theCaesar"], hairColor: ["2c1b18"],
    facialHair: ["beardMedium"], facialHairProbability: 100, facialHairColor: ["4a312c"],
    eyebrows: ["angryNatural"], clothing: ["shirtCrewNeck"], clothesColor: ["3c4f5c"],
    accessoriesProbability: 0,
  },
  topg: {
    seed: "top1", skinColor: ["edb98a"], topProbability: 0, facialHair: ["beardMedium"],
    facialHairProbability: 100, facialHairColor: ["2c1b18"], eyebrows: ["defaultNatural"],
    accessories: ["sunglasses"], accessoriesProbability: 100, accessoriesColor: ["262e33"],
    clothing: ["blazerAndShirt"], clothesColor: ["262e33"],
  },
  coach: {
    seed: "drill7", top: ["shortFlat"], facialHair: ["beardMedium"],
    facialHairProbability: 100, eyebrows: ["angryNatural"], accessoriesProbability: 0,
  },
};

let n = 0;
for (const [name, cfg] of Object.entries(CHARS)) {
  for (const [frame, state] of Object.entries(FRAMES)) {
    const svg = createAvatar(col.avataaars, { size: 300, ...cfg, ...state }).toString();
    writeFileSync(join(OUT, `${name}-${frame}.svg`), svg);
    n++;
  }
}
console.log(`wrote ${n} sprites to ${OUT}`);
