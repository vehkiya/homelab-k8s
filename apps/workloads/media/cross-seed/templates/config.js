// Seeded once on first boot by gomplate into /config/config.js; v7 imports this
// (including indexers) into /config/cross-seed.db and renames it to config.js.bak.
// Subsequent changes are managed via the Web UI (Settings).
module.exports = {
  apiKey: "{{ .Env.API_KEY }}",

  torznab: [
    "http://prowlarr-ui.media.svc.cluster.local:9696/1/api?apikey={{ .Env.PROWLARR_API_KEY }}",  // seedpool
    "http://prowlarr-ui.media.svc.cluster.local:9696/2/api?apikey={{ .Env.PROWLARR_API_KEY }}",  // TorrentLeech
    "http://prowlarr-ui.media.svc.cluster.local:9696/4/api?apikey={{ .Env.PROWLARR_API_KEY }}",  // Milkie
    "http://prowlarr-ui.media.svc.cluster.local:9696/5/api?apikey={{ .Env.PROWLARR_API_KEY }}",  // DigitalCore
    "http://prowlarr-ui.media.svc.cluster.local:9696/7/api?apikey={{ .Env.PROWLARR_API_KEY }}",  // InfinityHD
    "http://prowlarr-ui.media.svc.cluster.local:9696/10/api?apikey={{ .Env.PROWLARR_API_KEY }}", // AnimeZ
    "http://prowlarr-ui.media.svc.cluster.local:9696/11/api?apikey={{ .Env.PROWLARR_API_KEY }}", // FileList.io
  ],

  sonarr: [
    "http://sonarr-tv-ui.media.svc.cluster.local:8989/tv?apikey={{ .Env.SONARR_TV_API_KEY }}",
    "http://sonarr-anime-ui.media.svc.cluster.local:8989/anime?apikey={{ .Env.SONARR_ANIME_API_KEY }}",
  ],

  radarr: [
    "http://radarr-ui.media.svc.cluster.local:7878?apikey={{ .Env.RADARR_API_KEY }}",
  ],

  host: "0.0.0.0",
  port: 2468,

  notificationWebhookUrls: [],

  torrentClients: [
    "qbittorrent:http://qbittorrent-ui.media.svc.cluster.local:8080",
  ],

  useClientTorrents: true,
  delay: 30,

  dataDirs: [
    "/data/media/tv",
    "/data/media/anime",
    "/data/media/movies",
  ],

  linkCategory: "cross-seed-link",
  linkDirs: [
    "/data/torrents/cross-seed",
  ],
  linkType: "hardlink",
  flatLinking: false,

  matchMode: "partial",
  skipRecheck: true,
  autoResumeMaxDownload: 52428800,
  ignoreNonRelevantFilesToResume: false,
  maxDataDepth: 2,

  includeSingleEpisodes: false,
  includeNonVideos: false,
  seasonFromEpisodes: 1,
  fuzzySizeThreshold: 0.02,

  excludeOlder: "2 weeks",
  excludeRecentSearch: "3 days",

  action: "inject",
  duplicateCategories: false,

  rssCadence: "30 minutes",
  searchCadence: "1 day",
  snatchTimeout: "30 seconds",
  searchTimeout: "2 minutes",
  searchLimit: 400,

  blockList: [],
};
