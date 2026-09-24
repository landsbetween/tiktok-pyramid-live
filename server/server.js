// Pyramid Live — TikTok LIVE event bridge
// Connects to TikTok LIVE (no login needed), listens for gifts/follows/likes/chat
// and relays them to the Godot game over WebSocket (ws://127.0.0.1:3001).
// Based on the Snake Live server.

const express = require('express');
const http = require('http');
const { WebSocketServer } = require('ws');

const PORT = Number(process.env.PORT || 3001);
const USERNAME = (process.argv[2] || process.env.TIKTOK_USER || '').replace(/^@/, '');
const BLOCKS_PER_DIAMOND = Number(process.env.BLOCKS_PER_DIAMOND || 10); // 1 💎 = 10 blocks
const BLOCKS_PER_FOLLOW = Number(process.env.BLOCKS_PER_FOLLOW || 5);
const LIKES_PER_BLOCK = Number(process.env.LIKES_PER_BLOCK || 5);
// Gifts that shake the pyramid and knock off the top blocks instead of adding blocks.
const QUAKE_GIFTS = (process.env.QUAKE_GIFTS || 'GG,Fireworks,Boxing Gloves,Rocket').split(',').map((s) => s.trim().toLowerCase());

const app = express();
app.use(express.json());
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

const builders = new Map(); // uniqueId -> {id, name, avatar, coins}
let tiktokStatus = { connected: false, username: USERNAME, error: null };

function broadcast(msg) {
  const s = JSON.stringify(msg);
  for (const c of wss.clients) if (c.readyState === 1) c.send(s);
}

function userInfo(u = {}) {
  return {
    // tiktok-live-connector 2.x: the @handle is in displayId, uniqueId is often empty
    id: u.uniqueId || u.displayId || u.userId || u.id || 'anon',
    name: u.nickname || u.uniqueId || u.displayId || 'Anonymous',
    avatar:
      u.profilePicture?.url?.[0] ||
      u.profilePicture?.urls?.[0] ||
      u.avatarThumb?.urlList?.[0] ||
      u.avatarThumb?.url?.[0] ||
      null,
  };
}

function addCoins(user, coins) {
  const cur = builders.get(user.id) || { ...user, coins: 0 };
  cur.coins += coins;
  cur.name = user.name;
  if (user.avatar) cur.avatar = user.avatar;
  builders.set(user.id, cur);
}

function handleGift(user, giftName, diamonds, count) {
  const coins = Math.max(1, diamonds) * count;
  addCoins(user, coins);
  if (QUAKE_GIFTS.includes(String(giftName).toLowerCase())) {
    return broadcast({ type: 'quake', user, giftName, diamonds, count, coins, power: coins });
  }
  broadcast({ type: 'gift', user, giftName, diamonds, count, coins, blocks: Math.max(1, Math.round(coins * BLOCKS_PER_DIAMOND)) });
}
const handleFollow = (user) => broadcast({ type: 'follow', user, blocks: BLOCKS_PER_FOLLOW });
const handleLike = (user, likes) => broadcast({ type: 'like', user, likes });
const handleChat = (user, text) => broadcast({ type: 'chat', user, text });
const handleJoin = (user) => broadcast({ type: 'join', user });

const perf = new Map(); // latest frame stats reported by each game client
wss.on('connection', (ws) => {
  const id = Math.random().toString(36).slice(2, 7);
  ws.on('message', (m) => { try { const d = JSON.parse(m); if (d.type === 'perf') perf.set(id, { ...d, at: Date.now() }); } catch {} });
  ws.on('close', () => perf.delete(id));
  ws.send(JSON.stringify({
    type: 'snapshot',
    builders: [...builders.values()],
    tiktok: tiktokStatus,
    config: { blocksPerDiamond: BLOCKS_PER_DIAMOND, blocksPerFollow: BLOCKS_PER_FOLLOW, likesPerBlock: LIKES_PER_BLOCK, quakeGifts: QUAKE_GIFTS },
  }));
});

// Test events without a live stream:
// curl -X POST localhost:3001/api/sim -H "content-type: application/json" -d "{\"type\":\"gift\",\"diamonds\":5}"
app.post('/api/sim', (req, res) => {
  const b = req.body || {};
  const user = { id: b.id || 'tester', name: b.name || 'Tester', avatar: b.avatar || null };
  if (b.type === 'gift') handleGift(user, b.giftName || 'Rose', Number(b.diamonds || 1), Number(b.count || 1));
  else if (b.type === 'follow') handleFollow(user);
  else if (b.type === 'like') handleLike(user, Number(b.likes || 1));
  else if (b.type === 'chat') handleChat(user, String(b.text || 'wow'));
  else if (b.type === 'join') handleJoin(user);
  else return res.status(400).json({ ok: false, error: 'unknown type' });
  res.json({ ok: true });
});
app.get('/api/perf', (_req, res) => res.json([...perf.values()]));
app.get('/api/status', (_req, res) => res.json({ tiktok: tiktokStatus, builders: builders.size, clients: wss.clients.size }));

async function connectTikTok() {
  if (!USERNAME) {
    console.log('ℹ️  No TikTok username given. Usage: node server.js <username>. Use /api/sim or the demo keys in the game.');
    return;
  }
  const { TikTokLiveConnection, WebcastEvent, ControlEvent } = require('tiktok-live-connector');
  const conn = new TikTokLiveConnection(USERNAME, {
    processInitialData: false,
    enableExtendedGiftInfo: false, // true needs a paid EulerStream plan; diamondCount comes with every gift anyway
    fetchRoomInfoOnConnect: true,
  });

  conn.on(WebcastEvent.GIFT, (d) => {
    // Streakable gifts (giftType 1) are counted once the streak ends
    const giftType = d.giftDetails?.giftType ?? d.giftType;
    if (giftType === 1 && !d.repeatEnd) return;
    const diamonds = d.diamondCount ?? d.giftDetails?.diamondCount ?? d.extendedGiftInfo?.diamond_count ?? 1;
    const name = d.giftDetails?.giftName ?? d.giftName ?? d.extendedGiftInfo?.name ?? 'Gift';
    handleGift(userInfo(d.user), name, Number(diamonds), Number(d.repeatCount || 1));
  });
  conn.on(WebcastEvent.FOLLOW, (d) => handleFollow(userInfo(d.user)));
  conn.on(WebcastEvent.LIKE, (d) => handleLike(userInfo(d.user), Number(d.count ?? d.likeCount ?? 1)));
  conn.on(WebcastEvent.CHAT, (d) => handleChat(userInfo(d.user), d.comment || ''));
  conn.on(WebcastEvent.MEMBER, (d) => handleJoin(userInfo(d.user)));
  conn.on(WebcastEvent.STREAM_END, () => {
    tiktokStatus = { ...tiktokStatus, connected: false, error: 'stream ended' };
    broadcast({ type: 'tiktok', ...tiktokStatus });
  });
  conn.on('disconnected', () => {
    tiktokStatus = { ...tiktokStatus, connected: false };
    broadcast({ type: 'tiktok', ...tiktokStatus });
    console.log('⚠️  Disconnected, reconnecting in 10s');
    setTimeout(tryConnect, 10000);
  });
  conn.on('error', (e) => console.error('TikTok error:', e?.message || e));

  let connecting = false;
  // Stale-connection guard: TikTok sometimes keeps the socket open but stops sending.
  // Any raw frame counts as a sign of life; after 60 s of silence while "connected", reconnect.
  let lastData = Date.now();
  conn.on(ControlEvent.WEBSOCKET_DATA, () => { lastData = Date.now(); });
  setInterval(async () => {
    if (conn.isConnected && Date.now() - lastData > 60000) {
      console.log('⚠️  No data from TikTok for 60s, reconnecting...');
      lastData = Date.now();
      try { await conn.disconnect(); } catch {}
      setTimeout(tryConnect, 1000);
    }
  }, 15000);

  async function tryConnect() {
    if (connecting || conn.isConnected) return;
    connecting = true;
    try {
      const state = await conn.connect();
      tiktokStatus = { connected: true, username: USERNAME, error: null, roomId: state.roomId };
      console.log(`✅ Connected to @${USERNAME}, roomId ${state.roomId}`);
    } catch (e) {
      tiktokStatus = { connected: false, username: USERNAME, error: e?.message || String(e) };
      console.error('❌ Connection failed:', tiktokStatus.error, '- retrying in 20s');
      setTimeout(tryConnect, 20000);
    }
    connecting = false;
    broadcast({ type: 'tiktok', ...tiktokStatus });
  }
  tryConnect();

  // Watchdog: a new "Go LIVE" creates a new room. Reconnect when the room id changes.
  const probe = new TikTokLiveConnection(USERNAME, { processInitialData: false, fetchRoomInfoOnConnect: false });
  setInterval(async () => {
    try {
      const rid = String(await probe.fetchRoomId());
      if (rid && rid !== String(tiktokStatus.roomId || '')) {
        console.log(`🔄 New LIVE room detected (${tiktokStatus.roomId || '-'} -> ${rid}), reconnecting...`);
        try { await conn.disconnect(); } catch {}
        setTimeout(tryConnect, 1000);
      }
    } catch { /* offline or lookup failed: try again next tick */ }
  }, 45000);
}

server.listen(PORT, '127.0.0.1', () => {
  console.log(`🔺 Pyramid Live bridge: ws://127.0.0.1:${PORT}  (status: http://127.0.0.1:${PORT}/api/status)`);
  connectTikTok();
});
