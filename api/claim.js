// Point d'entrée quand Vercel déploie depuis la racine du dépôt.
// (Si Root Directory = web, Vercel utilise directement web/api/claim.js.)
module.exports = require("../web/api/claim.js");
