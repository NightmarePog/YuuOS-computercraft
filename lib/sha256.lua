local sha256 = {}

local MOD = 2^32
local MODM = MOD-1

local function memoize(f)
  local mt = {}
  local t = setmetatable({}, mt)
  function mt:__index(k)
    local v = f(k)
    t[k] = v
    return v
  end
  return t
end

local function make_bitop(t, m)
  local function bitop(a, b, op)
    local res,p = 0,1
    while a ~= 0 and b ~= 0 do
      local am, bm = a % m, b % m
      res = res + t[am][bm]*p
      a = (a - am) / m
      b = (b - bm) / m
      p = p*m
    end
    res = res + (a + b) * p
    return res
  end
  return bitop
end

local bxor1 = make_bitop({
  [0] = {[0] = 0, [1] = 1},
  [1] = {[0] = 1, [1] = 0}
}, 2)

local function bxor(a, b, c, ...)
  local z = nil
  if b then
    a = a % MOD
    b = b % MOD
    z = bxor1(a, b)
    if c then z = bxor(z, c, ...) end
    return z
  elseif a then return a % MOD
  else return 0 end
end

local function band(a, b, c, ...)
  local z
  if b then
    a = a % MOD
    b = b % MOD
    z = ((a + b) - bxor1(a,b)) / 2
    if c then z = band(z, c, ...) end
    return z
  else return a % MODM end
end

local function rshift1(a, disp)
  if disp > 31 or disp < 0 then return 0 end
  return math.floor(a % 2^32 / 2^disp)
end

local function rrotate(x, disp)
  x = x % MOD
  disp = disp % 32
  local low = band(x, 2^disp-1)
  return rshift1(x, disp) + low * 2^(32-disp)
end

local k = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
}

local function str2hexa(s)
  return (string.gsub(s, ".", function(c) return string.format("%02x", string.byte(c)) end))
end

local function num2s(l, n)
  local s = ""
  for i = 1, n do
    local rem = l % 256
    s = string.char(rem) .. s
    l = (l - rem) / 256
  end
  return s
end

local function s232num(s, i)
  local n = 0
  for i = i, i + 3 do n = n*256 + string.byte(s, i) end
  return n
end

local function preproc(msg, len)
  local extra = 64 - ((len + 9) % 64)
  len = num2s(8 * len, 8)
  msg = msg .. "\128" .. string.rep("\0", extra) .. len
  assert(#msg % 64 == 0)
  return msg
end

local function initH224(H)
  H[1] = 0xc1059ed8
  H[2] = 0x367cd507
  H[3] = 0x3070dd17
  H[4] = 0xf70e5939
  H[5] = 0xffc00b31
  H[6] = 0x68581511
  H[7] = 0x64f98fa7
  H[8] = 0xbefa4fa4
  return H
end

local function initH256(H)
  H[1], H[2], H[3], H[4] = 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
  H[5], H[6], H[7], H[8] = 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
  return H
end

local function digestblock(msg, i, H)
  local w = {}
  for j = 1, 16 do w[j] = s232num(msg, i + (j - 1) * 4) end
  for j = 17, 64 do
    local v = w[j - 15]
    local s0 = bxor(rrotate(v, 7), rrotate(v, 18), rshift1(v, 3))
    v = w[j - 2]
    w[j] = (w[j - 16] + s0 + w[j - 7] + bxor(rrotate(v, 17), rrotate(v, 19), rshift1(v, 10))) % MOD
  end

  local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
  for i = 1, 64 do
    local s0 = bxor(rrotate(a, 2), rrotate(a, 13), rrotate(a, 22))
    local maj = bxor(band(a, b), band(a, c), band(b, c))
    local t2 = s0 + maj
    local s1 = bxor(rrotate(e, 6), rrotate(e, 11), rrotate(e, 25))
    local ch = bxor(band(e, f), band(bxor(e, MODM), g))
    local t1 = h + s1 + ch + k[i] + w[i]
    h = g
    g = f
    f = e
    e = (d + t1) % MOD
    d = c
    c = b
    b = a
    a = (t1 + t2) % MOD
  end

  H[1] = (H[1] + a) % MOD
  H[2] = (H[2] + b) % MOD
  H[3] = (H[3] + c) % MOD
  H[4] = (H[4] + d) % MOD
  H[5] = (H[5] + e) % MOD
  H[6] = (H[6] + f) % MOD
  H[7] = (H[7] + g) % MOD
  H[8] = (H[8] + h) % MOD
end

function sha256.hash(msg)
  msg = preproc(msg, #msg)
  local H = initH256({})
  for i = 1, #msg, 64 do digestblock(msg, i, H) end
  return str2hexa(num2s(H[1], 4) .. num2s(H[2], 4) .. num2s(H[3], 4) ..
    num2s(H[4], 4) .. num2s(H[5], 4) .. num2s(H[6], 4) ..
    num2s(H[7], 4) .. num2s(H[8], 4))
end

return sha256
