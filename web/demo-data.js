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
  members.push({
    guild_key: key, name: `Parti-${realm}`, rank: "Membre", rank_index: 3, level: 60, class: "ROGUE",
    in_guild: false, left_at: iso(10 * D), last_online: iso(12 * D), guild_professions: {},
  });

  return {
    guilds: [{
      key, name: "Les Éternels", realm, info: { motd: "Raid Molten Core jeudi 21h – flacons obligatoires !" },
      ranks, scanned_at: iso(20 * 60e3), scanned_by: `Aelwyn-${realm}`,
    }],
    members,
    notes: { [`${key}|Grizzh-${realm}`]: "Absent jusqu'à fin novembre (prévenu sur Discord)", [`${key}|Brakk-${realm}`]: "Candidat officier" },
  };
};
