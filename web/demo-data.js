// Données fictives pour le mode démo (quand config.js est vide ou avec ?demo dans l'URL).
window.GS_DEMO = function () {
  const realm = "Skyfall";
  const key = "Les Éternels-" + realm;
  const now = Date.now();
  const iso = (msAgo) => new Date(now - msAgo).toISOString();
  const H = 3600e3, D = 86400e3;

  const ranks = ["Maître de guilde", "Officier", "Vétéran", "Membre", "Recrue"];
  const people = [
    ["Aelwyn", "PRIEST", "NightElf", 60, 0, true, [["Herboristerie", 300], ["Alchimie", 300]], 64.2, "Sacré"],
    ["Brakk", "WARRIOR", "Orc", 60, 1, true, [["Minage", 300], ["Forge", 295]], 66.8, "Protection"],
    ["Cendrelune", "MAGE", "Human", 60, 1, false, [["Couture", 300], ["Enchantement", 285]], 63.5, "Givre"],
    ["Durgan", "PALADIN", "Dwarf", 58, 2, false, [["Minage", 260], ["Ingénierie", 250]], null, null],
    ["Elyndra", "DRUID", "NightElf", 60, 2, true, [["Dépeçage", 300], ["Travail du cuir", 300]], 62.1, "Restauration"],
    ["Fizzlebang", "WARLOCK", "Gnome", 60, 3, false, [["Couture", 280], ["Enchantement", 300]], 61.0, "Affliction"],
    ["Grizzh", "HUNTER", "Troll", 55, 3, false, [["Dépeçage", 240], ["Travail du cuir", 230]], null, null],
    ["Hélia", "SHAMAN", "Tauren", 60, 3, true, [["Herboristerie", 300], ["Alchimie", 290]], 60.4, "Amélioration"],
    ["Ishka", "ROGUE", "Scourge", 47, 4, false, [], null, null],
    ["Jorund", "WARRIOR", "Dwarf", 60, 3, false, [["Minage", 300], ["Forge", 300]], 59.7, "Armes"],
    ["Kaelith", "MAGE", "Gnome", 34, 4, false, [["Couture", 150]], null, null],
    ["Lunara", "PRIEST", "Human", 60, 3, false, [["Couture", 300], ["Enchantement", 300]], 62.9, "Ombre"],
    ["Morthak", "WARLOCK", "Orc", 60, 4, false, [], null, null],
    ["Nyssa", "HUNTER", "NightElf", 60, 3, false, [["Ingénierie", 300], ["Minage", 270]], 61.8, "Précision"],
    ["Orvald", "PALADIN", "Human", 22, 4, false, [], null, null],
  ];
  const lastSeen = [0, 0, 2 * H, 5 * D, 0, 18 * H, 21 * D, 0, 40 * D, 3 * D, 75 * D, 1 * D, 16 * D, 9 * H, 120 * D];
  const zones = ["Orgrimmar", "Hurlevent", "Berceau-de-l'Hiver", "Maraudon", "Hautes-terres d'Arathi", "Strangleronce"];

  const members = people.map(([n, cls, race, lvl, rank, addon, profs, il, spec], i) => {
    const online = lastSeen[i] === 0;
    return {
      guild_key: key, name: `${n}-${realm}`, rank: ranks[rank], rank_index: rank, level: lvl, class: cls,
      zone: zones[i % zones.length], online, last_online: iso(lastSeen[i]), in_guild: true,
      achievement_points: 100 + i * 37,
      public_note: i === 1 ? "Tank principal" : i === 0 ? "Heal raid" : i === 8 ? "Reroll de Brakk" : "",
      guild_professions: addon ? {} : Object.fromEntries(profs.map(([p, s], j) => [String(j), { name: p, skill: s }])),
      profile: addon ? {
        level: lvl, race, class: cls, faction: "Horde", ilvl: il, spec,
        professions: profs.map(([p, s]) => ({ name: p, skill: s, max: 300 })),
        gear: [16900, 18404, 16902, 0, 16897, 16903, 16901, 16898, 16904, 16899, 19140, 18821, 18820, 19395, 17102, 17103, 18523, 0, 0],
      } : null,
      profile_at: addon ? iso(2 * H) : null,
    };
  });
  // Deux fiches au format complet (add-on 0.2+), pour montrer toutes les sections.
  const sec = (s) => Math.floor(now / 1000) - s;
  const reset = sec(-3 * 86400);
  const full = (m, extra) => {
    const p = m.profile;
    m.profile = {
      v: 2, name: m.name, addonVersion: "0.2.0",
      core: { at: sec(7200), level: p.level, race: p.race, class: p.class, faction: p.faction, ilvl: p.ilvl, spec: null,
        xp: 0, xpMax: 0, bind: "Orgrimmar", title: extra.title },
      professions: { at: sec(7200), list: p.professions },
      gear: { at: sec(7200), items: extra.gear },
      talents: { at: sec(86400), tabs: extra.talents, unspent: 0 },
      recipes: { at: sec(3600), profs: extra.recipes },
      stats: { at: sec(7200), ...extra.stats },
      lockouts: { at: sec(7200), list: extra.lockouts },
      reputations: { at: sec(7200), list: [
        { n: "Orgrimmar", s: 8, v: 42999, min: 42000, max: 42999, cat: "Horde" },
        { n: "Aube d'argent", s: 7, v: 30200, min: 21000, max: 42000, cat: "Autres" },
        { n: "Cercle cénarien", s: 6, v: 13100, min: 9000, max: 21000, cat: "Autres" },
      ] },
      pvp: { at: sec(7200), hk: 1840, rank: 7, rankName: "Garde de pierre", weekHK: 120, weekHonor: 5400 },
      inventory: { at: sec(600), slots: 96, free: 21, items: [
        { i: 13444, n: "Potion de mana excellente", c: 12, q: 1 }, { i: 13446, n: "Potion de soins majeure", c: 8, q: 1 },
        { i: 12360, n: "Barre d'arcanite", c: 3, q: 2 }, { i: 7076, n: "Essence de terre", c: 6, q: 2 },
      ] },
    };
  };
  full(members[0], {
    title: "Défenseur",
    gear: [
      { slot: 1, id: 16921, n: "Auréole de transcendance", q: 4, l: 76, e: 2588, tt: [
        { t: "Lié quand ramassé" }, { t: "Tête", r: "Tissu" }, { t: "102 Armure" },
        { t: "+17 Endurance" }, { t: "+27 Intelligence" }, { t: "+22 Esprit" }, { t: "+10 Résistance à l'Ombre" },
        { t: "+8 Intelligence (enchantement)", c: "1eff00" },
        { t: "Équipé : Augmente les soins prodigués de 48 au maximum.", c: "1eff00" },
        { t: "Vêtements de transcendance (2/8)", c: "ffd100" },
        { t: "(3) Ensemble : Augmente vos chances de toucher avec vos sorts de 1 %.", c: "808080" },
      ] }, { slot: 3, id: 16924, n: "Spallières de transcendance", q: 4, l: 76 },
      { slot: 5, id: 16923, n: "Robe de transcendance", q: 4, l: 76, e: 1891 }, { slot: 16, id: 17103, n: "Lame d'Azuregos", q: 4, l: 70, dur: 22 },
      { slot: 13, id: 19395, n: "Ecaille-de-rêve", q: 4, l: 77 },
    ],
    talents: [{ n: "Discipline", p: 21, list: [{ n: "Inspiration intérieure", r: 5, m: 5 }] }, { n: "Sacré", p: 30, list: [{ n: "Esprit de rédemption", r: 1, m: 1 }] }, { n: "Ombre", p: 0, list: [] }],
    recipes: {
      Alchimie: { at: sec(3600), skill: 300, max: 300, list: [
        { n: "Flacon des Titans", i: 13510, cd: null }, { n: "Flacon de sagesse distillée", i: 13511 },
        { n: "Transmutation : arcanite", i: 12360, cd: sec(-20 * 3600) }, { n: "Potion de mana excellente", i: 13444 },
      ] },
    },
    stats: { hp: 4210, power: 6800, int: 290, spi: 260, sta: 210, str: 40, agi: 50, armor: 1900, healing: 820, spellCrit: 6.2, mp5: 48, mp5Casting: 22,
      resist: { fire: 10, nature: 0, frost: 15, shadow: 30, arcane: 0 } },
    lockouts: [{ n: "Cœur du Magma", raid: true, size: 40, reset, done: 8, total: 10 }, { n: "Repaire d'Onyxia", raid: true, size: 40, reset: sec(-86400), done: 1, total: 1 }],
  });
  full(members[1], {
    title: null,
    gear: [{ slot: 1, id: 16963, n: "Heaume de colère", q: 4, l: 76 }, { slot: 16, id: 19019, n: "Thunderfury, lame bénie du Cherchevent", q: 5, l: 80, e: 1900 }],
    talents: [{ n: "Armes", p: 5, list: [] }, { n: "Fureur", p: 5, list: [] }, { n: "Protection", p: 41, list: [{ n: "Dernier rempart", r: 1, m: 1 }] }],
    recipes: { Forge: { at: sec(7200), skill: 295, max: 300, list: [{ n: "Barre d'arcanite", i: 12360 }, { n: "Martelame d'arcanite", i: 19166 }] } },
    stats: { hp: 8900, power: 100, str: 320, agi: 140, sta: 520, armor: 11200, defense: 440, dodge: 9.8, parry: 11.2, block: 14.5, ap: 1350, crit: 9.1, hit: 6,
      resist: { fire: 75, nature: 0, frost: 0, shadow: 0, arcane: 0 } },
    lockouts: [{ n: "Cœur du Magma", raid: true, size: 40, reset, done: 10, total: 10 }],
  });

  members.push({
    guild_key: key, name: `Parti-${realm}`, rank: "Membre", rank_index: 3, level: 60, class: "ROGUE",
    in_guild: false, left_at: iso(10 * D), last_online: iso(12 * D), guild_professions: {},
  });

  return {
    guilds: [{
      key, name: "Les Éternels", realm, info: {
        motd: "Raid Molten Core jeudi 21h – flacons obligatoires !",
        bank: { at: Math.floor(now / 1000) - 5400, money: 1234567, tabs: [
          { name: "Consommables", viewable: true, items: [{ i: 13510, n: "Flacon des Titans", c: 4, q: 1 }, { i: 13444, n: "Potion de mana excellente", c: 40, q: 1 }] },
          { name: "Composants", viewable: true, items: [{ i: 12360, n: "Barre d'arcanite", c: 7, q: 2 }, { i: 7078, n: "Essence de feu", c: 22, q: 2 }, { i: 17010, n: "Cœur ardent", c: 3, q: 3 }] },
        ] },
      },
      ranks, scanned_at: iso(20 * 60e3), scanned_by: `Aelwyn-${realm}`,
    }],
    members,
    notes: { [`${key}|Grizzh-${realm}`]: "Absent jusqu'à fin novembre (prévenu sur Discord)", [`${key}|Brakk-${realm}`]: "Candidat officier" },
  };
};
