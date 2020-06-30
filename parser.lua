local index_G = { __index = _G }
local _ENV = setmetatable({ _G = _G}, index_G) -- Declare sandbox

local view = require "debugview"
local StringIndexer = require "StringIndexer"
local list = require "SinglyLinkedList"

null = list.null
cons = list.cons

pattern, kw, keywordExports, Name, Number, Whitespace = true, true, true, true, true, true -- Declared here as they are referenced in the higher order patterns

local function toChars(str)
  local out = {}
  
  for c in str:gmatch(".") do
    out[#out + 1] = c
  end
  
  return out
end

function isWhitespace(value)
  return (value == ' '
       or value == '\r'
       or value == '\n')
end

function skipWhitespace(strIdx)
  local idx = strIdx:getIndex()
  local value = strIdx:getValue(idx)
  local collectedWhitespace = {}
  
  while isWhitespace(value) do
    collectedWhitespace[#collectedWhitespace + 1] = value
    idx = idx + 1
    value = strIdx:getValue(idx)
  end
  
  return idx, idx > strIdx:getIndex()
end

-- TODO This needs to be revisited
function skipComments(strIdx)
  local idx = strIndex:getIdx()

  if  (strIdx:getValue(idx) == '-') 
  and (strIdx:getValue(idx + 1) == '-') 
  then
    local multiline = strIdx:getValue(idx + 2) == '[' 
                  and strIdx:getValue(idx + 3) == '['
    idx = idx + (multiline and 4 or 2)
    
    if multiline then
      repeat
        idx = idx + 1
      until (strIdx:getValue(idx) == ']' 
        and  strIdx:getValue(idx - 1) == ']')
    else
      while not (strIdx:getValue(idx) == '\n') do
        idx = idx + 1
      end
    end
    
    return idx + 1
  else
    return idx
  end
end

local function contains(tbl, val)
  for k,v in pairs(tbl) do
    if v == val then return k, v end
  end
  return false
end

local function definitionNeedsDelimiter(pat)
  return pat == Name
      or pat == Number
end

local function getterSetter(key)
  return function(tbl) return tbl[key] end, 
         function(tbl, value) tbl[key] = value return tbl end
end

local isKeyword, markAsKeyword = getterSetter("isKeyword")
local needsWhitespace, markAsNeedsWhitespace = getterSetter("needsWhitespace")

local function copyRightPatternKeywordiness(right, pat)
  pat.trailingKeyword = right.isKeyword
  return pat
end

local function setValue(tbl, val, idx)
  tbl[idx] = val
  return tbl
end

local parsedLogCharLimit = 35

local function _logOptional(msg1, pat, msg2, strIdx, msg3, parsed)
  local stringValue = tostring(pat)

  if (not (stringValue == "ignore" and type(pat) == "table")) then
    if msg2 then
      print(msg1, stringValue, msg2, strIdx, msg3, parsed and table.concat(parsed:take(parsedLogCharLimit)))
    else
      print(msg1, pat)
    end
  end
end


local function stub() end

-- Exchange print and indentedPrint to 'stub' to disable logging.
local _print = print
local print = _print

local logOptional = stub --_logOptional

--[========]--
--|Lateinit|--------------------------------------------------------------------------------------------------
--[========]--

local lateinitRepo = {}
local lateinitNames = {}

-- Permit circular references using a promise stored in the 'lateinitNames' table
function lateinit(childPatternName)
  lateinitNames[childPatternName] = true
  local childPattern
  
  return pattern(function(strIdx, parsed)
    if not childPattern then
      childPattern = lateinitRepo[childPatternName]
      if not childPattern then error("Cannot load lateinit: " .. (childPatternName or "[No name]")) end
    end
    
    return childPattern(strIdx, parsed)
  end) * childPatternName
end

-- Initialise all promised references by drawing them from the provided table
function initialiseLateInitRepo()
  for name, _ in pairs(lateinitNames) do
    lateinitRepo[name] = _ENV[name]
  end
end

--[=====================]--
--|Higher Order Patterns|-------------------------------------------------------------------------------------
--[=====================]--

-- Advance pointer if contents of table matches eluChars at idx
local function kwCompare(keyword, strIdx, parsed)
  local pos = strIdx:getIndex()

  for _, c in ipairs(keyword) do
    if c ~= strIdx:getValue(pos) then
      return false
    end
    pos = pos + 1
  end
  
  return strIdx:withIndex(pos), cons(tostring(keyword), parsed)
end

-- Pattern AND operator
local function patternIntersection(left, right)
  if not left then error("Missing left pattern") end
  if not right then error("Missing right pattern") end
  
  local leftIsKeyword = isKeyword(left)
  local enforceWhitespace = needsWhitespace(left) and needsWhitespace(right)
  
  if enforceWhitespace then print("Enforcing whitespace for keys of ", left, "and", right) end
  
  return copyRightPatternKeywordiness(right, pattern(function(strIdx, parsed)
    logOptional("About to run intersection left:", left)
    local leftStrIdx, leftParsed = left(strIdx, parsed)
    logOptional("INTERSECTION LEFT PATTERN", left, "LEFT STR IDX", leftStrIdx, "PRODUCED", leftParsed)
    
    if leftStrIdx then
      local whitespaceStrIdx, whitespaceParsed = leftStrIdx, leftParsed
      
      if enforceWhitespace then
        whitespaceStrIdx, whitespaceParsed = Whitespace(leftStrIdx, leftParsed)
        whitespaceParsed = cons(' ', whitespaceParsed)
      end
      
      if whitespaceStrIdx then
        logOptional("About to run intersection right:", right)
        local rightStrIdx, rightParsed = right(whitespaceStrIdx, whitespaceParsed)
        logOptional("INTERSECTION RIGHT PATTERN", right, "RIGHT STR IDX", rightStrIdx, "PRODUCED", rightParsed)
        
        if rightStrIdx then        
          return rightStrIdx, rightParsed
        else
          if leftIsKeyword then
            error(string.format("Unable to parse after keyword: %s\nAt position: %s\nWith parsed of %s\n", left, leftStrIdx, leftParsed))
          end
        end
      end
    end
    
    return false
  end)) * ("(" .. tostring(left) .. " + " .. tostring(right) .. ")")
end

-- Pattern OR operator
local function patternUnion(left, right)
  if not left then error("Missing left pattern") end
  if not right then error("Missing right pattern") end
  
  return pattern(function(strIdx, parsed)
    logOptional("Union about to run left:", left)
    local leftStrIdx, leftParsed = left(strIdx, parsed)
    logOptional("UNION LEFT PATTERN", left, "LEFT STR IDX", leftStrIdx, "PRODUCED", leftParsed)
    
    if leftStrIdx then
      return leftStrIdx, leftParsed 
    end
    
    logOptional("\nUnion about to run right:", right)
    local rightStrIdx, rightParsed = right(strIdx, parsed)
    logOptional("UNION RIGHT PATTERN", right, "RIGHT STR IDX", rightStrIdx, "PRODUCED", rightParsed)
    
    return rightStrIdx, rightParsed
  end) * ("(" .. tostring(left) .. " / " .. tostring(right) .. ")")
end

-- Pattern appears zero or one times. Similar to '?' in regex
function maybe(childPattern)
  if not childPattern then error("Missing child pattern") end
  
  return pattern(function(strIdx, parsed)
    local childStrIdx, childParsed = childPattern(strIdx, parsed)
    
    if childStrIdx then
      return childStrIdx, childParsed
    else
      return strIdx, parsed
    end
  end) * ("maybe(" .. tostring(childPattern) .. ")")
end 

-- Pattern appears one or more times. Similar to '+' in regex
--[[
function many(childPattern)
  if not childPattern then error("Missing child pattern") end
  
  return pattern(function(strIdx, parsed)
    local function unpackReturn(packed)
      if packed then
        return packed[1], packed[2]
      else
        return false
      end
    end
  
    local function matchChildPattern(strIdx, parsed)
      local childStrIdx, childParsed = childPattern(strIdx, parsed)
      
      return childStrIdx
         and (matchChildPattern(childStrIdx, childParsed)
              or { childStrIdx, childParsed })
    end
    
    return unpackReturn(matchChildPattern(strIdx, parsed))
  end) * ("many(" .. tostring(childPattern) .. ")")
end]]

function many(childPattern)
	if not childPattern then error("Missing child pattern") end
  
  local function recurse(strIdx, parsed) 
    return (childPattern + maybe(many(childPattern)))(strIdx, parsed)
  end
  
  return pattern(recurse)
end

-- Pattern appears zero or more times. Similar to '*' in regex
function maybemany(childPattern)
  return maybe(many(childPattern))
end

-- Variables cannot share a name with a keyword. This rule clears up otherwise ambiguous syntax
-- Also packs variable names (see packString for details)
function checkNotKeywordThenPack(childPattern)
  if not childPattern then error("Missing child pattern") end
  
  return pattern(function(strIdx, parsed)
    local returnedStrIdx, returnedParsed = childPattern(strIdx, null)
    
    if not returnedStrIdx then return false end
    
    local whatChildParsed = returnedParsed:take()
    print("checkNotKeywordThenPack: whatChildParsed:", table.concat(whatChildParsed))
    local parsedIndexer = StringIndexer.new(whatChildParsed, 1)
    
    local function loop(gen, tbl, state)
      local kwName, kwParser = gen(tbl, state)
    
      return kwParser
         and ((#kwParser == #whatChildParsed and kwParser(parsedIndexer, null))
              or loop(gen, tbl, kwName))
    end
    
    local matchesAnyKeyword = loop(pairs(keywordExports))
        
    if matchesAnyKeyword then
      print("checkNotKeywordThenPack: That's a keyword!")
      return false
    else
      local packed = table.concat(whatChildParsed)
      print("checkNotKeywordThenPack: packing value to be:", packed)
      return returnedStrIdx, cons(packed, parsed)
    end
  end) * ("checkNotKeywordThenPack(" .. tostring(childPattern) .. ")")
end

-- All syntax is delimited with spaces in the output.
-- A string put through this would come out as " e n d ".
-- This function packs the child patterns into a single string, which is delimited correctly.
function packString(childPattern)
  if not childPattern then error("Missing child pattern") end
  
  return pattern(function(strIdx, parsed)
    local returnedStrIdx, returnedParsed = childPattern(strIdx, null)
    
    if not returnedStrIdx then return false end
    
    local packed = tostring(returnedParsed)
    print("packString: packing value to be:", packed)
    return returnedStrIdx, cons(packed, parsed)
  end) * ("packString(" .. tostring(childPattern) .. ")")
end

-- Consumes a single character given that childPattern fails to match.
function notPattern(childPattern)
  if not childPattern then error("Missing child pattern") end
  
  return pattern(function(strIdx, parsed)
    local value = strIdx:getValue()
  
    return value
       and not childPattern(strIdx, parsed)
       and strIdx:withFollowingIndex(), cons(value, parsed)
  end) * ("notPattern(" .. tostring(childPattern) .. ")")
end

--[==========]--
--|Metatables|------------------------------------------------------------------------------------------------
--[==========]--

--- The value of tostring may not be clear when the pattern is initially constructed. This function lets you bind tostring at a later point.
local function attachLabel(tbl, name)
  getmetatable(tbl).__tostring = function() return name end
  return tbl
end

pattern = function(fn)
  return setmetatable({}, { 
    __call = function(_, strIdx, parsed)
               return fn(strIdx, parsed)
             end,
    __add = patternIntersection, 
    __div = patternUnion, 
    __mul = attachLabel
  })
end

kw = function(str)
  local spacedStr = " " .. str .. " "
  
  return sym(str, spacedStr)
end

sym = function(matchStr, tostringStr)
  local tostringStr = tostringStr or matchStr
  local charTable = toChars(matchStr)
  charTable.isKeyword = true -- excluded from kwCompare as it only checks the array
  
  return setmetatable(markAsNeedsWhitespace(charTable), { 
    __call = kwCompare, 
    __add = patternIntersection, 
    __div = patternUnion,
    __len = function() return #matchStr end,
    __tostring = function() return tostringStr end
  })
end

--[===================]--
--|Loading and exports|---------------------------------------------------------------------------------------
--[===================]--

local function loadFile(address)
  local fn, message = loadfile(address, "t", _ENV)
  return fn and fn() or error(message)
end

-- Load terminals
keywordExports = loadFile("terminals.lua")

setmetatable(_ENV, { __index = keywordExports }) -- Add keywords to environment
_G.setmetatable(keywordExports, index_G) -- Ensure that _G is still accessible

local entrypoint = loadFile("ebnf.lua") -- Declare lua eBNF. Entrypoint is 'block'

local function parseChars(chars)
  local _, parsedStrs = entrypoint(StringIndexer.new(chars, 1), null)
  return tostring(parsedStrs)
end

local function parseString(str)
  return parseChars(toChars(str))
end

return { parseString = parseString, parseChars = parseChars }
