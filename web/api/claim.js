// POST /api/claim  (fonction serverless Vercel, aucune dépendance)
//
// Appelée par le site juste après la connexion Discord. Vérifie que la personne
// est bien sur le serveur Discord de la guilde, et si elle a un rôle officier,
// puis enregistre son accès dans Supabase (table site_access).
//
// Variables d'environnement Vercel :
//   SUPABASE_URL               https://xxxx.supabase.co
//   SUPABASE_SERVICE_ROLE_KEY  clé secrète (service_role / sb_secret_...)
//   DISCORD_GUILD_ID           ID du serveur Discord de la guilde
//   DISCORD_OFFICER_ROLE_IDS   IDs des rôles officiers, séparés par des virgules

function keyHeaders(key) {
  // Les anciennes clés sont des JWT (eyJ...) : on les passe aussi en Bearer.
  return key.startsWith("eyJ") ? { apikey: key, Authorization: `Bearer ${key}` } : { apikey: key };
}

module.exports = async (req, res) => {
  if (req.method !== "POST") return res.status(405).json({ error: "POST uniquement" });

  const {
    SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, DISCORD_GUILD_ID, DISCORD_OFFICER_ROLE_IDS = "",
  } = process.env;
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !DISCORD_GUILD_ID) {
    return res.status(500).json({ error: "Configuration serveur incomplète" });
  }

  const jwt = (req.headers.authorization || "").replace(/^Bearer\s+/i, "");
  const providerToken = req.body && req.body.providerToken;
  if (!jwt || !providerToken) return res.status(400).json({ error: "Session ou jeton Discord manquant" });

  // 1. Qui est connecté côté Supabase ?
  const userRes = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${jwt}` },
  });
  if (!userRes.ok) return res.status(401).json({ error: "Session invalide" });
  const user = await userRes.json();
  const identity = (user.identities || []).find((i) => i.provider === "discord");
  const discordId = (identity && (identity.identity_data?.provider_id || identity.identity_data?.sub || identity.id))
    || user.user_metadata?.provider_id;
  if (!discordId) return res.status(403).json({ error: "Compte non lié à Discord" });

  // 2. Est-il sur le serveur Discord de la guilde ?
  const memberRes = await fetch(`https://discord.com/api/v10/users/@me/guilds/${DISCORD_GUILD_ID}/member`, {
    headers: { Authorization: `Bearer ${providerToken}` },
  });

  const accessUrl = `${SUPABASE_URL}/rest/v1/site_access`;
  const adminHeaders = { ...keyHeaders(SUPABASE_SERVICE_ROLE_KEY), "Content-Type": "application/json" };

  if (memberRes.status === 404) {
    // Pas (ou plus) sur le serveur : on retire l'accès.
    await fetch(`${accessUrl}?user_id=eq.${encodeURIComponent(user.id)}`, { method: "DELETE", headers: adminHeaders });
    return res.status(403).json({ error: "Tu n'es pas sur le serveur Discord de la guilde." });
  }
  if (!memberRes.ok) {
    return res.status(502).json({ error: `Discord a répondu ${memberRes.status}` });
  }
  const member = await memberRes.json();
  if (!member.user || member.user.id !== discordId) {
    return res.status(403).json({ error: "Le jeton Discord ne correspond pas au compte connecté" });
  }

  const officerRoles = DISCORD_OFFICER_ROLE_IDS.split(",").map((s) => s.trim()).filter(Boolean);
  const role = (member.roles || []).some((r) => officerRoles.includes(r)) ? "officer" : "member";
  const name = member.nick || member.user.global_name || member.user.username;

  // 3. Enregistre l'accès (valable 30 jours, renouvelé à chaque connexion).
  const up = await fetch(`${accessUrl}?on_conflict=user_id`, {
    method: "POST",
    headers: { ...adminHeaders, Prefer: "resolution=merge-duplicates,return=minimal" },
    body: JSON.stringify({
      user_id: user.id, discord_id: discordId, discord_name: name, role, checked_at: new Date().toISOString(),
    }),
  });
  if (!up.ok) return res.status(500).json({ error: `Supabase a répondu ${up.status}` });

  return res.status(200).json({ role, name });
};
