local M = {}
local blocked = require("roarkt_english_blocklist")

-- Complete spellings supported by the bundled Luna Pinyin syllabary. Requiring
-- complete syllables deliberately excludes initials and correction algebra.
-- Ambiguous English/pinyin (can, shi, etc.) continues to prefer Chinese.
local syllables = {}
for spelling in ([[
a ai an ang ao
ba bai ban bang bao bei ben beng bi bian biang biao bie bin bing bo bu
ca cai can cang cao ce cei cen ceng cha chai chan chang chao che chen cheng chi chong chou chu chua chuai chuan chuang chui chun chuo ci cong cou cu cuan cui cun cuo
da dai dan dang dao de dei den deng di dia dian diao die din ding diu dong dou du duan dui dun duo
e eh ei en eng er
fa fan fang fei fen feng fiao fo fong fou fu
ga gai gan gang gao ge gei gen geng gong gou gu gua guai guan guang gui gun guo
ha hai han hang hao he hei hen heng hong hou hu hua huai huan huang hui hun huo
ji jia jian jiang jiao jie jin jing jiong jiu ju juan jue jun
ka kai kan kang kao ke kei ken keng kong kou ku kua kuai kuan kuang kui kun kuo
la lai lan lang lao le lei leng li lia lian liang liao lie lin ling liu lo long lou lu luan lun luo lv lvan lve
ma mai man mang mao me mei men meng mi mian miao mie min ming miu mo mou mu
na nai nan nang nao ne nei nen neng ni nia nian niang niao nie nin ning niu nong nou nu nuan nun nuo nv nve
o ou
pa pai pan pang pao pei pen peng pi pia pian piao pie pin ping po pou pu
qi qia qian qiang qiao qie qin qing qiong qiu qu quan que qun
ran rang rao re ren reng ri rong rou ru rua ruan rui run ruo
sa sai san sang sao se sei sen seng sha shai shan shang shao she shei shen sheng shi shou shu shua shuai shuan shuang shui shun shuo si song sou su suan sui sun suo
ta tai tan tang tao te tei teng ti tian tiao tie ting tong tou tu tuan tui tun tuo
wa wai wan wang wei wen weng wo wong wu
xi xia xian xiang xiao xie xin xing xiong xiu xu xuan xue xun
ya yai yan yang yao ye yi yin ying yo yong you yu yuan yue yun
za zai zan zang zao ze zei zen zeng zha zhai zhan zhang zhao zhe zhei zhen zheng zhi zhong zhou zhu zhua zhuai zhuan zhuang zhui zhun zhuo zi zong zou zu zuan zui zun zuo
]]):gmatch("%S+") do syllables[spelling] = true end

local function complete_pinyin(raw)
  for part in raw:gmatch("[^ ']+") do
    local reachable = {[0] = true}
    for finish = 1, #part do
      for length = 1, math.min(6, finish) do
        if reachable[finish - length] and syllables[part:sub(finish - length + 1, finish)] then
          reachable[finish] = true
          break
        end
      end
    end
    if not reachable[#part] then return false end
  end
  return true
end

function M.init(env)
  -- Query the existing table translator; never load/materialize the word list
  -- in Lua, and retain genuine dictionary candidates for user learning.
  env.english_lookup = Component.Translator(env.engine, "english", "table_translator")
end

local function english_match(env)
  if not env or not env.english_lookup then return nil end
  local context = env.engine.context
  if context.composition:empty() then return nil end
  local segment = context.composition:back()
  local raw = context.input:sub(segment.start + 1, segment._end)
  local flypy = env.engine.schema and env.engine.schema.schema_id == "roarkt_flypy"
  if #raw > 64 or not raw:match("^[a-z]+$") then return nil end
  -- Double-pinyin codes are not full spellings. Conservatively promote only
  -- exact English words >=4 letters; never promote a Flypy prefix completion.
  if flypy then
    if #raw < 4 then return nil end
  elseif #raw < 3 or complete_pinyin(raw) then return nil end
  local translation = env.english_lookup:query(raw, segment)
  if not translation then return nil end
  -- One dictionary pull, even if the English item is far down the merged stream.
  for candidate in translation:iter() do
    if blocked.contains(candidate.text) then return nil end
    local code = candidate.text:lower():gsub("[^a-z]", "")
    if candidate._start == segment.start and candidate._end == segment._end
        and ((flypy and code == raw) or (not flypy and code:sub(1, #raw) == raw)) then return candidate end
    break
  end
end

local function same_entry(a, b)
  return a.text:lower() == b.text:lower() and a._start == b._start and a._end == b._end
end

local function can_lead(candidate)
  return candidate.type ~= "roarkt_english_echo"
      and not candidate.text:match("^[%z\1-\127]*$")
end

-- Preserve the established ordering, but only pull as much as the consumer
-- needs. In particular, the first Chinese page need not locate a distant echo.
function M.func(input, env)
  local iterator, state, control = input:iter()
  local ended = false
  local function take()
    while not ended do
      local candidate = iterator(state, control)
      control = candidate
      if not candidate then ended = true; return nil end
      if not blocked.contains(candidate.text) then
        return candidate
      end
    end
  end

  local promoted = english_match(env)
  if promoted then
    local first = take()
    -- Preserve a leading Chinese choice (also conservative for double pinyin).
    -- Otherwise the dictionary match may lead an echo/English-only stream.
    if first and can_lead(first) then yield(first) end
    yield(promoted)
    if first and not can_lead(first) and not same_entry(first, promoted) then yield(first) end
    while true do
      local candidate = take()
      if not candidate then return end
      if not same_entry(candidate, promoted) then yield(candidate) end
    end
  end

  local first = take()
  if not first then return end
  local primary, echo
  local buffered = {}
  if can_lead(first) then
    primary = first
  else
    -- Until both a promotable candidate and an echo exist, the original order
    -- might still be required. This ambiguous prefix cannot safely be streamed.
    local prefix = {first}
    local echo_index = first.type == "roarkt_english_echo" and 1 or nil
    local primary_index
    while not (echo_index and primary_index) do
      local candidate = take()
      if not candidate then
        for _, value in ipairs(prefix) do yield(value) end
        return
      end
      table.insert(prefix, candidate)
      if not echo_index and candidate.type == "roarkt_english_echo" then echo_index = #prefix end
      if not primary_index and can_lead(candidate) then primary_index = #prefix end
    end
    primary, echo = prefix[primary_index], prefix[echo_index]
    for index, candidate in ipairs(prefix) do
      if index ~= primary_index and index ~= echo_index then table.insert(buffered, candidate) end
    end
  end

  local cursor, buffered_count = 1, #buffered
  local function next_regular()
    if cursor <= buffered_count then
      local candidate = buffered[cursor]
      buffered[cursor] = nil
      cursor = cursor + 1
      return candidate
    end
    return take()
  end

  yield(primary)
  local leading = 1
  while leading < 7 do
    local candidate = next_regular()
    if not candidate then break end
    if not echo and candidate.type == "roarkt_english_echo" then
      echo = candidate
    else
      yield(candidate)
      leading = leading + 1
    end
  end

  -- Only a consumer asking for position eight pays for locating a late echo.
  -- With no echo this scan may reach the end; preserve order rather than guess.
  local before_echo = {}
  while not echo do
    local candidate = next_regular()
    if not candidate then break end
    if candidate.type == "roarkt_english_echo" then echo = candidate
    else table.insert(before_echo, candidate) end
  end
  if echo then yield(echo) end
  for index = 1, #before_echo do
    local candidate = before_echo[index]
    before_echo[index] = nil
    yield(candidate)
  end
  while true do
    local candidate = next_regular()
    if not candidate then return end
    yield(candidate)
  end
end

return M
